#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *ASMEULEngine;
ASMEULEngine asmeul_create(void);
void asmeul_destroy(ASMEULEngine engine);
// process=0 captures system audio excluding this process. Otherwise a Core Audio process object ID.
int32_t asmeul_start(ASMEULEngine engine, uint32_t process);
// Explicit app scope: an empty list captures silence, never the whole system.
int32_t asmeul_start_processes(ASMEULEngine engine, const uint32_t *processes, uint32_t count);
// Poll on the control thread after start: 0 = waiting with original audio
// intact, 1 = verified capture routed through the mixer, -1 = failed/stopped.
int32_t asmeul_poll_capture(ASMEULEngine engine);
int32_t asmeul_update_processes(ASMEULEngine engine, const uint32_t *processes, uint32_t count);
void asmeul_stop(ASMEULEngine engine);
void asmeul_configure(ASMEULEngine engine, float space, float warmth, float orbit, float gain, int bypass);
// Asset copies happen on the control thread; published banks stay immutable
// while live and are retired before control-thread reclamation after render.
// Test/offline renderer only; does nothing while the live device is running.
void asmeul_render_offline(ASMEULEngine engine, float *stereo, uint32_t frames, double sampleRate);
int asmeul_load_sound(ASMEULEngine engine, int slot, const float *stereo, uint32_t frames, double rate);
int asmeul_begin_sound(ASMEULEngine engine, int slot, uint32_t frames, double rate);
int asmeul_append_sound(ASMEULEngine engine, int slot, const float *stereo, uint32_t frames);
int asmeul_finish_sound(ASMEULEngine engine, int slot);
// Both engines are exclusively owned by the caller; source must be stopped.
// Moves a prepared immutable recording without copying or decoding on the UI thread.
int asmeul_take_sound(ASMEULEngine destination, ASMEULEngine source, int slot);
void asmeul_collect_sounds(ASMEULEngine engine);
uint64_t asmeul_sound_bytes(ASMEULEngine engine);
void asmeul_unload_sound(ASMEULEngine engine, int slot);
void asmeul_track_gain(ASMEULEngine engine, int slot, float gain);
void asmeul_mix(ASMEULEngine engine, float ambience, float music, float fade);
void asmeul_spatial(ASMEULEngine engine, int enabled);
void asmeul_position(ASMEULEngine engine, int slot, int direction, float distance);
float asmeul_peak(ASMEULEngine engine);
uint64_t asmeul_callbacks(ASMEULEngine engine);
uint32_t asmeul_output_device(ASMEULEngine engine);
double asmeul_sample_rate(ASMEULEngine engine);
const char *asmeul_error(ASMEULEngine engine);
#ifdef __cplusplus
}
#endif
