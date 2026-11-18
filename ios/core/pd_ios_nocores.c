// iOS: every game runs on mGBA, so armGBA and gpSP aren't built (the session's dispatch, 3ds/emu/pd_dispatch.c, still
// names them). Each answers "not this core" / nothing: pd_armgba_is and pd_gpsp_is are false for every core, so none of the
// rest is reached. Written from pd_armgba.h / pd_gpsp.h; a new function there needs its line here.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../../3ds/emu/pd_armgba.h"
#include "../../3ds/emu/pd_gpsp.h"


bool pd_armgba_wants(const uint8_t* header, size_t headerLen) { return false; }
struct mCore* pd_armgba_load(const char* romPath, const char* savePath, const struct pd_armgba_host* host, char* error, size_t errorLen) { if (error && errorLen) error[0] = 0; return NULL; }
bool pd_armgba_is(const struct mCore* core) { return false; }
bool pd_armgba_recompiling(void) { return false; }
bool pd_armgba_threaded(void) { return false; }
bool pd_armgba_fast_flash_saves(long* start, long* stop) { return false; }
void pd_armgba_skip_video(bool skip) {}
void pd_armgba_hblank_skips(bool on) {}
void pd_armgba_hblank_cost(int cycles) {}
bool pd_armgba_write(uint32_t addr, const void* data, size_t len) { return false; }
bool pd_armgba_rom_write(uint32_t addr, const void* data, size_t len) { return false; }
bool pd_armgba_save_state(const char* path) { return false; }
enum pd_armgba_state pd_armgba_load_state(const char* path) { return PD_ARMGBA_STATE_NO_FILE; }
void pd_armgba_flush_save(void) {}
int pd_armgba_save_dirty(void) { return 0; }
int pd_armgba_finish_save(struct mCore* core, int maxFrames, void (*afterFrame)(void)) { return 0; }
void pd_armgba_heal_rtc(void) {}
int pd_armgba_call(uint32_t fn, const uint32_t args[4], uint32_t* r0) { return 0; }
int pd_armgba_call_safe(void) { return 0; }
void pd_armgba_call_set_cap(long steps) {}
void pd_armgba_rest_note(void) {}
void pd_armgba_rest_reset(void) {}
void pd_armgba_cheats_clear(void) {}
void pd_armgba_set_bkpt(bool (*handler)(uint32_t address, unsigned immediate)) {}
uint32_t pd_armgba_reg(int n) { return 0; }
void pd_armgba_set_reg(int n, uint32_t value) {}
void pd_armgba_jump(uint32_t to) {}
int pd_armgba_vcount(void) { return 0; }
int pd_armgba_cheats_apply(const char* text, size_t len) { return 0; }
struct mCore* pd_gpsp_load(const char* romPath, const char* savePath, const struct pd_gpsp_host* host, char* error, size_t errorLen) { if (error && errorLen) error[0] = 0; return NULL; }
bool pd_gpsp_is(const struct mCore* core) { return false; }
void pd_gpsp_cheats_clear(void) {}
int pd_gpsp_cheats_apply(const char* text, size_t len) { return 0; }
bool pd_gpsp_open(const char* romPath, const char* savePath, const struct pd_gpsp_host* host, char* error, size_t errorLen) { return false; }
void pd_gpsp_close(void) {}
bool pd_gpsp_loaded(void) { return false; }
void pd_gpsp_memory(struct pd_gpsp_memory* m) {}
void pd_gpsp_set_keys(uint32_t keys) {}
uint32_t pd_gpsp_keys(void) { return 0; }
void pd_gpsp_run_frame(void) {}
void pd_gpsp_reset(void) {}
void pd_gpsp_set_video(uint32_t* buffer, size_t stride) {}
void pd_gpsp_skip_video(bool skip) {}
uint32_t pd_gpsp_crc(void) { return 0; }
bool pd_gpsp_recompiling(void) { return false; }
bool pd_gpsp_threaded(void) { return false; }
void pd_gpsp_render_us(unsigned* render, unsigned* wait) {}
uint32_t pd_gpsp_read8(uint32_t address) { return 0; }
bool pd_gpsp_write(uint32_t addr, const void* data, size_t len) { return false; }
bool pd_gpsp_rom_write(uint32_t addr, const void* data, size_t len) { return false; }
int pd_gpsp_save_dirty(void) { return 0; }
void pd_gpsp_flush_save(void) {}
int pd_gpsp_call(uint32_t fn, const uint32_t args[4], uint32_t* r0) { return 0; }
int pd_gpsp_call_safe(void) { return 0; }
void pd_gpsp_call_set_cap(long steps) {}
void pd_gpsp_rest_note(void) {}
void pd_gpsp_rest_reset(void) {}
void pd_gpsp_set_bkpt(bool (*hook)(uint32_t pc, unsigned immediate)) {}
uint32_t pd_gpsp_reg(int n) { return 0; }
void pd_gpsp_set_reg(int n, uint32_t v) {}
void pd_gpsp_jump(uint32_t to) {}
int pd_gpsp_vcount(void) { return 0; }
void pd_gpsp_hblank_skips(bool on) {}
void pd_gpsp_hblank_cost(int cycles) {}
bool pd_gpsp_save_state(const char* path) { return false; }
enum pd_gpsp_state pd_gpsp_load_state(const char* path) { return PD_GPSP_STATE_NO_FILE; }
