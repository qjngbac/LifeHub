import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/calendar/presentation/calendar_page.dart';
import 'package:lifehub/features/credentials/presentation/credentials_page.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/today/presentation/today_page.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/ui/responsive_test_harness.dart';

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase database,
  Widget page, {
  Size size = const Size(390, 844),
  double scale = 1,
  double keyboard = 0,
}) async {
  await configurePhone(
    tester,
    ResponsiveTestCase(
      'calendar',
      size: size,
      textScale: scale,
      keyboardHeight: keyboard,
    ),
  );
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: MaterialApp(theme: LifeHubTheme.light(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'calendar separates time and place and navigates days without overflow',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = EventRepository(database);
      final day = _today;
      await repository.create(
        EventDraft(
          title: '需要核对多项资料的长标题日程安排',
          start: DateTime(day.year, day.month, day.day, 9),
          end: DateTime(day.year, day.month, day.day, 10),
          location: '图书馆',
          travelMinutes: 20,
          departureReminderEnabled: true,
        ),
      );
      await repository.create(
        EventDraft(
          title: '下一天安排',
          start: DateTime(day.year, day.month, day.day + 1, 12),
          end: DateTime(day.year, day.month, day.day + 1, 13),
        ),
      );
      await _pump(
        tester,
        database,
        const CalendarPage(),
        size: const Size(320, 800),
        scale: 1.6,
      );
      expect(find.text('09:00–10:00'), findsOneWidget);
      expect(find.text('图书馆'), findsOneWidget);
      expect(find.text('建议 08:40 出发'), findsOneWidget);
      expectNoLayoutFailure(tester);
      await tester.tap(find.byTooltip('下一天'));
      await tester.pumpAndSettle();
      expect(find.text('下一天安排'), findsOneWidget);
      expect(find.text('需要核对多项资料的长标题日程安排'), findsNothing);
      await tester.tap(find.byTooltip('回到今天'));
      await tester.pumpAndSettle();
      expect(find.text('需要核对多项资料的长标题日程安排'), findsOneWidget);
    },
  );

  testWidgets('calendar opens one complete form and saves an all-day event', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(tester, database, const CalendarPage());
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('新建日程'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('请输入日程标题'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '全天安排');
    await tester.ensureVisible(find.widgetWithText(SwitchListTile, '全天日程'));
    await tester.tap(find.widgetWithText(SwitchListTile, '全天日程'));
    await tester.tap(save);
    await tester.pumpAndSettle();
    final events = await EventRepository(database).occurrencesWindow(
      _today,
      DateTime(_today.year, _today.month, _today.day + 1),
    );
    expect(events.single.event.title, '全天安排');
    expect(events.single.event.allDay, isTrue);
    expect(events.single.event.localDate, DateKeys.toLocalDateKey(_today));
    expect(find.text('00:00–23:59'), findsOneWidget);
    expect(find.text('全天'), findsNothing);
    expectNoLayoutFailure(tester);
  });

  testWidgets('event form fits small large-text phones with the keyboard', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(
      tester,
      database,
      const CalendarPage(),
      size: const Size(320, 720),
      scale: 1.6,
      keyboard: 220,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存');
    expect(save, findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(500));
    expectNoLayoutFailure(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      await EventRepository(
        database,
      ).occurrencesWindow(_today, _today.add(const Duration(days: 2))),
      isEmpty,
    );
  });

  testWidgets('date and time controls stay compact and independently editable', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(tester, database, const CalendarPage(), size: const Size(390, 844), scale: 1.6);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final date = find.byTooltip('选择开始日期');
    final time = find.byTooltip('选择开始时间');
    await tester.ensureVisible(date);
    expect((tester.getCenter(date).dy - tester.getCenter(time).dy).abs(), lessThan(10));
    expect(tester.getSize(date).height, lessThan(90));
    await tester.tap(time);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    final cancel = MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog))).cancelButtonLabel;
    await tester.tap(find.widgetWithText(TextButton, cancel));
    await tester.pumpAndSettle();
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final cancelDate = MaterialLocalizations.of(tester.element(find.byType(DatePickerDialog))).cancelButtonLabel;
    await tester.tap(find.widgetWithText(TextButton, cancelDate));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'editing preserves overnight time, custom recurrence and departure settings',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final start = DateTime(_today.year, _today.month, _today.day, 23, 0, 37);
      final end = DateTime(_today.year, _today.month, _today.day + 1, 2, 0, 19);
      final repository = EventRepository(database);
      final event = await repository.create(
        EventDraft(
          title: '夜间安排',
          start: start,
          end: end,
          repeatRule: 'FREQ=DAILY;INTERVAL=2',
          location: '图书馆',
          notes: '带上资料',
          preparationMinutes: 10,
          travelMinutes: 20,
          departureReminderEnabled: true,
        ),
      );
      await _pump(tester, database, const CalendarPage());
      await tester.tap(find.text('夜间安排'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑日程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '夜间安排更新');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      final updated = await repository.get(event.id);
      expect(updated.title, '夜间安排更新');
      expect(updated.startAt, event.startAt);
      expect(updated.endAt, event.endAt);
      expect(updated.repeatRule, event.repeatRule);
      expect(updated.location, event.location);
      expect(updated.notes, event.notes);
      expect(updated.preparationMinutes, 10);
      expect(updated.travelMinutes, 20);
      expect(updated.departureReminderEnabled, isTrue);
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets(
    'home shows all-day events with the full-day display interval',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await EventRepository(database).create(
        EventDraft(
          title: '全天会议',
          start: _today,
          end: DateTime(_today.year, _today.month, _today.day + 1),
          allDay: true,
          localDate: DateKeys.toLocalDateKey(_today),
        ),
      );
      await _pump(tester, database, const TodayPage());
      expect(find.text('全天会议'), findsOneWidget);
      expect(find.text('00:00–23:59'), findsOneWidget);
      expect(find.text('全天'), findsNothing);
      expect(find.text('00:00–00:00'), findsNothing);
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets('credential number guidance remains fully visible when focused', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(
      tester,
      database,
      const CredentialsPage(),
      size: const Size(320, 800),
      scale: 1.6,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final input = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '号码提示',
    );
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.pumpAndSettle();
    expect(find.text('勿填写完整号码'), findsOneWidget);
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'multi-day all-day editing preserves its inclusive dates and stored interval',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final day = _today;
      final repository = EventRepository(database);
      final event = await repository.create(
        EventDraft(
          title: '全天出差',
          start: day,
          end: DateTime(day.year, day.month, day.day + 3),
          allDay: true,
          localDate: DateKeys.toLocalDateKey(day),
          eventType: 'WORK',
          location: '外地',
          notes: '准备材料',
        ),
      );
      await _pump(tester, database, const CalendarPage());
      await tester.tap(find.text('全天出差'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑日程'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '全天出差更新');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      final updated = await repository.get(event.id);
      expect(updated.startAt, event.startAt);
      expect(updated.endAt, event.endAt);
      expect(updated.localDate, event.localDate);
      expect(updated.allDay, isTrue);
      expect(updated.eventType, 'WORK');
      expect(updated.location, event.location);
      expect(updated.notes, event.notes);
    },
  );

  testWidgets('invalid all-day date range stays in the form without saving', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(tester, database, const CalendarPage());
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '日期检查');
    await tester.tap(find.widgetWithText(SwitchListTile, '全天日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择结束日期'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    picker.onDateChanged(DateTime(_today.year, _today.month, _today.day - 1));
    await tester.pumpAndSettle();
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).okButtonLabel;
    await tester.tap(find.widgetWithText(TextButton, ok));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('结束日期不能早于开始日期'), findsOneWidget);
    expect(
      await EventRepository(
        database,
      ).occurrencesWindow(_today, _today.add(const Duration(days: 2))),
      isEmpty,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'optional repeat and departure settings save within the same form',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _pump(tester, database, const CalendarPage());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '带出发提醒的日程');
      await tester.ensureVisible(find.text('更多选项'));
      await tester.tap(find.text('更多选项'));
      await tester.pumpAndSettle();
      final repeat = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(repeat);
      await tester.tap(repeat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('每天').last);
      await tester.pumpAndSettle();
      final departure = find.widgetWithText(SwitchListTile, '出发提醒');
      await tester.ensureVisible(departure);
      await tester.tap(departure);
      await tester.pumpAndSettle();
      for (final entry in {'准备时间（分钟）': '7', '路程时间（分钟）': '18'}.entries) {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == entry.key,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      final preparation = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '准备时间（分钟）',
      );
      await tester.ensureVisible(preparation);
      await tester.enterText(preparation, '-1');
      await tester.ensureVisible(find.text('更多选项'));
      await tester.tap(find.text('更多选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('出发提醒时间需填写非负整数'), findsOneWidget);
      await tester.ensureVisible(find.text('更多选项'));
      await tester.tap(find.text('更多选项'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(preparation);
      await tester.enterText(preparation, '7');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      final event = (await EventRepository(database).occurrencesWindow(
        _today,
        DateTime(_today.year, _today.month, _today.day + 1),
      )).single.event;
      expect(event.repeatRule, 'FREQ=DAILY;INTERVAL=1');
      expect(event.preparationMinutes, 7);
      expect(event.travelMinutes, 18);
      expect(event.departureReminderEnabled, isTrue);
      expectNoLayoutFailure(tester);
    },
  );
}
