/* Private libretro environment commands shared by PokeDaisy's cores and host. */
#ifndef PD_ENV_H
#define PD_ENV_H

#include <stdint.h>

/* The core's quick menu asks the frontend to turn fast-forward on or off. [data] is a bool. */
#define PD_ENV_SET_FAST_FORWARD 0x20001

/* The core's floating touch screen. The core keeps the game's bottom screen at its full 256 x 192 and asks a host that
 * can draw it to do the output scaling itself, instead of scaling the pixels down into the panel first. [data] is a
 * pd_touch_panel; the pointer stays valid until the core's next frame. active = 0 withdraws the panel. */
#define PD_ENV_SET_TOUCH_PANEL 0x20002
struct pd_touch_panel {
  const uint32_t *pixels; /* src_w x src_h, XRGB8888 (0xFFRRGGBB), as the frame's pixels are */
  int src_w, src_h;
  int x, y, w, h;         /* the screen's place in the core's canvas */
  int active;
};

/* The core's field HUD at its own resolution. A ZOOM step grows the core's canvas and the frontend scales it down to
 * the window, so a HUD blended into the picture is resampled with it: sharp at whole steps, soft at 1.25x and 1.5x. A
 * host that can draw it takes the HUD's own picture instead, drawn over its box in the window's pixels, so each HUD
 * pixel reaches the window from the picture once. [data] is a pd_hud; the pixels stay valid until the core's next
 * frame. active = 0 withdraws it. */
#define PD_ENV_SET_HUD 0x20003
struct pd_hud {
  const uint32_t *pixels; /* src_w x src_h, the HUD's own 256x192, ARGB8888, alpha 0 = clear */
  int src_w, src_h;
  int x, y, w, h;         /* the HUD's box in the core's canvas (the 1x top screen's place at every ZOOM step) */
  int pct;                /* 100: the picture over the whole box. 50: each quarter at its own corner, a quarter of the box */
  int active;
};

/* Optional desktop dual-window companion frame. A frontend that supports a separate
 * companion window returns true, even for an inactive probe (active=0).
 * Pixels are XRGB8888 and valid only for the duration of the environment call;
 * the frontend must copy them before returning. */
#define PD_ENV_SET_COMPANION_FRAME 0x20004
struct pd_companion_frame {
  const uint32_t *pixels;
  int width, height;
  int active;
};

/* Companion mouse state in native 320x240 companion pixels. The host returns
 * false if independent companion input is unavailable. A short click must be
 * held across at least one core tick so release-driven UI actions are not lost. */
#define PD_ENV_GET_COMPANION_POINTER 0x20005
struct pd_companion_pointer {
  int x, y;
  int pressed;
};

#endif
