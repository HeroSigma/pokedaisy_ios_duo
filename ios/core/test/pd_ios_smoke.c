// pd_ios_smoke ROM OUTDIR: the iPhone app's C side run headless, the way the app drives it (a tick a refresh, buttons,
// a finger on the companion, the audio thread's reads). Writes top.png / bottom.png and prints what it saw; fails if a
// pane stayed empty, no sound came, or the save wasn't written. For the diagnostic ROMs (linux/make_diagnostic.py) or
// any game of your own: nothing commercial is in the repo.
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "pd_ios.h"
#include "pd_png.h"

static uint32_t px[PD_IOS_TOP_W * PD_IOS_TOP_H];

static int distinct(const uint32_t* p, int n) {
    uint32_t seen[8];
    int count = 0;
    for (int i = 0; i < n && count < 8; i++) {
        int j = 0;
        while (j < count && seen[j] != p[i]) j++;
        if (j == count) seen[count++] = p[i];
    }
    return count;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: pd_ios_smoke ROM OUTDIR\n");
        return 2;
    }
    const char* out = argv[2];
    mkdir(out, 0755);
    char data[1024], cache[1024], save[1024], path[1200];
    snprintf(data, sizeof(data), "%s/data", out);
    snprintf(cache, sizeof(cache), "%s/cache", out);
    snprintf(save, sizeof(save), "%s/game.sav", out);
    pd_ios_init(data, cache);
    char error[256] = "";
    if (!pd_ios_start(argv[1], save, error, sizeof(error))) {
        printf("FAIL: start: %s\n", error);
        return 1;
    }
    printf("title '%s' supported %d gameboy %d\n", pd_ios_title(), pd_ios_supported(), pd_ios_game_boy());
    pd_ios_set_battery(80, false);

    int failures = 0, tops = 0, bottoms = 0, sound = 0;
    bool tapped = false;
    static int16_t audio[800 * 2];
    for (int i = 0; i < 600; i++) {
        uint32_t keys = (i / 30) % 2 ? PD_IOS_A : 0;
        if (i == 300) keys |= PD_IOS_Y; // the QUICK MENU, then closed again
        if (i == 330) keys |= PD_IOS_B;
        pd_ios_set_buttons(keys);
        if (i == 200) pd_ios_touch(260, 226, true); // STATES on the tab bar
        if (i == 203) pd_ios_touch(0, 0, false);
        int r = pd_ios_tick(16);
        if (r & PD_IOS_TOP_CHANGED) tops++;
        if (r & PD_IOS_BOTTOM_CHANGED) bottoms++;
        if (r & PD_IOS_LEAVE) printf("leave asked at %d\n", i);
        sound += pd_ios_audio_read(audio, 800); // the audio thread, about a refresh's worth
        if (i >= 203 && i <= 205 && (r & PD_IOS_BOTTOM_CHANGED)) tapped = true; // the lift is the tap
        if (i == 205 || i == 320) {
            const uint32_t* t = (const uint32_t*) (i == 205 ? pd_ios_bottom() : pd_ios_top());
            int w = i == 205 ? PD_IOS_BOTTOM_W : PD_IOS_TOP_W, h = i == 205 ? PD_IOS_BOTTOM_H : PD_IOS_TOP_H;
            for (int k = 0; k < w * h; k++)
                px[k] = i == 205 ? (t[k] & 0xFFFFFF) : ((t[k] & 0xFF) << 16 | (t[k] & 0xFF00) | (t[k] >> 16 & 0xFF));
            snprintf(path, sizeof(path), "%s/%s.png", out, i == 205 ? "bottom-tapped" : "top-quick");
            pd_png_write(path, w, h, px);
        }
    }
    if (!tapped) printf("FAIL: the tap on STATES didn't redraw the companion\n"), failures++;
    printf("ticks with a new top %d, new companion %d, sound frames %d\n", tops, bottoms, sound);

    const uint32_t* top = (const uint32_t*) pd_ios_top();
    for (int i = 0; i < PD_IOS_TOP_W * PD_IOS_TOP_H; i++) {
        uint32_t p = top[i];
        px[i] = (p & 0xFF) << 16 | (p & 0xFF00) | (p >> 16 & 0xFF);
    }
    snprintf(path, sizeof(path), "%s/top.png", out);
    pd_png_write(path, PD_IOS_TOP_W, PD_IOS_TOP_H, px);
    int topColours = distinct(px, PD_IOS_TOP_W * PD_IOS_TOP_H);
    const uint32_t* bottom = (const uint32_t*) pd_ios_bottom();
    for (int i = 0; i < PD_IOS_BOTTOM_W * PD_IOS_BOTTOM_H; i++) px[i] = bottom[i] & 0xFFFFFF;
    snprintf(path, sizeof(path), "%s/bottom.png", out);
    pd_png_write(path, PD_IOS_BOTTOM_W, PD_IOS_BOTTOM_H, px);
    int bottomColours = distinct(px, PD_IOS_BOTTOM_W * PD_IOS_BOTTOM_H);
    printf("colours: top %d, companion %d\n", topColours, bottomColours);

    if (!tops || topColours < 2) printf("FAIL: the game's pane stayed blank\n"), failures++;
    if (!bottoms || bottomColours < 2) printf("FAIL: the companion's pane stayed blank\n"), failures++;
    if (sound < 600 * 600) printf("FAIL: too little sound (%d frames)\n", sound), failures++;

    pd_ios_flush_save();
    pd_ios_stop();
    struct stat st;
    if (stat(save, &st)) printf("FAIL: no save file\n"), failures++;
    else printf("save: %lld bytes\n", (long long) st.st_size);
    if (pd_ios_running()) printf("FAIL: still running after stop\n"), failures++;
    // A second start of the same game: its save is backed up first.
    if (!pd_ios_start(argv[1], save, error, sizeof(error))) printf("FAIL: restart: %s\n", error), failures++;
    for (int i = 0; i < 60; i++) pd_ios_tick(16);
    pd_ios_stop();
    printf(failures ? "%d FAILED\n" : "ok\n", failures);
    return failures ? 1 : 0;
}
