import '../interfaces/message_data.dart';

/// Selection option item
class SelectionOption {
  final String id;
  final String label;

  const SelectionOption({
    required this.id,
    required this.label,
  });
}

/// Selection message data - multiple choice with confirm/cancel
class SelectionMessageData implements IMessageData {
  /// Question text
  final String question;

  /// Available options
  final List<SelectionOption> options;

  /// Whether multiple selection is allowed
  final bool multiSelect;

  /// Minimum selections required (0 = no minimum)
  final int minSelect;

  /// Maximum selections allowed (0 = no maximum)
  final int maxSelect;

  SelectionMessageData({
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.minSelect = 0,
    this.maxSelect = 0,
  });

  @override
  String get type => 'selection';
}
