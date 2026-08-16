import 'package:flutter/material.dart';

class LifeMonthCalendar extends StatelessWidget {
  const LifeMonthCalendar({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.onSelected,
    this.moodEmojis = const {},
    this.moodColors = const {},
    this.eventDates = const {},
    this.cycleDates = const {},
    this.anniversaryDates = const {},
  });

  final DateTime month;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  final Map<int, String> moodEmojis;
  final Map<int, Color> moodColors;
  final Set<int> eventDates;
  final Set<int> cycleDates;
  final Set<int> anniversaryDates;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = DateTime.now();
    return Column(children: [
      Row(
        children: const ['一', '二', '三', '四', '五', '六', '日']
            .map((value) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
      LayoutBuilder(builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: cellWidth / 66,
          ),
          itemBuilder: (context, index) {
            final date = gridStart.add(Duration(days: index));
            final key = _key(date);
            final inMonth =
                date.month == month.month && date.year == month.year;
            final selected = _sameDay(date, selectedDate);
            final isToday = _sameDay(date, today);
            final emoji = moodEmojis[key];
            final moodColor = moodColors[key];
            return Semantics(
              button: true,
              selected: selected,
              label: '${date.year}年${date.month}月${date.day}日',
              child: InkWell(
                key: ValueKey('life-day-$key'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : isToday
                            ? Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: .55)
                            : moodColor?.withValues(alpha: .42) ??
                                Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: selected || isToday
                        ? Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.secondary,
                          )
                        : null,
                  ),
                  child: Column(children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 12,
                        color: inMonth
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: .45),
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 1),
                    if (emoji != null)
                      Text(emoji, style: const TextStyle(fontSize: 17)),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (cycleDates.contains(key))
                        const _Marker(color: Color(0xFFE883A7)),
                      if (eventDates.contains(key))
                        const _Marker(color: Color(0xFF7D9AD6)),
                      if (anniversaryDates.contains(key))
                        const _Marker(color: Color(0xFFE7B34D)),
                    ]),
                    const SizedBox(height: 2),
                  ]),
                ),
              ),
            );
          },
        );
      }),
    ]);
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

int _key(DateTime value) => value.year * 10000 + value.month * 100 + value.day;

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
