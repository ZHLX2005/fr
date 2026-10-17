// Layer 2 — DefaultTorchProtectColorStrategy：从 tokens/color/torch 派生护眼色。

import 'package:flutter/material.dart';

import '../../../../tokens/color/torch.dart';
import '../torch_protect_color_strategy.dart';

class DefaultTorchProtectColorStrategy extends TorchProtectColorStrategy {
  @override
  final ColorScheme scheme;

  static DefaultTorchProtectColorStrategy? _cached;

  factory DefaultTorchProtectColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultTorchProtectColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultTorchProtectColorStrategy._(this.scheme);

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