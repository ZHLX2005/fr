import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/discovery_service.dart';
import 'services/message_service.dart';

class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final String deviceId = const Uuid().v4();
  late final DiscoveryService discovery;
  late final MessageService message;

  String deviceAlias = 'Flutter Device';

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    discovery = DiscoveryService();
    message = MessageService(
      deviceId: deviceId,
      deviceAlias: deviceAlias,
    );

    // Set alias on discovery service
    discovery.deviceAlias = deviceAlias;

    debugPrint('[Localnet] Service initialized');
  }

  Future<void> start() async {
    init();
    await message.startServer();
    await discovery.startListening();
    debugPrint('[Localnet] Started');
  }

  void stop() {
    discovery.stop();
    message.stop();
    debugPrint('[Localnet] Stopped');
  }

  void dispose() {
    stop();
    discovery.dispose();
    message.dispose();
  }

  List<LocalnetDevice> get devices => discovery.devices;
  Stream<List<LocalnetDevice>> get devicesStream => discovery.devicesStream;

  List<LocalnetMessage> get messages => message.messages;
  Stream<List<LocalnetMessage>> get messagesStream => message.messagesStream;

  Future<bool> sendMessage(LocalnetDevice target, String content) {
    return message.sendMessage(target, content);
  }

  void updateAlias(String alias) {
    deviceAlias = alias;
    discovery.deviceAlias = alias;
  }
}

final localnetService = LocalnetService();
