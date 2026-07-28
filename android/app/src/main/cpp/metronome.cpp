#include "metronome.h"
#include <oboe/Oboe.h>
#include <math.h>
#include <string.h>

#define DR_WAV_IMPLEMENTATION
#include "dr_wav.h"

using namespace oboe;

// One WAV slot per accent level (0=weak, 1=medium, 2=accent).
// pcm points to float32 mono samples resampled to the audio stream's sampleRate.
// playPos < 0 means the slot is idle; when a beat fires we set playPos = 0
// and the mixer pulls from pcm[playPos++] until pcm exhausted.
struct SampleSlot {
    float* pcm = nullptr;         // interleaved is not used; we downmix to mono at load
    int lengthSamples = 0;        // total samples in pcm
    int playPos = -1;             // -1 = idle, else next-sample index
};

// The slot's pcm buffer is owned here. Freed by clear_sample or process exit.
static SampleSlot gSlots[3];

// Free the pcm buffer of a slot if any. Safe to call repeatedly.
static void freeSlot(int level) {
    if (level < 0 || level > 2) return;
    if (gSlots[level].pcm) {
        free(gSlots[level].pcm);
        gSlots[level].pcm = nullptr;
    }
    gSlots[level].lengthSamples = 0;
    gSlots[level].playPos = -1;
}

// Load a WAV via dr_wav, downmix to mono, resample (linear) to the target sample
// rate, and store into gSlots[level].pcm. Returns true on success.
// This is called on the Dart-invoking thread (usually main isolate), NOT the
// audio thread. The audio thread only reads gSlots via the atomic-ish assignment
// pattern below. We accept a tiny race window on hot-swap because a click sample
// abort at worst produces a dropped tick.
static bool loadSampleInto(int level, const char* path, double targetSampleRate) {
    if (level < 0 || level > 2 || !path) return false;

    unsigned int channels = 0;
    unsigned int sampleRate = 0;
    drwav_uint64 totalPCMFrames = 0;
    // Decode to float32.
    float* raw = drwav_open_file_and_read_pcm_frames_f32(
        path, &channels, &sampleRate, &totalPCMFrames, nullptr);
    if (!raw || totalPCMFrames == 0 || channels == 0 || sampleRate == 0) {
        if (raw) drwav_free(raw, nullptr);
        return false;
    }

    // Downmix to mono. `raw` is interleaved: frame0[ch0..chN] frame1[...] ...
    // We average across channels per frame.
    const int inFrames = (int) totalPCMFrames;
    float* mono = (float*) malloc(sizeof(float) * inFrames);
    if (!mono) { drwav_free(raw, nullptr); return false; }
    for (int i = 0; i < inFrames; i++) {
        float sum = 0.0f;
        for (unsigned int c = 0; c < channels; c++) {
            sum += raw[i * channels + c];
        }
        mono[i] = sum / (float) channels;
    }
    drwav_free(raw, nullptr);

    // Resample (linear interpolation) to targetSampleRate.
    float* out;
    int outFrames;
    if ((double) sampleRate == targetSampleRate) {
        out = mono;
        outFrames = inFrames;
    } else {
        const double ratio = targetSampleRate / (double) sampleRate;
        outFrames = (int) ((double) inFrames * ratio);
        if (outFrames < 1) outFrames = 1;
        out = (float*) malloc(sizeof(float) * outFrames);
        if (!out) { free(mono); return false; }
        for (int i = 0; i < outFrames; i++) {
            const double srcIdx = (double) i / ratio;
            const int i0 = (int) srcIdx;
            const int i1 = (i0 + 1 < inFrames) ? i0 + 1 : i0;
            const float frac = (float) (srcIdx - (double) i0);
            out[i] = mono[i0] * (1.0f - frac) + mono[i1] * frac;
        }
        free(mono);
    }

    // Swap in. Free old first — a stale pointer would be a bigger risk than
    // a dropped tick on the audio thread during the swap.
    freeSlot(level);
    gSlots[level].pcm = out;
    gSlots[level].lengthSamples = outFrames;
    gSlots[level].playPos = -1;
    return true;
}

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

                // If this level has a WAV sample loaded, arm it. This is atomic
                // enough for our purposes — a torn write between load_sample and
                // this line would at worst play the wrong tone once.
                if (level >= 0 && level <= 2 && gSlots[level].pcm) {
                    gSlots[level].playPos = 0;
                    // When sample is armed, we skip the synth click so we don't
                    // stack the two on top of each other.
                    clickRemaining = 0;
                }

                if (tickCallback) {
                    tickCallback(idxInBar);
                }

                beat++;
            }

            float sample = 0.0f;

            // 1) Mix any active WAV slots (may have multiple in-flight if BPM
            //    is fast and sample is long — that's fine, they overlap.)
            for (int s = 0; s < 3; s++) {
                SampleSlot& slot = gSlots[s];
                if (slot.playPos >= 0 && slot.pcm && slot.playPos < slot.lengthSamples) {
                    sample += slot.pcm[slot.playPos];
                    slot.playPos++;
                    if (slot.playPos >= slot.lengthSamples) {
                        slot.playPos = -1;  // done
                    }
                }
            }

            // 2) Synth click (only if no sample armed this cycle — clickRemaining
            //    was zeroed above when a sample was loaded).
            if (clickRemaining > 0) {
                double t = (double) clickRemaining / sampleRate;
                // 指数衰减包络
                float env = (float)(clickRemaining / (float)currentTone.clickSamples);

                float base = (float)sin(2.0 * M_PI * currentTone.frequency * t);
                float harmonic2 = currentTone.with2xHarmonic
                    ? (float)(0.4 * sin(2.0 * M_PI * currentTone.frequency * 2.0 * t)) : 0.0f;
                float harmonic3 = currentTone.with3xHarmonic
                    ? (float)(0.2 * sin(2.0 * M_PI * currentTone.frequency * 3.0 * t)) : 0.0f;

                sample += currentTone.amplitude * env * (base + harmonic2 + harmonic3);

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

    // NOTE: We deliberately do NOT free gSamples here.  Samples are user
    // configuration (woodfish etc.) and may outlive a stream open/close
    // cycle — e.g. the user loads woodfish in the metronome demo, leaves,
    // and the Clock demo continues to use it.  Explicit cleanup happens via
    // clear_sample() or the next load_sample() (which frees its own slot
    // before reassigning).
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

// Load a WAV file and mount it to the given accent level slot.
// Uses the current audio stream's sampleRate for resampling.
// Returns 1 on success, 0 on failure.
int load_sample(int level, const char* path) {
    if (!gMetronome) return 0;
    return loadSampleInto(level, path, gMetronome->sampleRate) ? 1 : 0;
}

void clear_sample(int level) {
    freeSlot(level);
}

}