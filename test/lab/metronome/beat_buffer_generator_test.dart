// 节拍缓冲区的时序校验。
//
// 节拍器的音频是"预渲染一段 WAV 然后 LoopMode.all 循环播放"，所以**循环缝**
// 也是一次真实的拍点：最后一拍到下一轮第一拍的间隔必须等于一拍，否则每循环一次
// 就多敲一下（听起来像"声音多重"），而且相位每循环跳一次（听起来像"音画偏移"）。
//
// 同理，一个循环里的总拍数必须是小节拍数的整数倍，否则下一轮的强拍会落在
// 小节中间 —— 3/4、6/8、5/4、7/8 尤其明显。
//
// 这两条都只跟生成出来的 PCM 有关，不需要音频设备，纯 Dart 就能钉住。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/beat_buffer_generator.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';

/// 从 WAV 字节里取回 PCM（跳过 44 字节头）
Int16List _pcmOf(Uint8List wav) {
  final bd = ByteData.sublistView(wav, 44);
  final out = Int16List(bd.lengthInBytes ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little);
  }
  return out;
}

/// 找出每个点击音的起始采样点。
///
/// 点击音是"正弦 + 指数衰减"，正弦每 44 个采样点会过一次零 —— 不加不应期
/// 就会把一次敲击算成几十次。这里用 clickDurationSec 作为不应期：一击一定
/// 在这个时长内衰减完，之后再触发的一定是下一拍。
List<int> _clickOnsets(Int16List pcm, {int silenceThreshold = 200}) {
  final refractory =
      (MetronomeDefaults.sampleRate * MetronomeDefaults.clickDurationSec)
          .toInt();
  final onsets = <int>[];
  var nextEligible = 0;
  for (var i = 0; i < pcm.length; i++) {
    if (i < nextEligible) continue;
    if (pcm[i].abs() > silenceThreshold) {
      onsets.add(i);
      nextEligible = i + refractory;
    }
  }
  return onsets;
}

void main() {
  const sampleRate = MetronomeDefaults.sampleRate;

  // 覆盖"整除"和"除不尽"两类 BPM：120 是 15 的倍数（老实现恰好没问题），
  // 140 / 100 / 73 除不尽（老实现每个循环都会多敲一下）
  const bpms = [60, 73, 100, 120, 140, 176, 200];

  group('循环缝必须正好是一拍', () {
    for (final bpm in bpms) {
      for (final pattern in MetronomePresets.patterns) {
        test('bpm=$bpm ${pattern.name}', () {
          final result = BeatBufferGenerator.generateLoop(
            bpm: bpm,
            beatPattern: pattern,
          );
          final pcm = _pcmOf(result.wav);
          final onsets = _clickOnsets(pcm);

          expect(onsets.length, result.beatsPerLoop,
              reason: '生成的点击数与声明的 beatsPerLoop 对不上');

          final expectedBeatSamples = pcm.length / result.beatsPerLoop;
          // 允许 1 个采样点（22µs）的取整误差
          const tol = 1.0;

          for (var i = 1; i < onsets.length; i++) {
            expect(
              (onsets[i] - onsets[i - 1]).toDouble(),
              closeTo(expectedBeatSamples, tol),
              reason: '第 $i 拍间隔不对',
            );
          }

          // 关键一条：跨过循环缝的那一拍
          final wrapInterval =
              (pcm.length - onsets.last) + onsets.first;
          expect(
            wrapInterval.toDouble(),
            closeTo(expectedBeatSamples, tol),
            reason: '循环缝处的间隔是 $wrapInterval 采样点，'
                '应为 ${expectedBeatSamples.toStringAsFixed(1)} —— '
                '每循环一次就会多敲一下',
          );
        });
      }
    }
  });

  group('循环长度必须是整数小节', () {
    for (final bpm in bpms) {
      for (final pattern in MetronomePresets.patterns) {
        test('bpm=$bpm ${pattern.name}', () {
          final result = BeatBufferGenerator.generateLoop(
            bpm: bpm,
            beatPattern: pattern,
          );
          expect(
            result.beatsPerLoop % pattern.beatsPerMeasure,
            0,
            reason: '一个循环 ${result.beatsPerLoop} 拍，不是 '
                '${pattern.beatsPerMeasure} 的整数倍 —— 下一轮强拍会落在小节中间',
          );
        });
      }
    }
  });

  group('循环时长与拍点定位', () {
    test('循环时长贴近 60/bpm * beatsPerLoop', () {
      for (final bpm in bpms) {
        final r = BeatBufferGenerator.generateLoop(
          bpm: bpm,
          beatPattern: MetronomePresets.defaultPattern,
        );
        final expectedSec = 60.0 / bpm * r.beatsPerLoop;
        final actualSec = r.loopSamples / sampleRate;
        expect(actualSec, closeTo(expectedSec, 1 / sampleRate));
      }
    });

    test('循环不短于设定的最小时长，避免磁盘/解码开销过大', () {
      for (final bpm in bpms) {
        final r = BeatBufferGenerator.generateLoop(
          bpm: bpm,
          beatPattern: MetronomePresets.defaultPattern,
        );
        expect(r.loopSamples / sampleRate,
            greaterThanOrEqualTo(MetronomeDefaults.minLoopSec));
      }
    });

    test('强拍确实比弱拍响', () {
      final r = BeatBufferGenerator.generateLoop(
        bpm: 120,
        beatPattern: MetronomePresets.defaultPattern, // 4/4，第 0 拍重音
      );
      final pcm = _pcmOf(r.wav);
      final onsets = _clickOnsets(pcm);

      int peakAt(int onset) {
        var peak = 0;
        for (var i = onset; i < onset + 800 && i < pcm.length; i++) {
          if (pcm[i].abs() > peak) peak = pcm[i].abs();
        }
        return peak;
      }

      expect(peakAt(onsets[0]), greaterThan(peakAt(onsets[1])));
    });
  });
}
