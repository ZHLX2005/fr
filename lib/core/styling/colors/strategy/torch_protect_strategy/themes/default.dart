// Layer 2 — DefaultTorchProtectStrategy：从 tokens/color/torch 派生护眼色。

import 'package:flutter/material.dart';

import '../../../../tokens/color/torch/torch.dart';
import '../torch_protect_strategy.dart';

class DefaultTorchProtectStrategy extends TorchProtectStrategy {
  @override
  final ColorScheme scheme;

  static DefaultTorchProtectStrategy? _cached;

  factory DefaultTorchProtectStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultTorchProtectStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultTorchProtectStrategy._(this.scheme);

  @override
  Color get protectWarmYellow => TorchColors.protectWarmYellow(scheme);

  @override
  Color get protectWarmOrange => TorchColors.protectWarmOrange(scheme);

  @override
  Color get protectNeutral => TorchColors.protectNeutral(scheme);

  @override
  Color get protectCoolWhite => TorchColors.protectCoolWhite(scheme);

  @override
  List<Color> get protectPresets => TorchColors.protectPresets(scheme);

  @override
  List<String> get protectPresetNames => TorchColors.protectPresetNames;
}