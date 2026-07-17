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

/// 节拍缓冲区生成器
class BeatBufferGenerator {
  /// 生成节拍缓冲区（WAV 格式）
  ///
  /// [bpm] 每分钟节拍数
  /// [beatPattern] 节拍模式
  /// [sampleRate] 采样率（默认 44100）
  /// [durationSec] 生成的总时长（秒）
  static Uint8List generate({
    required int bpm,
    required BeatPattern beatPattern,
    int sampleRate = MetronomeDefaults.sampleRate,
    double durationSec = MetronomeDefaults.bufferDurationSec,
  }) {
    final beatIntervalSec = 60.0 / bpm;
    final totalSamples = (sampleRate * durationSec).toInt();
    final buffer = Int16List(totalSamples);

    // 节拍音参数
    final clickSamples = (sampleRate * MetronomeDefaults.clickDurationSec).toInt();

    // 填充缓冲区
    double time = 0.0;
    int beatIndex = 0;
    while (time < durationSec) {
      final startSample = (time * sampleRate).toInt();
      if (startSample >= totalSamples) break;

      // 获取当前拍的重音级别
      final accentLevel = beatPattern.getAccentLevel(beatIndex % beatPattern.beatsPerMeasure);

      // 获取对应参数
      final amplitude = AccentVolume.getVolume(accentLevel);
      final frequency = AccentFrequency.getFrequency(accentLevel);

      // 生成点击音
      _generateClick(
        buffer: buffer,
        startSample: startSample,
        clickSamples: clickSamples,
        amplitude: amplitude,
        frequency: frequency,
        sampleRate: sampleRate,
      );

      // 前进到下一拍
      time += beatIntervalSec;
      beatIndex++;
    }

    // 转换为 WAV 格式
    return WavGenerator.generateWav(pcmData: buffer, sampleRate: sampleRate);
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

  /// 生成单拍音（用于预加载）
  ///
  /// [accentLevel] 重音级别
  /// [sampleRate] 采样率
  static Uint8List generateSingleClick({
    required AccentLevel accentLevel,
    int sampleRate = MetronomeDefaults.sampleRate,
  }) {
    final clickDurationSec = 0.08;
    final clickSamples = (sampleRate * clickDurationSec).toInt();
    final buffer = Int16List(clickSamples);

    final amplitude = AccentVolume.getVolume(accentLevel);
    final frequency = AccentFrequency.getFrequency(accentLevel);

    for (int i = 0; i < clickSamples; i++) {
      final t = i / sampleRate;
      final envelope = math.exp(-t * 60);
      final sine = math.sin(2 * math.pi * frequency * t);
      final value = (amplitude * sine * envelope * 32767).round();
      buffer[i] = value.clamp(-32768, 32767);
    }

    return WavGenerator.generateWav(pcmData: buffer, sampleRate: sampleRate);
  }
}
