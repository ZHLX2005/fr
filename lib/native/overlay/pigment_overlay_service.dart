import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PigmentOverlayService {
  static final PigmentOverlayService _instance =
      PigmentOverlayService._internal();
  factory PigmentOverlayService() => _instance;
  PigmentOverlayService._internal();

  static const _channel = MethodChannel('io.github.xiaodouzi.fr/floating');

  bool _isActive = false;
  bool _hasPermission = false;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;
  bool get isActive => _isActive;
  bool get hasPermission => _hasPermission;

  Future<void> init() async {
    if (!isSupported) return;
    await checkOverlayPermission();
  }

  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    try {
      final value = await _channel.invokeMethod<bool>('checkOverlayPermission');
      _hasPermission = value ?? false;
      return _hasPermission;
    } on PlatformException {
      _hasPermission = false;
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException {
      return;
    }
  }

  Future<bool> start() async {
    if (!isSupported) return false;
    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
      await requestOverlayPermission();
      return false;
    }
    try {
      final value = await _channel.invokeMethod<bool>('startPigmentFloating');
      _isActive = value ?? false;
      return _isActive;
    } on PlatformException {
      _isActive = false;
      return false;
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopPigmentFloating');
      _isActive = false;
    } on PlatformException {
      return;
    }
  }

  Future<bool> isShowing() async {
    if (!isSupported) return false;
    try {
      final value = await _channel.invokeMethod<bool>(
        'isPigmentFloatingShowing',
      );
      _isActive = value ?? false;
      return _isActive;
    } on PlatformException {
      return false;
    }
  }
}
