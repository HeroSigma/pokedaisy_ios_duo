// PokeDaisy for iPhone: the C side of the app. One game at a time, driven from the main thread (CADisplayLink), its
// sound read from the audio thread. It is a host for 3ds/host/pd_session.c, like the 3DS build (3ds/ctr/main.c) and the
// headless simulator (3ds/desktop/sim/pd_sim.c): the session owns the game, the companion, the HUD, the QUICK MENU and
// EXPAND; this owns the files, the screens' pixels, the sound and the buttons.
//
// Every game runs on mGBA's interpreter (third_party/mgba): iOS gives an app no executable memory without JIT, and mGBA
// needs none. Swift sees this header through the app's bridging header.
#ifndef PD_IOS_H
#define PD_IOS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The buttons: the GBA's ten (the same bits as pd_binput.h's PD_KEY_*), then the four the app adds, as the 3DS has them:
// X sends the buttons to the companion on the field (BACK elsewhere), Y opens the QUICK MENU, ZL steps the companion's
// tabs back, ZR holds fast-forward.
enum {
    PD_IOS_A = 1 << 0, PD_IOS_B = 1 << 1, PD_IOS_SELECT = 1 << 2, PD_IOS_START = 1 << 3,
    PD_IOS_RIGHT = 1 << 4, PD_IOS_LEFT = 1 << 5, PD_IOS_UP = 1 << 6, PD_IOS_DOWN = 1 << 7,
    PD_IOS_R = 1 << 8, PD_IOS_L = 1 << 9,
    PD_IOS_X = 1 << 10, PD_IOS_Y = 1 << 11, PD_IOS_ZL = 1 << 12, PD_IOS_ZR = 1 << 13,
};

// The top screen's picture: the 3DS's 400x240 screen at twice its size, so the game sits in it the way the console
// shows it (SHARP 1.5x = 3x here, whole pixels) with the HUD / QUICK MENU drawn over it. RGBA bytes.
#define PD_IOS_TOP_W 800
#define PD_IOS_TOP_H 480
// The companion: 320x240, BGRA bytes (0xAARRGGBB words, alpha always 0xFF).
#define PD_IOS_BOTTOM_W 320
#define PD_IOS_BOTTOM_H 240

// The sound's rate, stereo int16.
#define PD_IOS_AUDIO_RATE 48000

// pd_ios_tick's result bits.
enum {
    PD_IOS_TOP_CHANGED = 1 << 0,    // pd_ios_top has a new picture
    PD_IOS_BOTTOM_CHANGED = 1 << 1, // pd_ios_bottom has a new picture
    PD_IOS_LEAVE = 1 << 2,          // the companion's CLOSE GAME: the app should go back to its library
};

// Once, at launch: [dataDir] holds settings, states, cheats, backups (made as needed); [cacheDir] the ROM art's offsets.
void pd_ios_init(const char* dataDir, const char* cacheDir);

// Starts [romPath] with its battery save at [savePath] (made if missing; backed up first). False + a reason in [error].
bool pd_ios_start(const char* romPath, const char* savePath, char* error, size_t errorLen);
// Writes the save out and closes the game. Safe to call with none running.
void pd_ios_stop(void);
bool pd_ios_running(void);
// The game's own name and whether the companion knows it ("" / false with none running).
const char* pd_ios_title(void);
bool pd_ios_supported(void);
bool pd_ios_game_boy(void);

// The app is going to the background: the save is written out now (iOS may end the app without asking).
void pd_ios_flush_save(void);

// The buttons held now (PD_IOS_* bits). Presses are worked out from the last call.
void pd_ios_set_buttons(uint32_t held);
// A finger on the companion, in its 320x240 pixels; down = false when it lifts (x / y ignored).
void pd_ios_touch(int x, int y, bool down);
// The device's battery for the companion's SETTINGS title (-1 = unknown).
void pd_ios_set_battery(int percent, bool charging);
// The display's refresh this is ticked at, for the sound's rate (60 by default).
void pd_ios_set_refresh(double hz);

// One screen held sideways: the app shows the game alone (the companion over it on demand), so it takes its own ASPECT,
// EXPAND by default: the overworld past the GBA's edges, as PokeDaisy on a one-screen device. Its own pick is kept.
void pd_ios_set_landscape(bool on);
// Fast forward is on (PD_IOS_ZR toggles it, as the QUICK MENU's FF does).
bool pd_ios_ff_on(void);
// The companion has the controller's buttons (X gave them to it; X / START / B at its top give them back).
bool pd_ios_companion_focused(void);
// Gives the controller's buttons to the companion (when it can take them) or back to the game.
void pd_ios_set_companion_focus(bool on);

// One loop: a game frame (more in fast-forward), the companion's taps, its redraw. [ms] since the last tick.
int pd_ios_tick(unsigned ms);

const uint8_t* pd_ios_top(void);    // PD_IOS_TOP_W x PD_IOS_TOP_H RGBA
const uint8_t* pd_ios_bottom(void); // PD_IOS_BOTTOM_W x PD_IOS_BOTTOM_H BGRA

// The audio thread: up to [frames] stereo frames into [out]; the rest is silence. Returns how many were real.
int pd_ios_audio_read(int16_t* out, int frames);

#ifdef __cplusplus
}
#endif

#endif
