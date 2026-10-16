import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';
import 'package:lifehub/features/reading/presentation/reading_form.dart';
import 'package:lifehub/features/reading/presentation/reading_page.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidget(Widget child) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('reading form displays title hint without brackets and types in two rows', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      createWidget(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showReadingForm(context),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // Verify hint text has no brackets
    expect(find.text('如 三体、百年孤独'), findsOneWidget);
    expect(find.text('如《三体》、《百年孤独》'), findsNothing);

    // Verify reading types (5 types)
    expect(find.text('图书'), findsOneWidget);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('论文'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);

    // Verify no ChoiceChip checkmarks
    expect(find.byType(ChoiceChip), findsNothing);

    // Cancel form
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('reading page renders category grid and status chips and prevents progress overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = ReadingRepository(db);
    final book = await repo.create(const ReadingDraft(
      title: '仙逆',
      author: '耳根',
      readingType: ReadingType.novel,
      progressUnit: ReadingUnit.chapter,
      currentProgress: 100,
      totalProgress: 1888,
      status: ReadingStatus.reading,
    ));

    await tester.pumpWidget(createWidget(const ReadingPage()));
    await tester.pumpAndSettle();

    // Verify category grid
    expect(find.text('读物分类'), findsOneWidget);
    expect(find.text('1 本'), findsWidgets);

    // Verify status chips
    expect(find.text('按状态查看'), findsOneWidget);
    expect(find.text('全部 1'), findsOneWidget);
    expect(find.text('在读 1'), findsOneWidget);

    // Verify book item card
    expect(find.text('仙逆'), findsWidgets);

    // Tap modify progress icon button
    final editButtons = find.byTooltip('修改进度');
    expect(editButtons, findsWidgets);
    await tester.tap(editButtons.first);
    await tester.pumpAndSettle();

    // Verify dialog shows total progress
    expect(find.text('全书共 1888 章'), findsOneWidget);
    expect(find.text('设为已读完 (1888 章)'), findsOneWidget);

    // Enter 10000 in progress input
    final input = find.byType(TextField).last;
    await tester.enterText(input, '10000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // Verify validation intercepts 10000 with clear message instead of silent failure
    expect(find.text('输入进度 (10000) 不能超过全书总数 (1888 章)'), findsOneWidget);

    // Quick set to completed button works
    await tester.tap(find.text('设为已读完 (1888 章)'));
    await tester.pumpAndSettle();
    expect(find.text('输入进度 (10000) 不能超过全书总数 (1888 章)'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // Check database updated to 1888
    final updated = await repo.get(book.id);
    expect(updated.currentProgress, 1888);
    expect(updated.status, 'COMPLETED');
  });
}
