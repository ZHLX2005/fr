#include "metronome.h"
#include <oboe/Oboe.h>
#include <math.h>

using namespace oboe;

class Metronome : public AudioStreamCallback {
public:
    double bpm = 120.0;
    double sampleRate = 48000.0;
    int beatsPerBar = 4;
    bool useAccentTick = false;

    const float accentTickFrequency = 1500.0;
    const float regularTickFrequency = 1000.0;

    double samplesPerBeat;
    double sampleCounter = 0;

    int clickRemaining = 0;
    double frequency = 1000.0;
    int beat = 0;

    bool isPlaying = false;

    TickCallback tickCallback = nullptr;

    Metronome(double bpm_) : bpm(bpm_) {
        updateTiming();
        sampleCounter = samplesPerBeat;
    }

    void updateTiming() {
        samplesPerBeat = sampleRate * 60.0 / bpm;
    }

    void setBpm(double newBpm) {
        bpm = newBpm;
        updateTiming();
    }

    void setBeatsPerBar(int newBeatsPerBar) {
        beatsPerBar = newBeatsPerBar;
    }

    void setUseAccentTick(bool useAccentTick_) {
        useAccentTick = useAccentTick_;
    }

    void play() {
        beat = 0;
        sampleCounter = samplesPerBeat;
        isPlaying = true;
    }

    void pause() {
        isPlaying = false;
    }

    DataCallbackResult onAudioReady(AudioStream *stream,
                                    void *audioData,
                                    int32_t numFrames) override {

        float *out = static_cast<float *>(audioData);

        for (int i = 0; i < numFrames; i++) {

            if (!isPlaying) {
                *out++ = 0.0f;
                continue;
            }

            if (sampleCounter >= samplesPerBeat) {
                sampleCounter -= samplesPerBeat;

                clickRemaining = 200;
                frequency = calculateTickFrequency(beat);

                if (tickCallback) {
                    tickCallback(beat % beatsPerBar);
                }

                beat++;
            }

            float sample = 0.0f;

            if (clickRemaining > 0) {
                double t = (double) clickRemaining / sampleRate;

                sample = (float)(
                        0.8 *
                        sin(2.0 * M_PI * frequency * t) *
                        (clickRemaining / 200.0)
                );

                clickRemaining--;
            }

            *out++ = sample;
            sampleCounter++;
        }

        return DataCallbackResult::Continue;
    }

private:
    double calculateTickFrequency(int currentBeat) const {
        if (useAccentTick && (currentBeat % beatsPerBar == 0)) {
            return accentTickFrequency;
        }
        return regularTickFrequency;
    }
};

// =======================================================
// GLOBALS
// =======================================================

static Metronome *gMetronome = nullptr;
static AudioStream *gStream = nullptr;
static TickCallback gTickCallback = nullptr;

// =======================================================
// C INTERFACE
// =======================================================

extern "C" {

void init_audio(double bpm) {
    if (gStream) return;

    gMetronome = new Metronome(bpm);

    AudioStreamBuilder builder;
    builder.setDirection(Direction::Output);
    builder.setPerformanceMode(PerformanceMode::LowLatency);
    builder.setSharingMode(SharingMode::Exclusive);
    builder.setFormat(AudioFormat::Float);
    builder.setChannelCount(1);
    builder.setCallback(gMetronome);

    builder.openStream(&gStream);
    gStream->requestStart();

    gMetronome->sampleRate = gStream->getSampleRate();
    gMetronome->setBpm(bpm);
    gMetronome->tickCallback = gTickCallback;
}

void play_metronome() {
    if (gMetronome) {
        gMetronome->play();
    }
}

void pause_metronome() {
    if (gMetronome) {
        gMetronome->pause();
    }
}

void shutdown_audio() {
    if (!gStream) return;

    gStream->stop();
    gStream->close();

    delete gMetronome;

    gStream = nullptr;
    gMetronome = nullptr;
}


void set_bpm(double bpm) {
    if (gMetronome) {
        gMetronome->setBpm(bpm);
    }
}

void set_beats_per_bar(int beatsPerBar) {
    if (gMetronome) {
        gMetronome->setBeatsPerBar(beatsPerBar);
    }
}

void set_use_accent_tick(bool useAccentTick) {
    if (gMetronome) {
        gMetronome->setUseAccentTick(useAccentTick);
    }
}

void set_tick_callback(TickCallback callback) {
    gTickCallback = callback;
    if (gMetronome) {
        gMetronome->tickCallback = callback;
    }
}

}
