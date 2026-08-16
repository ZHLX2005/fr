// test/core/schema/fr_widget_toggle_translate_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/app_lifecycle/fr_method_channel_translator.dart'
    show FrMethodChannelTranslator;

void main() {
  test('navigateToClockWidgetToggle → fr://clock/widget-toggle', () {
    final url = FrMethodChannelTranslator.translate(
      const MethodCall('navigateToClockWidgetToggle'),
    );
    expect(url, 'fr://clock/widget-toggle');
  });
}
