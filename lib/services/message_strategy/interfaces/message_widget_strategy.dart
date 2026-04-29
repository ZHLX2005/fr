import 'package:flutter/material.dart';
import 'message_data.dart';

/// Strategy interface for rendering message widgets
abstract class MessageWidgetStrategy<T extends IMessageData> {
  Widget build(BuildContext context, T data);
  T createMockData();
}
