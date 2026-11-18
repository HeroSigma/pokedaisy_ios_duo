// PokeDaisy for iPhone: the session's host (see pd_ios.h). What the 3DS's main.c does with its GPU, ndsp and HID, done
// here into plain pixel buffers and a ring of samples the app's Metal view and audio engine take.
#include "pd_ios.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <mgba-util/vfs.h>
#include <mgba/core/blip_buf.h>
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/internal/gba/audio.h>
#include <mgba/internal/gba/gba.h>

#include "pk_call.h"
#include "pk_gb_audio.h"
#include "pk_host.h"
#include "pd_game.h"
#include "pd_romart.h"
#include "pd_settings.h"
#include "pd_style.h"
#include "../../3ds/host/pd_session.h"

#define GAME_STRIDE PD_GAME_STRIDE
#define GAME_MAX_H 240
#define K 2 // the top picture is the 3DS's top screen at this scale
#define AUDIO_CHUNK 1024
#define RING_FRAMES 16384 // stereo frames, a power of two
#define RING_TARGET 2400  // what the rate control keeps queued: 50 ms
#define BACKUPS_KEPT 10

_Static_assert(PD_UI_WIDTH == PD_IOS_BOTTOM_W && PD_UI_HEIGHT == PD_IOS_BOTTOM_H, "the companion's canvas");
_Static_assert(PD_TOP_W * K == PD_IOS_TOP_W && PD_TOP_H * K == PD_IOS_TOP_H, "the top screen");

// ---- state ----

static char dataDir[512], cacheDir[512];
static char settingsPath[600];
static struct pd_settings settings;
static bool settingsReady;

static struct pd_session session;
static struct mCore* core;
static struct VFile* saveFile;
static void* romBytes;
static char romBase[256]; // the ROM's file name without its extension: names its states and backups
static char savePathNow[1024];
static bool running;

static uint32_t video[GAME_STRIDE * GAME_MAX_H];
static uint32_t topPx[PD_IOS_TOP_W * PD_IOS_TOP_H];
static uint32_t bottomPx[PD_IOS_BOTTOM_W * PD_IOS_BOTTOM_H];
static uint32_t wideFilled[400 * 240];

static uint32_t buttonsHeld, buttonsWas, withheld;
static int focusHeldFor[4];
static bool touching;
static int touchX, touchY;
static bool ffWas; // fast-forward on at the last tick: a notice when it changes
static bool touchDown, touchPress; // touchPress: a finger landed since the last tick (kept even if it already lifted)

static double refreshHz = 60.0;
static unsigned fpsFrames, fpsMs;

// ---- sound: a ring the audio thread reads ----

static int16_t ring[RING_FRAMES * 2];
static _Atomic unsigned ringWrite, ringRead;
static bool gbAudioOn;
static struct pk_gb_audio gbAudio;
static struct mAVStream stream;
static double rateAdjust = 1.0, baseRatio = 1.0;

static unsigned ring_count(void) {
    return atomic_load_explicit(&ringWrite, memory_order_acquire) - atomic_load_explicit(&ringRead, memory_order_acquire);
}

static void ring_push(const int16_t* stereo, int frames) {
    unsigned w = atomic_load_explicit(&ringWrite, memory_order_relaxed);
    unsigned free = RING_FRAMES - ring_count();
    if ((unsigned) frames > free) frames = (int) free; // full: the newest go (the reader has stalled)
    for (int i = 0; i < frames; i++) {
        unsigned at = (w + (unsigned) i) & (RING_FRAMES - 1);
        ring[at * 2] = stereo[i * 2];
        ring[at * 2 + 1] = stereo[i * 2 + 1];
    }
    atomic_store_explicit(&ringWrite, w + (unsigned) frames, memory_order_release);
}

int pd_ios_audio_read(int16_t* out, int frames) {
    unsigned r = atomic_load_explicit(&ringRead, memory_order_relaxed);
    unsigned have = atomic_load_explicit(&ringWrite, memory_order_acquire) - r;
    int n = (unsigned) frames < have ? frames : (int) have;
    for (int i = 0; i < n; i++) {
        unsigned at = (r + (unsigned) i) & (RING_FRAMES - 1);
        out[i * 2] = ring[at * 2];
        out[i * 2 + 1] = ring[at * 2 + 1];
    }
    memset(out + n * 2, 0, (size_t) (frames - n) * 2 * sizeof(int16_t));
    atomic_store_explicit(&ringRead, r + (unsigned) n, memory_order_release);
    return n;
}

// mGBA's GBA sound, a chunk at a time; muted in fast-forward (as the 3DS has it).
static void post_audio(struct mAVStream* s, blip_t* left, blip_t* right) {
    (void) s;
    static int16_t chunk[AUDIO_CHUNK * 2];
    int n = blip_samples_avail(left);
    if (n > AUDIO_CHUNK) n = AUDIO_CHUNK;
    blip_read_samples(left, chunk, n, true);
    blip_read_samples(right, chunk + 1, n, true);
    if (!session.ff) ring_push(chunk, n);
}

static void gb_audio_pump(void) {
    if (!gbAudioOn) return;
    static int16_t chunk[AUDIO_CHUNK * 2];
    int n;
    while ((n = pk_gb_audio_read(&gbAudio, chunk, AUDIO_CHUNK)) > 0)
        if (!session.ff) ring_push(chunk, n);
}

// The display ticks a little faster or slower than the game's 59.73 frames a second, and the audio device's clock drifts
// from both: the sound's rate is nudged (at most 0.5%) to keep about RING_TARGET frames queued.
static void audio_follow(void) {
    double fill = (double) ring_count();
    double want = 1.0 + 0.005 * (RING_TARGET - fill) / RING_TARGET;
    if (want < 0.995) want = 0.995;
    if (want > 1.005) want = 1.005;
    rateAdjust += (want - rateAdjust) * 0.05;
    double rate = PD_IOS_AUDIO_RATE * baseRatio * rateAdjust;
    if (gbAudioOn) {
        pk_gb_audio_set_rate(&gbAudio, rate);
    } else if (core) {
        blip_set_rates(core->getAudioChannel(core, 0), core->frequency(core), rate);
        blip_set_rates(core->getAudioChannel(core, 1), core->frequency(core), rate);
    }
}

// ---- files ----

static void make_dir(const char* path) {
    if (mkdir(path, 0755) && errno != EEXIST) return;
}

static void data_path(char* out, size_t len, const char* sub) {
    snprintf(out, len, "%s/%s", dataDir, sub);
}

static bool copy_file(const char* from, const char* to) {
    FILE* in = fopen(from, "rb");
    if (!in) return false;
    FILE* out = fopen(to, "wb");
    if (!out) {
        fclose(in);
        return false;
    }
    char buf[16384];
    size_t n;
    bool ok = true;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0)
        if (fwrite(buf, 1, n, out) != n) ok = false;
    fclose(in);
    if (fclose(out)) ok = false;
    return ok;
}

static int name_cmp(const void* a, const void* b) {
    return strcmp(*(char* const*) a, *(char* const*) b);
}

// The save copied aside before a start and before a state load: backups/<rom>/<time>.sav, the newest BACKUPS_KEPT kept
// (the repo's "save files are sacred" rule).
static void backup_save(void) {
    struct stat st;
    if (!savePathNow[0] || stat(savePathNow, &st) || st.st_size == 0) return;
    char dir[1024], path[1300];
    data_path(dir, sizeof(dir), "backups");
    make_dir(dir);
    snprintf(dir + strlen(dir), sizeof(dir) - strlen(dir), "/%s", romBase);
    make_dir(dir);
    time_t now = time(NULL);
    struct tm t;
    localtime_r(&now, &t);
    char stamp[32];
    strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &t);
    snprintf(path, sizeof(path), "%s/%s.sav", dir, stamp);
    if (!copy_file(savePathNow, path)) return;

    DIR* d = opendir(dir);
    if (!d) return;
    char* names[256];
    int count = 0;
    struct dirent* e;
    while ((e = readdir(d)) && count < 256)
        if (strstr(e->d_name, ".sav")) names[count++] = strdup(e->d_name);
    closedir(d);
    qsort(names, (size_t) count, sizeof(*names), name_cmp);
    for (int i = 0; i < count; i++) {
        if (i < count - BACKUPS_KEPT) {
            snprintf(path, sizeof(path), "%s/%s", dir, names[i]);
            unlink(path);
        }
        free(names[i]);
    }
}

static void state_path(void* ctx, int slot, char* vf, size_t vfLen, char* path, size_t pathLen) {
    (void) ctx;
    char dir[1024];
    data_path(dir, sizeof(dir), "states");
    make_dir(dir);
    snprintf(path, pathLen, "%s/%s.ss%d", dir, romBase, slot);
    snprintf(vf, vfLen, "%s", path);
}

static void backup_for_load(void* ctx) {
    (void) ctx;
    backup_save();
}

// One screen held sideways (pd_ios_set_landscape): the game alone, its own ASPECT (EXPAND unless the player picks another
// there), kept apart from the two-pane one in `landscape-aspect` so neither overwrites the other in settings.ini.
static bool landscape;
static int otherAspect = PD_ASPECT_EXPAND; // the aspect of the orientation not in use
static char landscapePath[600];

static void save_settings(void) {
    struct pd_settings out = settings;
    if (landscape) out.aspect = otherAspect;
    pd_settings_save(&out, settingsPath);
    FILE* f = fopen(landscapePath, "w");
    if (f) {
        fprintf(f, "%d\n", landscape ? settings.aspect : otherAspect);
        fclose(f);
    }
}

void pd_ios_set_landscape(bool on) {
    if (on == landscape || !settingsReady) return;
    int now = settings.aspect;
    settings.aspect = otherAspect;
    otherAspect = now;
    landscape = on;
    session.redraw = true;
}

bool pd_ios_ff_on(void) {
    return running && session.ff;
}

bool pd_ios_companion_focused(void) {
    return running && session.ui.keyFocus;
}

void pd_ios_set_companion_focus(bool on) {
    if (!running || on == session.ui.keyFocus || (on && !pd_session_can_focus(&session))) return;
    pd_session_set_focus(&session, on);
    withheld |= buttonsHeld; // what's held now stays away from the side it left
    session.redraw = true;
}

static void settings_changed(void* ctx) {
    (void) ctx;
    save_settings();
}

static void cheat_path(void* ctx, uint32_t crc, char* path, size_t len) {
    (void) ctx;
    char dir[1024];
    data_path(dir, sizeof(dir), "cheats");
    make_dir(dir);
    snprintf(path, len, "%s/%08X.cheats", dir, (unsigned) crc);
}

static void flight_area_path(void* ctx, uint32_t crc, uint32_t key, char* path, size_t len) {
    (void) ctx;
    char dir[1024];
    data_path(dir, sizeof(dir), "flight");
    make_dir(dir);
    snprintf(path, len, "%s/%08X-%08X.txt", dir, (unsigned) crc, (unsigned) key);
}

static void nuzlocke_path(void* ctx, uint32_t crc, char* path, size_t len) {
    (void) ctx;
    char dir[1024];
    data_path(dir, sizeof(dir), "nuzlocke");
    make_dir(dir);
    snprintf(path, len, "%s/%08X.txt", dir, (unsigned) crc);
}

// ---- lifetime ----

static void noop_log(struct mLogger* log, int category, enum mLogLevel level, const char* format, va_list args) {
    (void) log; (void) category; (void) level; (void) format; (void) args;
}
static struct mLogger silentLogger = { .log = noop_log, .filter = NULL };

void pd_ios_init(const char* data, const char* cache) {
    snprintf(dataDir, sizeof(dataDir), "%s", data);
    snprintf(cacheDir, sizeof(cacheDir), "%s", cache);
    make_dir(dataDir);
    make_dir(cacheDir);
    char romArt[600];
    snprintf(romArt, sizeof(romArt), "%s/rom-art", cacheDir);
    make_dir(romArt);
    pd_romart_cache_dir(romArt);
    snprintf(settingsPath, sizeof(settingsPath), "%s/settings.ini", dataDir);
    pd_settings_defaults(&settings);
    pd_settings_load(&settings, settingsPath);
    snprintf(landscapePath, sizeof(landscapePath), "%s/landscape-aspect", dataDir);
    FILE* f = fopen(landscapePath, "r");
    int a;
    if (f) {
        if (fscanf(f, "%d", &a) == 1 && a >= 0 && a < PD_ASPECTS) otherAspect = a;
        fclose(f);
    }
    settingsReady = true;
    mLogSetDefaultLogger(&silentLogger);
}

// A Game Boy cart's own screen, not a Super Game Boy border; its volume where the GB mixer can't clip (3ds/ctr/main.c).
static void gb_settings(struct mCore* c) {
    if (c->platform(c) != mPLATFORM_GB) return;
    mCoreConfigSetIntValue(&c->config, "sgb.borders", 0);
    c->reloadConfigOption(c, "sgb.borders", &c->config);
    mCoreConfigSetIntValue(&c->config, "volume", 0x80);
    c->reloadConfigOption(c, "volume", &c->config);
}

static void fail(char* error, size_t len, const char* why) {
    if (error && len) snprintf(error, len, "%s", why);
}

bool pd_ios_start(const char* romPath, const char* savePath, char* error, size_t errorLen) {
    if (!settingsReady) {
        fail(error, errorLen, "pd_ios_init wasn't called");
        return false;
    }
    pd_ios_stop();

    const char* slash = strrchr(romPath, '/');
    snprintf(romBase, sizeof(romBase), "%s", slash ? slash + 1 : romPath);
    char* dot = strrchr(romBase, '.');
    if (dot) *dot = 0;
    snprintf(savePathNow, sizeof(savePathNow), "%s", savePath);

    // The ROM from a copy in memory: a GPIO write swaps mGBA's own mapping of a mapped file (pd_sim.c).
    FILE* f = fopen(romPath, "rb");
    if (!f) {
        fail(error, errorLen, "The game file couldn't be opened.");
        return false;
    }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0 || len > 64 * 1024 * 1024) {
        fclose(f);
        fail(error, errorLen, "That file is empty or too big to be a game.");
        return false;
    }
    romBytes = malloc((size_t) len);
    if (!romBytes || fread(romBytes, 1, (size_t) len, f) != (size_t) len) {
        fclose(f);
        free(romBytes);
        romBytes = NULL;
        fail(error, errorLen, "The game file couldn't be read.");
        return false;
    }
    fclose(f);

    memset(&session, 0, sizeof(session));
    pd_game_detect(&session.game, romBytes, (size_t) len);
    backup_save();

    struct VFile* rom = VFileFromMemory(romBytes, (size_t) len);
    core = rom ? mCoreFindVF(rom) : NULL;
    if (!core || !core->init(core)) {
        if (rom) rom->close(rom);
        core = NULL;
        free(romBytes);
        romBytes = NULL;
        fail(error, errorLen, "Not a game PokeDaisy plays (GBA, Game Boy or Game Boy Color).");
        return false;
    }
    mCoreInitConfig(core, NULL);
    memset(video, 0, sizeof(video));
    core->setVideoBuffer(core, (color_t*) video, GAME_STRIDE);
    gb_settings(core);
    core->setAudioBufferSize(core, AUDIO_CHUNK);
    if (!core->loadROM(core, rom)) {
        core->deinit(core);
        core = NULL;
        free(romBytes);
        romBytes = NULL;
        fail(error, errorLen, "mGBA couldn't load the game.");
        return false;
    }
    saveFile = VFileOpen(savePath, O_CREAT | O_RDWR);
    if (saveFile) core->loadSave(core, saveFile);
    if (core->platform(core) == mPLATFORM_GBA) ((struct GBA*) core->board)->idleOptimization = IDLE_LOOP_DETECT;

    atomic_store(&ringWrite, 0);
    atomic_store(&ringRead, 0);
    rateAdjust = 1.0;
    // A game frame a refresh: its 59.73 frames' sound in the display's [refreshHz].
    baseRatio = GBAAudioCalculateRatio(1, (float) refreshHz, 1);
    if (core->platform(core) == mPLATFORM_GB) {
        gbAudioOn = pk_gb_audio_attach(&gbAudio, core, PD_IOS_AUDIO_RATE * baseRatio);
    } else {
        memset(&stream, 0, sizeof(stream));
        stream.postAudioBuffer = post_audio;
        core->setAVStream(core, &stream);
    }
    audio_follow();
    core->reset(core);
    pk_heal_rtc(core);

    static struct pd_session_host files;
    files = (struct pd_session_host) { .statePath = state_path, .backupSave = backup_for_load, .settingsChanged = settings_changed,
                                       .cheatPath = cheat_path, .flightAreaPath = flight_area_path, .nuzlockePath = nuzlocke_path };
    session.host = (struct pd_host_info) { .count = 2, .batteryPct = -1 };
    session.host.labels[0] = "FILE";
    snprintf(session.host.values[0], sizeof(session.host.values[0]), "%.39s", romBase);
    session.host.labels[1] = "SPEED";
    snprintf(session.host.values[1], sizeof(session.host.values[1]), "-");
    pd_session_start(&session, core, video, &settings, &files);

    buttonsHeld = buttonsWas = withheld = 0;
    ffWas = false;
    memset(focusHeldFor, 0, sizeof(focusHeldFor));
    touching = touchDown = touchPress = false;
    fpsFrames = fpsMs = 0;
    session.redraw = true;
    running = true;
    return true;
}

void pd_ios_stop(void) {
    if (!running) return;
    running = false;
    // A save the game is writing finishes before the core stops; deinit then writes it back.
    bool ff = session.ff;
    session.ff = true; // muted meanwhile
    pk_finish_save(core, PK_FINISH_SAVE_FRAMES, NULL);
    session.ff = ff;
    if (gbAudioOn) pk_gb_audio_detach(&gbAudio, core);
    gbAudioOn = false;
    core->deinit(core);
    core = NULL;
    saveFile = NULL; // closed by deinit
    free(romBytes);
    romBytes = NULL;
    atomic_store(&ringRead, atomic_load(&ringWrite));
}

bool pd_ios_running(void) {
    return running;
}

const char* pd_ios_title(void) {
    return running && session.game.title[0] ? session.game.title : "";
}

bool pd_ios_supported(void) {
    return running && session.game.cfg != NULL;
}

bool pd_ios_game_boy(void) {
    return running && pd_session_game_boy(&session);
}

void pd_ios_flush_save(void) {
    if (!running) return;
    if (saveFile) saveFile->sync(saveFile, NULL, 0);
    save_settings();
}

// ---- input ----

void pd_ios_set_buttons(uint32_t held) {
    buttonsHeld = held;
}

void pd_ios_touch(int x, int y, bool down) {
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= PD_IOS_BOTTOM_W) x = PD_IOS_BOTTOM_W - 1;
    if (y >= PD_IOS_BOTTOM_H) y = PD_IOS_BOTTOM_H - 1;
    if (down) {
        touchX = x;
        touchY = y;
        if (!touchDown) touchPress = true;
    }
    touchDown = down;
}

void pd_ios_set_battery(int percent, bool charging) {
    if (!running) return;
    if (session.host.batteryPct != percent || session.host.charging != charging) {
        session.host.batteryPct = percent;
        session.host.charging = charging;
        if (session.ui.tab == PD_TAB_SETTINGS) session.redraw = true;
    }
}

void pd_ios_set_refresh(double hz) {
    if (hz > 20 && hz < 500) refreshHz = hz;
}

// The buttons the 3DS host maps to the companion (ctr/main.c): X sends the buttons to the companion on the field (BACK
// elsewhere), with them there the D-pad / A / B / L / R drive it; ZL steps the tabs back.
static void companion_keys(uint32_t held, uint32_t down) {
    struct pd_ui* ui = &session.ui;
    if (ui->keyFocus) {
        static const uint32_t DIRS[4] = { PD_IOS_UP, PD_IOS_DOWN, PD_IOS_LEFT, PD_IOS_RIGHT };
        if (down & (PD_IOS_X | PD_IOS_START)) pd_session_set_focus(&session, false);
        else if ((down & PD_IOS_B) && !pd_ui_back(ui)) pd_session_set_focus(&session, false);
        else if (down & PD_IOS_A) pd_ui_focus_press(ui);
        else if (down & (PD_IOS_L | PD_IOS_R)) pd_ui_next_tab(ui, (down & PD_IOS_L) ? -1 : 1);
        for (int i = 0; i < 4; i++) {
            focusHeldFor[i] = (held & DIRS[i]) ? focusHeldFor[i] + 1 : 0;
            if ((down & DIRS[i]) || (focusHeldFor[i] >= 24 && focusHeldFor[i] % 6 == 0)) {
                pd_ui_focus_move(ui, i);
                session.redraw = true;
            }
        }
        if (down) session.redraw = true;
        withheld |= held;
    } else {
        if (down & PD_IOS_X) {
            if (pd_session_can_focus(&session)) {
                pd_session_set_focus(&session, true);
                withheld |= held;
            } else {
                pd_ui_back(ui);
            }
            session.redraw = true;
        }
        if (down & PD_IOS_ZL) {
            pd_ui_next_tab(ui, -1);
            session.redraw = true;
        }
    }
    // Keys pressed on the companion stay away from the game until they're let go.
    withheld &= held;
}

// ---- pictures ----

static inline uint32_t rgba_of_argb(uint32_t o) {
    return (o >> 16 & 0xFF) | (o & 0xFF00) | (o & 0xFF) << 16;
}

// The 3DS's top screen (gpu.c's run_job) at K times its size: the game where SCREEN puts it, the dim, the overlay.
static void compose_top(void) {
    const int TW = PD_IOS_TOP_W, TH = PD_IOS_TOP_H;
    uint32_t bar = pd_session_game_boy(&session) ? 0xFFFFFFFFu : 0xFF000000u;
    unsigned gameW = 240, gameH = 160;
    core->desiredVideoDimensions(core, &gameW, &gameH);

    const uint32_t* src = video;
    int srcW = (int) gameW, srcH = (int) gameH, stride = GAME_STRIDE;
    float dx, dy, dw, dh; // where the picture goes, in the 400x240 screen's pixels
    int mode = pd_session_screen(&session);
    if (session.wideReady && session.wideW > 0 && session.wideH > 0 && session.wideW <= 400 && session.wideH <= 240) {
        // EXPAND's window, the game's own frame in its hole (what the console's draw thread does).
        const struct pd_wide_hole* hole = &session.wideHole;
        memcpy(wideFilled, pd_session_wide(&session), (size_t) session.wideW * session.wideH * sizeof(uint32_t));
        for (int y = 0; hole->w && y < hole->h; y++)
            memcpy(wideFilled + (hole->y + y) * session.wideW + hole->x, video + (hole->gameY + y) * GAME_STRIDE + hole->gameX,
                   (size_t) hole->w * sizeof(uint32_t));
        src = wideFilled;
        srcW = session.wideW;
        srcH = session.wideH;
        stride = session.wideW;
        float k = 240.0f / srcH;
        dw = srcW * k;
        dh = 240;
        dx = (400 - dw) / 2;
        dy = 0;
    } else if (mode == PD_SCREEN_STRETCH) {
        dx = dy = 0;
        dw = 400;
        dh = 240;
    } else if (mode == PD_SCREEN_PIXEL) {
        dw = (float) srcW;
        dh = (float) srcH;
        dx = (400 - dw) / 2;
        dy = (240 - dh) / 2;
    } else {
        float s = mode == PD_SCREEN_SHARP_125 ? 1.25f : 240.0f / srcH;
        dw = srcW * s;
        dh = srcH * s;
        dx = (400 - dw) / 2;
        dy = (240 - dh) / 2;
    }
    int x0 = (int) (dx * K + 0.5f), y0 = (int) (dy * K + 0.5f), w = (int) (dw * K + 0.5f), h = (int) (dh * K + 0.5f);
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x0 + w > TW) w = TW - x0;
    if (y0 + h > TH) h = TH - y0;

    for (int y = 0; y < TH; y++) {
        uint32_t* row = topPx + y * TW;
        if (y < y0 || y >= y0 + h) {
            for (int x = 0; x < TW; x++) row[x] = bar;
            continue;
        }
        const uint32_t* s = src + ((y - y0) * srcH / h) * stride;
        for (int x = 0; x < x0; x++) row[x] = bar;
        for (int x = 0; x < w; x++) row[x0 + x] = s[x * srcW / w] | 0xFF000000u; // the top byte is mGBA's layer: opaque here
        for (int x = x0 + w; x < TW; x++) row[x] = bar;
    }

    if (session.overlayDim)
        for (int i = 0; i < TW * TH; i++) {
            uint32_t d = topPx[i];
            topPx[i] = 0xFF000000u | (((d >> 1) & 0x7F7F7F) + ((d >> 3) & 0x1F1F1F) + ((d >> 5) & 0x070707)); // ~2/3, gpu.c's 0x55 black
        }
    if (session.overlayShown) {
        const uint32_t* overlay = pd_session_overlay(&session);
        for (int y = 0; y < TH; y++) {
            const uint32_t* o = overlay + (y / K) * PD_TOP_W;
            uint32_t* row = topPx + y * TW;
            for (int x = 0; x < TW; x++) {
                uint32_t p = o[x / K], a = p >> 24;
                if (!a) continue;
                uint32_t c = rgba_of_argb(p);
                if (a == 0xFF) {
                    row[x] = 0xFF000000u | c;
                    continue;
                }
                uint32_t d = row[x], r = 0;
                for (int sft = 0; sft <= 16; sft += 8)
                    r |= ((((c >> sft) & 0xFF) * a + ((d >> sft) & 0xFF) * (255 - a)) / 255) << sft;
                row[x] = 0xFF000000u | r;
            }
        }
    }
}

const uint8_t* pd_ios_top(void) {
    return (const uint8_t*) topPx;
}

const uint8_t* pd_ios_bottom(void) {
    return (const uint8_t*) bottomPx;
}

// ---- the loop ----

int pd_ios_tick(unsigned ms) {
    if (!running) return 0;
    int result = 0;
    uint32_t held = buttonsHeld, down = held & ~buttonsWas;
    buttonsWas = held;
    companion_keys(held, down);

    // A tap can land and lift between two ticks: the press is kept until a tick sees it, then the lift.
    if (touchPress) {
        touchPress = false;
        session.redraw |= pd_ui_touch(&session.ui, touchX, touchY, true);
        touching = true;
    } else if (touching && touchDown) {
        session.redraw |= pd_ui_touch(&session.ui, touchX, touchY, true); // held: the companion's drags and long presses
    }
    if (touching && !touchDown) {
        session.redraw |= pd_ui_touch(&session.ui, 0, 0, false);
        touching = false;
    }

    enum pd_action action = pd_ui_take_action(&session.ui);
    if (!pd_session_action(&session, action)) {
        switch (action) {
        case PD_ACTION_LEAVE_GAME:
            result |= PD_IOS_LEAVE;
            break;
        case PD_ACTION_RESTART_GAME:
            pk_finish_save(core, PK_FINISH_SAVE_FRAMES, NULL);
            core->reset(core);
            pk_heal_rtc(core);
            break;
        case PD_ACTION_SETTINGS_CHANGED:
            save_settings();
            break;
        default:
            break;
        }
    }

    uint32_t gameHeld = held & ~withheld & 0x3FF, gameDown = down & ~withheld & 0x3FF;
    struct pd_input in = { .held = gameHeld, .down = gameDown, .quickMenu = (down & PD_IOS_Y) && !session.ui.keyFocus,
                           .stickAngle = -1 };
    // FF is a toggle: a press of FF (R2, Tab) turns it on, the next turns it off.
    if (down & PD_IOS_ZR) session.ffToggled = !session.ffToggled;
    unsigned before = session.frame;
    pd_session_tick(&session, &in, ms);
    if (session.ff != ffWas) {
        // However it went on or off (FF held, the QUICK MENU's FF, the companion), a notice on the game says so.
        ffWas = session.ff;
        char text[40];
        if (ffWas) snprintf(text, sizeof(text), "Fast forward on (%dx)", settings.ffSpeed);
        else snprintf(text, sizeof(text), "Fast forward off");
        pd_session_show(&session, text);
    }
    gb_audio_pump();
    audio_follow();
    unsigned frames = session.frame - before;
    if ((frames || session.overlayShown || session.overlayDirty) && !pd_session_holds_frame(&session)) {
        compose_top();
        result |= PD_IOS_TOP_CHANGED;
    }

    fpsFrames += frames;
    fpsMs += ms;
    if (fpsMs >= 1000) {
        // Against the GBA's own 268111856 / 4481136 = 59.73 frames a second.
        unsigned pct = (unsigned) ((uint64_t) fpsFrames * 1000 * 100 * 4481136 / ((uint64_t) fpsMs * 268111856ULL));
        snprintf(session.host.values[1], sizeof(session.host.values[1]), "%u%% (%u FPS)", pct, fpsFrames);
        fpsFrames = fpsMs = 0;
        if (session.ui.tab == PD_TAB_SETTINGS) session.redraw = true;
    }

    if (session.redraw) {
        struct pd_canvas bottom;
        pd_canvas_init(&bottom, PD_UI_WIDTH, PD_UI_HEIGHT, bottomPx);
        pd_session_draw(&session, &bottom);
        for (int i = 0; i < PD_IOS_BOTTOM_W * PD_IOS_BOTTOM_H; i++) bottomPx[i] |= 0xFF000000u;
        result |= PD_IOS_BOTTOM_CHANGED;
    }
    return result;
}
