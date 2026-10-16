import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 快递模块共用的表单视觉规范。
///
/// 全局主题的 `inputDecorationTheme` 是"白色 78% 填充 + 无边框"，
/// 叠在近白的对话框底色上输入区几乎隐形；这里在模块内统一换成
/// 可辨识的浅灰底 + 淡描边（不动共享主题文件）。
InputDecoration parcelFieldDecoration(
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

class ParcelSectionLabel extends StatelessWidget {
  const ParcelSectionLabel(this.text, {super.key});
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

/// 状态徽章：tone 2 = 红（超期/退回）、1 = 橙（要处理）、0 = 普通。
class ParcelStatusBadge extends StatelessWidget {
  const ParcelStatusBadge({super.key, required this.text, this.tone = 0});
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

class ParcelMiniTag extends StatelessWidget {
  const ParcelMiniTag({super.key, required this.text, this.icon});
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

/// 取件截止：日期 + 时间一并选择，外观与输入框统一。
class ParcelDeadlineField extends StatelessWidget {
  const ParcelDeadlineField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final initial = value ?? DateTime.now().add(const Duration(days: 1));
        final date = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 730)),
          barrierDismissible: false,
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
          barrierDismissible: false,
        );
        if (time == null) return;
        onChanged(DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ));
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
                        : DateFormat('yyyy-MM-dd HH:mm').format(value!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null ? scheme.outline : null,
                    ),
                  ),
                ],
              ),
            ),
            if (value == null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              IconButton(
                tooltip: '清除',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
    );
  }
}

/// 取件截止的倒计时文案：快递超时会被退回，这是该模块最该有的预警。
///
/// 返回 null 表示不需要特别提示（已取件 / 没有截止时间 / 时间还充裕）。
({String text, int tone})? pickupDeadlineHint({
  required String status,
  required int? pickupDeadline,
  required int? arrivedAt,
  required DateTime now,
}) {
  if (status == 'COLLECTED' || status == 'RETURNED') return null;
  final deadline = pickupDeadline;
  if (deadline == null) return null;
  final end = DateTime.fromMillisecondsSinceEpoch(deadline);
  final remaining = end.difference(now).inMinutes;
  if (remaining <= 0) {
    final hours = (-remaining) ~/ 60;
    final text = hours >= 1 ? '已超时 $hours 小时' : '已超时不到 1 小时';
    return (text: text, tone: 2);
  }
  if (remaining <= 24 * 60) {
    final hours = remaining ~/ 60;
    if (hours >= 1) return (text: '剩 $hours 小时取件', tone: 1);
    final minutes = remaining < 1 ? 1 : remaining;
    return (text: '剩 $minutes 分钟取件', tone: 1);
  }
  final days = remaining ~/ (24 * 60);
  return (text: '$days 天后到期', tone: 0);
}
