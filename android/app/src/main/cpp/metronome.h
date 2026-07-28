#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*TickCallback)(int);

void init_audio(double bpm);
void play_metronome();
void pause_metronome();
void shutdown_audio();
void set_bpm(double bpm);
void set_beats_per_bar(int beatsPerBar);
void set_tick_callback(TickCallback callback);
void set_use_accent_tick(bool useAccentTick);
void set_beat_accent_level(int beatIndex, int level);

// Custom WAV samples per accent level (0=weak, 1=medium, 2=accent).
// If a slot is loaded, that tone is played by streaming the WAV samples
// instead of the built-in synth click. Passing null or bad path clears
// the slot (falls back to synth).
//
// Returns 1 on success, 0 on failure (bad path / decode error / bad level).
int load_sample(int level, const char* path);
void clear_sample(int level);

#ifdef __cplusplus
}
#endif
