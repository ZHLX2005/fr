// lib/core/surround_game/lan/profile/alias_dialog.dart
//
// 进 LanLobbyPage 时弹窗：让用户填本机名称（deviceAlias）。
// 返回 Future<String?>，null=取消。

import 'package:flutter/material.dart';

class AliasDialog extends StatefulWidget {
  const AliasDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AliasDialog(),
    );
  }

  @override
  State<AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<AliasDialog> {
  final _ctrl = TextEditingController(text: 'Player');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onOk() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_ctrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置本机名称'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '将显示在房间列表中',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '名称不能为空';
            if (v.trim().length > 16) return '名称过长';
            return null;
          },
          onFieldSubmitted: (_) => _onOk(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _onOk, child: const Text('确定')),
      ],
    );
  }
}
