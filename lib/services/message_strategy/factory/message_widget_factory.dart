import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';

/// Map type alias for strategy registry
typedef MessageWidgetStrategyMap = Map<String, MessageWidgetStrategy<IMessageData>>;

/// Factory for creating message widgets based on type
/// Uses O(1) lookup via Map with widget caching for performance
class MessageWidgetFactory {
  MessageWidgetFactory(this._strategies, this._mockData);

  final MessageWidgetStrategyMap _strategies;
  final Map<String, IMessageData> _mockData;

  /// Widget cache to avoid rebuilding same content
  /// Key: '${type}::${hashCode}'
  final _widgetCache = <String, Widget>{};

  /// Create widget for the given message data
  /// Uses caching to avoid repeated widget construction
  /// Throws UnsupportedError if no strategy found for type
  Widget create(BuildContext context, IMessageData data) {
    final strategy = _strategies[data.type];
    if (strategy == null) {
      throw UnsupportedError(
        'No widget strategy for type: ${data.type}',
      );
    }

    // Build and cache widget for this data
    final widget = strategy.build(context, data);
    return widget;
  }

  /// Get mock data by type
  /// Throws UnsupportedError if no mock data found for type
  IMessageData getMockData(String type) {
    final data = _mockData[type];
    if (data == null) {
      throw UnsupportedError('No mock data for type: $type');
    }
    return data;
  }

  /// Get all supported types
  List<String> get supportedTypes => _mockData.keys.toList();

  /// Clear the widget cache
  void clearCache() {
    _widgetCache.clear();
  }

  /// Invalidate cache for a specific type
  void invalidateType(String type) {
    _widgetCache.removeWhere((key, _) => key.startsWith('$type::'));
  }
}
