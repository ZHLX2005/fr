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

#ifdef __cplusplus
}
#endif
