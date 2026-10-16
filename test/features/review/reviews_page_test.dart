import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/review/data/review_repository.dart';
import 'package:lifehub/features/review/presentation/reviews_page.dart';

void main() {
  testWidgets('reopening and saving the same review preserves its reflections',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await initializeDateFormatting('zh_CN');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ReviewRepository(database);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 7));
    await repository.save(ReviewDraft(periodType: 'WEEK', start: start,
      end: end, summary: await repository.summary(start, end),
      wins: '已完成计划', blockers: '保留反思', nextPriorities: '下一步',
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: ReviewsPage()),
    ));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((field) => field.controller!.text),
        ['已完成计划', '保留反思', '下一步']);
    await tester.tap(find.byTooltip('上一期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一期'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存复盘'));
    await tester.tap(find.text('保存复盘'));
    await tester.pumpAndSettle();
    final saved = (await repository.list()).single;
    expect(saved.wins, '已完成计划');
    expect(saved.blockers, '保留反思');
    expect(saved.nextPriorities, '下一步');
    final winsField = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.decoration?.labelText == '做得好的事');
    await tester.ensureVisible(winsField);
    await tester.enterText(winsField, '补充收获');
    await tester.ensureVisible(find.text('保存复盘'));
    await tester.tap(find.text('保存复盘'));
    await tester.pumpAndSettle();
    final edited = (await repository.list()).single;
    expect(edited.wins, '补充收获');
    expect(edited.blockers, '保留反思');
    expect(edited.nextPriorities, '下一步');
  });
}
