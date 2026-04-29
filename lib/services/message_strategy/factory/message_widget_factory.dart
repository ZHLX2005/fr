import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';

/// Map type alias for strategy registry
typedef MessageWidgetStrategyMap = Map<String, MessageWidgetStrategy<IMessageData>>;

/// Factory for creating message widgets based on type
/// Uses O(1) lookup via Map
class MessageWidgetFactory {
  final MessageWidgetStrategyMap _strategies;

  MessageWidgetFactory(this._strategies);

  /// Create widget for the given message data
  /// Throws UnsupportedError if no strategy found for type
  Widget create(BuildContext context, IMessageData data) {
    final strategy = _strategies[data.type];
    if (strategy == null) {
      throw UnsupportedError(
        'No widget strategy for type: ${data.type}',
      );
    }
    return strategy.build(context, data);
  }
}
