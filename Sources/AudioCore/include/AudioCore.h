#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *HollowEngine;
HollowEngine hollow_create(void);
void hollow_destroy(HollowEngine engine);
// process=0 captures system audio excluding this process. Otherwise a Core Audio process object ID.
int32_t hollow_start(HollowEngine engine, uint32_t process);
void hollow_stop(HollowEngine engine);
void hollow_configure(HollowEngine engine, float space, float warmth, float orbit, float gain, int bypass);
// Asset copies happen on the control thread; published banks stay immutable until destruction.
// Test/offline renderer only; does nothing while the live device is running.
void hollow_render_offline(HollowEngine engine, float *stereo, uint32_t frames, double sampleRate);
int hollow_load_sound(HollowEngine engine, int slot, const float *stereo, uint32_t frames, double rate);
int hollow_begin_sound(HollowEngine engine, int slot, uint32_t frames, double rate);
int hollow_append_sound(HollowEngine engine, int slot, const float *stereo, uint32_t frames);
int hollow_finish_sound(HollowEngine engine, int slot);
void hollow_track_gain(HollowEngine engine, int slot, float gain);
void hollow_mix(HollowEngine engine, float ambience, float music, float fade);
void hollow_spatial(HollowEngine engine, int enabled);
void hollow_position(HollowEngine engine, int slot, int direction, float distance);
float hollow_peak(HollowEngine engine);
uint64_t hollow_callbacks(HollowEngine engine);
uint32_t hollow_output_device(HollowEngine engine);
double hollow_sample_rate(HollowEngine engine);
const char *hollow_error(HollowEngine engine);
#ifdef __cplusplus
}
#endif
