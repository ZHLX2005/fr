import 'package:flutter/material.dart';

import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import 'nxnx_option_form.dart';

/// nx-nx 原生面板的**视觉语言**：无色块 + 边框强调。
///
/// ## 为什么不用色块
///
/// 面板要显示的东西很多（模板、选项、说明、文件清单、脚本源码），
/// 一层层叠色块会让页面变成一片糊 —— 每一块都在喊「看我」，
/// 结果哪块都看不清。
///
/// 这里的规矩是：
///   · **块与块之间靠描边分开**，不靠底色
///   · **状态靠描边强弱区分**，不靠填充
///     （选中 = 描边换成强调色；普通 = 弱描边）
///   · **底色一律透明**，让页面底色透上来
///
/// 于是「层次」是**线**画出来的，不是色块堆出来的。
class NxNxBlock extends StatelessWidget {
  /// 块标题（可空 → 无头块）。
  final String? title;

  /// 块头右侧的内容（计数、动作按钮）。
  final Widget? trailing;

  final Widget child;

  /// 强调态：描边换成强调色（用于「当前选中」）。
  final bool emphasized;

  /// 紧凑内边距（列表类块）。
  final bool dense;

  const NxNxBlock({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.emphasized = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = emphasized ? cs.outline : cs.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border, width: emphasized ? 1.6 : 1),
        borderRadius: AppBorderRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            NxNxBlockHeader(title: title!, trailing: trailing),
          Padding(
            padding: EdgeInsets.all(dense ? AppSpacing.xs : AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 块头：标题 + 右侧内容 + 一条分隔线。
///
/// 分隔线而不是色块 —— 层次靠线，不靠面。
class NxNxBlockHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const NxNxBlockHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 小标签：**描边**的，不是填充的。
class NxNxTag extends StatelessWidget {
  final String text;
  final bool strong;
  final Color? color;

  const NxNxTag(this.text, {super.key, this.strong = false, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? (strong ? cs.primary : cs.outline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: AppBorderRadius.allXs,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: c, height: 1.2),
      ),
    );
  }
}

/// 块内的一行「标签 — 值」。
class NxNxKeyValue extends StatelessWidget {
  /// 左边的标签（**不叫 key** —— `key` 是 Widget 的保留名）。
  final String label;
  final String value;
  final Widget? trailing;

  const NxNxKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 空态：一行灰字 + 可选提示。
class NxNxEmpty extends StatelessWidget {
  final String text;
  final String? hint;

  const NxNxEmpty(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: 12, color: cs.outline)),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hint!,
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// 列表里的一项（可选中）。
///
/// 选中态 = **描边**变强调色，不是铺底色。
class NxNxSelectableItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const NxNxSelectableItem({
    super.key,
    required this.title,
    this.subtitle,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.allXs,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: AppBorderRadius.allXs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: cs.outline, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一个**选项**的输入控件（按 schema 的 type 渲染）。
///
/// 面板不认识任何具体的选项名 —— 类型决定控件，模板加一个选项就多一个控件。
class NxNxOptionField extends StatelessWidget {
  final NxNxOption option;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  const NxNxOptionField({
    super.key,
    required this.option,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = nxNxOptionLabel(option);
    final type = option.type.isEmpty ? 'string' : option.type;
    final err = nxNxValidateOption(option, value);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              if (option.required)
                Text(
                  ' *',
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              const SizedBox(width: AppSpacing.xs),
              NxNxTag(type),
            ],
          ),
          if (option.hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                option.hint,
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          _control(context, type),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                err,
                style: TextStyle(fontSize: 11, color: cs.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _control(BuildContext context, String type) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: AppBorderRadius.allXs,
      borderSide: BorderSide(color: cs.outlineVariant),
    );

    if (type == 'boolean') {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(
          value == true ? '开' : '关',
          style: const TextStyle(fontSize: 12),
        ),
        value: value == true,
        onChanged: (v) => onChanged(v),
      );
    }

    if (type == 'enum') {
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: option.values.map((v) {
          final on = '$value' == v;
          return InkWell(
            onTap: () => onChanged(v),
            borderRadius: AppBorderRadius.allXs,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: on ? cs.primary : cs.outlineVariant,
                  width: on ? 1.6 : 1,
                ),
                borderRadius: AppBorderRadius.allXs,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              child: Text(v, style: const TextStyle(fontSize: 12)),
            ),
          );
        }).toList(),
      );
    }

    if (type == 'number') {
      return TextField(
        style: const TextStyle(fontSize: 12),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          isDense: true,
          hintText: option.defaultValue?.toString() ?? '',
          border: border,
        ),
        controller: TextEditingController(text: '${value ?? ''}')
          ..selection = TextSelection.collapsed(offset: '${value ?? ''}'.length),
        onChanged: (v) => onChanged(v),
      );
    }

    return TextField(
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: option.defaultValue?.toString() ?? '',
        border: border,
      ),
      controller: TextEditingController(text: '${value ?? ''}')
        ..selection = TextSelection.collapsed(offset: '${value ?? ''}'.length),
      onChanged: (v) => onChanged(v),
    );
  }
}
