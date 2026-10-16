import 'package:flutter/material.dart';
import 'package:lifehub/features/life_records/data/lunar_date_helper.dart';
import 'package:lunar/lunar.dart';

/// 农历日期选择器组件
class LunarDatePickerWidget extends StatelessWidget {
  const LunarDatePickerWidget({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
    required this.onChanged,
  });

  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;
  final void Function(int year, int month, int day, bool isLeapMonth) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leapMonth = LunarDateHelper.getLeapMonthInYear(year);

    // 计算当月天数（29 或 30 天）
    int maxDays = 30;
    try {
      final lunarMonthObj = LunarYear.fromYear(year).getMonth(isLeapMonth ? -month : month);
      if (lunarMonthObj != null) {
        maxDays = lunarMonthObj.getDayCount();
      }
    } catch (_) {
      maxDays = 30;
    }

    final effectiveDay = day.clamp(1, maxDays);

    // 计算对应公历日期与节日
    final solarDate = LunarDateHelper.lunarToSolar(
      year: year,
      month: month,
      day: effectiveDay,
      isLeapMonth: isLeapMonth,
    );
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[solarDate.weekday - 1];

    String festivalInfo = '';
    try {
      final l = Lunar.fromYmd(year, isLeapMonth ? -month : month, effectiveDay);
      final fests = l.getFestivals();
      if (fests.isNotEmpty) {
        festivalInfo = ' · ${fests.first}';
      }
    } catch (_) {}

    // 月份选项列表（若有闰月则动态插入）
    final List<({int m, bool isLeap, String label})> monthChoices = [];
    for (int i = 1; i <= 12; i++) {
      monthChoices.add((m: i, isLeap: false, label: LunarInfo.monthNames[i - 1]));
      if (leapMonth == i) {
        monthChoices.add((m: i, isLeap: true, label: '闰${LunarInfo.monthNames[i - 1]}'));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 年份选择（独占一行，空间充裕，干支与生肖彻底展开且不截断）
          DropdownButtonFormField<int>(
            key: ValueKey('lunar_year_$year'),
            isExpanded: true,
            initialValue: year,
            decoration: const InputDecoration(
              labelText: '农历年份',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              for (int y = 1940; y <= 2060; y++)
                DropdownMenuItem(
                  value: y,
                  child: Text(
                    '$y年 (${_getGanZhiZodiac(y)})',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (newYear) {
              if (newYear == null) return;
              final newLeapMonth =
                  LunarDateHelper.getLeapMonthInYear(newYear);
              final safeIsLeap = isLeapMonth && newLeapMonth == month;
              onChanged(newYear, month, effectiveDay, safeIsLeap);
            },
          ),
          const SizedBox(height: 10),
          // 月份与日期选择（双列平分，各占一半，无挤压）
          Row(
            children: [
              // 月份选择
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('lunar_month_${month}_$isLeapMonth'),
                  isExpanded: true,
                  initialValue: '${month}_$isLeapMonth',
                  decoration: const InputDecoration(
                    labelText: '农历月份',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: monthChoices.map((choice) {
                    return DropdownMenuItem(
                      value: '${choice.m}_${choice.isLeap}',
                      child: Text(
                        choice.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final parts = value.split('_');
                    final newMonth = int.parse(parts[0]);
                    final newIsLeap = parts[1] == 'true';
                    onChanged(year, newMonth, effectiveDay, newIsLeap);
                  },
                ),
              ),
              const SizedBox(width: 10),
              // 日期选择
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('lunar_day_${year}_${month}_$effectiveDay'),
                  isExpanded: true,
                  initialValue: effectiveDay,
                  decoration: const InputDecoration(
                    labelText: '农历日期',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    for (int d = 1; d <= maxDays; d++)
                      DropdownMenuItem(
                        value: d,
                        child: Text(
                          LunarInfo.dayNames[d - 1],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                  onChanged: (newDay) {
                    if (newDay == null) return;
                    onChanged(year, month, newDay, isLeapMonth);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 对应公历与节日提示条（允许自然折行，彻底杜绝“星期...”截断）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.sync_alt_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '对应公历：${solarDate.year}年${solarDate.month}月${solarDate.day}日 星期$weekday$festivalInfo',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _getGanZhiZodiac(int year) {
    try {
      final l = Lunar.fromYmd(year, 1, 1);
      return '${l.getYearInGanZhi()}${l.getYearShengXiao()}年';
    } catch (_) {
      return '';
    }
  }
}
