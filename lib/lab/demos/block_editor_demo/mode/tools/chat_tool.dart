import 'package:flutter/material.dart';

abstract class ChatTool {
  String get id;
  String get label;
  IconData get icon;
  String? get description;
}
