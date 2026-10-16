import 'package:flutter/material.dart';

/// 用药与急救卡模块共用的表单视觉规范。
///
/// 全局主题里的 `inputDecorationTheme` 是"白色 78% 填充 + 无边框"，
/// 而对话框底色是近白（`0xFFFFFBFF`）——两者叠在一起输入区几乎隐形，
/// 用户看不出哪儿能点。这里统一换成可辨识的浅灰底 + 淡描边。
/// （只在本模块内生效，不动共享主题文件。）
InputDecoration medicationFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? suffix,
  String? errorText,
  Widget? suffixIcon,
  int maxLines = 1,
}) {
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  final idle = scheme.outlineVariant.withValues(alpha: 0.75);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    suffixIcon: suffixIcon,
    errorText: errorText,
    isDense: true,
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: maxLines > 1 ? 12 : 14,
    ),
    border: border(idle, 1),
    enabledBorder: border(idle, 1),
    focusedBorder: border(scheme.primary, 1.6),
  );
}

/// 表单分组小标题。
class MedicationSectionLabel extends StatelessWidget {
  const MedicationSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 状态徽章：tone 2 = 红（失效）、1 = 橙（要注意）、0 = 普通。
class MedicationStatusBadge extends StatelessWidget {
  const MedicationStatusBadge({
    super.key,
    required this.text,
    this.tone = 0,
  });
  final String text;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (Color bg, Color fg) = switch (tone) {
      2 => (scheme.errorContainer, scheme.onErrorContainer),
      1 => (
          isDark ? const Color(0x4D8A5300) : const Color(0xFFFFE7C2),
          isDark ? const Color(0xFFFFD08A) : const Color(0xFF7A4B00),
        ),
      _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// 紧凑信息小标签。
class MedicationMiniTag extends StatelessWidget {
  const MedicationMiniTag({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 日期字段：与输入框同款的浅灰圆角块，两个可以并排，
/// 比占两行的 ListTile 省一半高度，外观也和输入框统一。
class MedicationDateField extends StatelessWidget {
  const MedicationDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          barrierDismissible: false,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null
                        ? '未设置'
                        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null ? scheme.outline : null,
                    ),
                  ),
                ],
              ),
            ),
            if (allowClear && value != null)
              IconButton(
                tooltip: '清除',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onChanged(null),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 把 "HH:mm" 校验成分钟数；返回 null 表示格式非法。
int? parseReminderTime(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

String formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';
