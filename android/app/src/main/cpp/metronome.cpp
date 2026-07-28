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

    // 三档音色参数：频率 / 振幅 / 时长 / 谐波
    // 设计目标：weak→medium→accent 听感差距必须明显可辨
    struct Tone {
        float frequency;       // 基频
        float amplitude;       // 振幅（与混合叠加后的总峰值成正比）
        int clickSamples;      // 点击音持续采样数
        bool with2xHarmonic;   // 是否加 2x 谐波
        bool with3xHarmonic;   // 是否加 3x 谐波
    };

    // weak（弱拍）：低频、闷、短、不加谐波
    Tone weakTone   {  700.0f, 0.4f,  200, false, false };
    // medium（次强）：中频、中振幅、稍短、加 2x 谐波
    Tone mediumTone { 1400.0f, 0.7f,  200, true,  false };
    // accent（强拍）：高频、最响、最长、加 2x + 3x 谐波
    Tone accentTone { 2200.0f, 1.0f,  300, true,  true  };

    // 每拍的重音级别数组（0/1/2）。默认全 0；set_beat_accent_level 由 Dart 注入。
    // 大小由 set_beats_per_bar 时分配。
    int* beatAccentLevels = nullptr;
    int currentAccentLevel = 0;  // 当前正在合成的这拍的重音级别（默认 weak）

    double samplesPerBeat;
    double sampleCounter = 0;

    int clickRemaining = 0;
    Tone currentTone{};
    int beat = 0;

    bool isPlaying = false;

    TickCallback tickCallback = nullptr;

    Metronome(double bpm_) : bpm(bpm_) {
        updateTiming();
        sampleCounter = samplesPerBeat;
        allocateLevels(beatsPerBar);
        applyTone(kWeakTone);
    }

    ~Metronome() {
        if (beatAccentLevels) {
            delete[] beatAccentLevels;
            beatAccentLevels = nullptr;
        }
    }

    void allocateLevels(int count) {
        if (beatAccentLevels) delete[] beatAccentLevels;
        beatAccentLevels = new int[count];
        // 默认：第 0 拍是 accent，其它全 weak
        for (int i = 0; i < count; i++) {
            beatAccentLevels[i] = (i == 0) ? kAccentTone : kWeakTone;
        }
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
        allocateLevels(newBeatsPerBar);
    }

    void setUseAccentTick(bool useAccentTick_) {
        useAccentTick = useAccentTick_;
    }

    void setBeatAccentLevel(int beatIndex, int level) {
        if (!beatAccentLevels) return;
        if (beatIndex < 0 || beatIndex >= beatsPerBar) return;
        if (level < kWeakTone || level > kAccentTone) return;
        beatAccentLevels[beatIndex] = level;
    }

    static constexpr int kWeakTone   = 0;
    static constexpr int kMediumTone = 1;
    static constexpr int kAccentTone = 2;

    void applyTone(int level) {
        currentAccentLevel = level;
        switch (level) {
            case kAccentTone:  currentTone = accentTone; break;
            case kMediumTone:  currentTone = mediumTone; break;
            case kWeakTone:
            default:           currentTone = weakTone;   break;
        }
        clickRemaining = currentTone.clickSamples;
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

                int idxInBar = beat % beatsPerBar;
                int level = beatAccentLevels ? beatAccentLevels[idxInBar] : kWeakTone;
                applyTone(level);

                if (tickCallback) {
                    tickCallback(idxInBar);
                }

                beat++;
            }

            float sample = 0.0f;

            if (clickRemaining > 0) {
                double t = (double) clickRemaining / sampleRate;
                // 指数衰减包络
                float env = (float)(clickRemaining / (float)currentTone.clickSamples);

                float base = (float)sin(2.0 * M_PI * currentTone.frequency * t);
                float harmonic2 = currentTone.with2xHarmonic
                    ? (float)(0.4 * sin(2.0 * M_PI * currentTone.frequency * 2.0 * t)) : 0.0f;
                float harmonic3 = currentTone.with3xHarmonic
                    ? (float)(0.2 * sin(2.0 * M_PI * currentTone.frequency * 3.0 * t)) : 0.0f;

                sample = currentTone.amplitude * env * (base + harmonic2 + harmonic3);

                clickRemaining--;
            }

            // 钳位到 [-1, 1]，避免 accent+谐波叠加溢出
            if (sample > 1.0f) sample = 1.0f;
            else if (sample < -1.0f) sample = -1.0f;

            *out++ = sample;
            sampleCounter++;
        }

        return DataCallbackResult::Continue;
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

void set_beat_accent_level(int beatIndex, int level) {
    if (gMetronome) {
        gMetronome->setBeatAccentLevel(beatIndex, level);
    }
}

void set_tick_callback(TickCallback callback) {
    gTickCallback = callback;
    if (gMetronome) {
        gMetronome->tickCallback = callback;
    }
}

}