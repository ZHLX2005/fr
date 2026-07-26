import 'dart:math' as math;
import 'dart:typed_data';

import 'const_metronome.dart';

/// WAV 文件生成工具
class WavGenerator {
  /// 生成 WAV 格式的字节数据
  ///
  /// [pcmData] PCM 格式的 Int16List 数据
  /// [sampleRate] 采样率
  static Uint8List generateWav({
    required Int16List pcmData,
    required int sampleRate,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length * 2; // 16-bit = 2 bytes per sample
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    int offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // R
    buffer.setUint8(offset++, 0x49); // I
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // W
    buffer.setUint8(offset++, 0x41); // A
    buffer.setUint8(offset++, 0x56); // V
    buffer.setUint8(offset++, 0x45); // E

    // fmt chunk
    buffer.setUint8(offset++, 0x66); // f
    buffer.setUint8(offset++, 0x6D); // m
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x20); // space
    buffer.setUint32(offset, 16, Endian.little); // chunk size
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little); // audio format (PCM)
    offset += 2;
    buffer.setUint16(offset, numChannels, Endian.little);
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    buffer.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little);
    offset += 2;

    // data chunk
    buffer.setUint8(offset++, 0x64); // d
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    // PCM data
    for (int i = 0; i < pcmData.length; i++) {
      buffer.setInt16(offset, pcmData[i], Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}

/// 一段可无缝循环的节拍音频
class BeatLoop {
  const BeatLoop({
    required this.wav,
    required this.beatsPerLoop,
    required this.loopSamples,
    required this.sampleRate,
  });

  /// WAV 字节（含 44 字节头）
  final Uint8List wav;

  /// 一个循环里有多少拍（保证是 beatsPerMeasure 的整数倍）
  final int beatsPerLoop;

  /// 一个循环的采样点数
  final int loopSamples;

  final int sampleRate;

  /// 一个循环的时长
  Duration get loopDuration =>
      Duration(microseconds: (loopSamples * 1000000 / sampleRate).round());

  /// 一拍的时长（由循环长度均分得到，与音频里实际的拍点位置一致）
  Duration get beatDuration => Duration(
      microseconds:
          (loopSamples * 1000000 / sampleRate / beatsPerLoop).round());
}

/// 节拍缓冲区生成器
class BeatBufferGenerator {
  /// 生成一段**可无缝循环**的节拍音频。
  ///
  /// 这里有两条硬约束，破了任何一条都会被用户听出来：
  ///
  /// 1. **循环长度必须是整数拍**。播放用的是 LoopMode.all，循环缝就是一次真实
  ///    拍点。旧实现固定生成 4.0 秒，只有 bpm 是 15 的倍数时才凑巧对齐；
  ///    bpm=140 时最后一拍到循环点只隔了三分之一拍 —— 每 4 秒抢敲一下，
  ///    听起来就是"声音多重"，相位也跟着每 4 秒跳一次（"音画偏移"）。
  /// 2. **循环长度必须是整数小节**，否则下一轮的强拍落在小节中间，
  ///    3/4、6/8、5/4、7/8 会明显串味。
  ///
  /// 做法：先按 [minLoopSec] 向上取整到整数小节得到 [BeatLoop.beatsPerLoop]，
  /// 再把第 k 拍放在 `round(k * loopSamples / beatsPerLoop)` —— 用整数采样点
  /// 均分，取整误差不累积（单拍最多差半个采样点，约 11µs）。
  static BeatLoop generateLoop({
    required int bpm,
    required BeatPattern beatPattern,
    int sampleRate = MetronomeDefaults.sampleRate,
    double minLoopSec = MetronomeDefaults.minLoopSec,
  }) {
    final beatsPerMeasure = beatPattern.beatsPerMeasure;
    final measureSec = 60.0 / bpm * beatsPerMeasure;
    final measures = math.max(1, (minLoopSec / measureSec).ceil());
    final beatsPerLoop = measures * beatsPerMeasure;

    final loopSamples = (sampleRate * 60.0 * beatsPerLoop / bpm).round();
    final buffer = Int16List(loopSamples);
    final clickSamples =
        (sampleRate * MetronomeDefaults.clickDurationSec).toInt();

    for (int k = 0; k < beatsPerLoop; k++) {
      // 用循环总长均分，而不是累加 beatIntervalSec —— 累加会把浮点误差攒起来
      final startSample = (k * loopSamples / beatsPerLoop).round();
      final accentLevel = beatPattern.getAccentLevel(k % beatsPerMeasure);

      _generateClick(
        buffer: buffer,
        startSample: startSample,
        clickSamples: clickSamples,
        amplitude: AccentVolume.getVolume(accentLevel),
        frequency: AccentFrequency.getFrequency(accentLevel),
        sampleRate: sampleRate,
      );
    }

    return BeatLoop(
      wav: WavGenerator.generateWav(pcmData: buffer, sampleRate: sampleRate),
      beatsPerLoop: beatsPerLoop,
      loopSamples: loopSamples,
      sampleRate: sampleRate,
    );
  }

  /// 生成点击音
  /// 使用正弦波 + 指数衰减模拟打击乐音头
  static void _generateClick({
    required Int16List buffer,
    required int startSample,
    required int clickSamples,
    required double amplitude,
    required double frequency,
    required int sampleRate,
  }) {
    for (int i = 0; i < clickSamples && (startSample + i) < buffer.length; i++) {
      final t = i / sampleRate;
      // 指数衰减包络
      final envelope = math.exp(-t * 80);
      // 正弦波 + 少量谐波增加清脆感
      final sine = math.sin(2 * math.pi * frequency * t);
      final harmonic = 0.3 * math.sin(2 * math.pi * frequency * 2 * t);
      final wave = sine + harmonic * 0.3;
      final value = (amplitude * wave * envelope * 32767).round();
      buffer[startSample + i] = value.clamp(-32768, 32767);
    }
  }
}
