import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/life_records/presentation/life_month_calendar.dart';

void main() {
  testWidgets('month calendar renders six weeks and selects adjacent dates',
      (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeMonthCalendar(
          month: DateTime(2026, 8),
          selectedDate: DateTime(2026, 8, 9),
          moodEmojis: const {20260809: '😊'},
          eventDates: const {20260809},
          cycleDates: const {20260803},
          anniversaryDates: const {20260820},
          onSelected: (value) => selected = value,
        ),
      ),
    ));

    expect(find.byType(InkWell), findsNWidgets(42));
    expect(find.text('😊'), findsOneWidget);
    expect(find.byKey(const ValueKey('life-day-20260727')), findsOneWidget);
    expect(find.byKey(const ValueKey('life-day-20260906')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('life-day-20260731')));
    expect(selected, DateTime(2026, 7, 31));
  });
}
