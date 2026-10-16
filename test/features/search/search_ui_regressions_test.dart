import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/entertainment/presentation/entertainment_page.dart';
import 'package:lifehub/features/first_aid/presentation/first_aid_page.dart';
import 'package:lifehub/features/search/presentation/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  for (final page in [const FirstAidPage(), const EntertainmentPage()]) {
    testWidgets(
      'search audit ${page.runtimeType} keeps its input while searching',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(MaterialApp(home: page));
        await _pumpLoading(tester);
        await tester.enterText(_searchField(), '测试');
        await _pumpLoading(tester);
        expect(find.byType(SearchBar), findsOneWidget);
        await tester.enterText(_searchField(), '改词');
        await _pumpLoading(tester);
        expect(find.text('改词'), findsOneWidget);
        await tester.enterText(_searchField(), '');
        await _pumpLoading(tester);
        expect(find.byType(SearchBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'search audit global input debounces and parent rebuild reuses its future',
    (tester) async {
      final recorder = _SearchReads();
      final database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(recorder),
      );
      addTearDown(database.close);
      await database
          .into(database.tasks)
          .insert(TasksCompanion.insert(title: 'abc result'));
      recorder.reads.clear();
      await tester.pumpWidget(_app(database));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      for (final text in ['a', 'ab', 'abc']) {
        await tester.enterText(_searchField(), text);
        await tester.pump(const Duration(milliseconds: 70));
      }
      expect(recorder.taskReads, isEmpty);
      await tester.pump(const Duration(milliseconds: 350));
      await _pumpIOUntil(tester, find.text('abc result'));
      expect(recorder.taskReads, hasLength(1));
      expect(recorder.taskReads.single.args, contains('%abc%'));
      expect(find.text('abc result'), findsOneWidget);
      final count = recorder.reads.length;
      await tester.pumpWidget(_app(database, dark: true));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      expect(recorder.reads, hasLength(count));
      await tester.enterText(_searchField(), '');
      await tester.pump(const Duration(milliseconds: 350));
      expect(recorder.reads, hasLength(count));
    },
  );

  testWidgets(
    'search audit obsolete global query stops before remaining SQL and cannot replace latest',
    (tester) async {
      final gate = Completer<void>();
      final recorder = _SearchReads(oldGate: gate);
      final database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(recorder),
      );
      addTearDown(database.close);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await database
          .into(database.tasks)
          .insert(TasksCompanion.insert(title: 'old result'));
      await database
          .into(database.tasks)
          .insert(TasksCompanion.insert(title: 'new result'));
      recorder.reads.clear();
      await tester.pumpWidget(_app(database));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      await tester.enterText(_searchField(), 'old');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(
        recorder.taskReads.where((row) => row.args.contains('%old%')),
        hasLength(1),
      );
      await tester.enterText(_searchField(), 'new');
      gate.complete();
      await tester.pump();
      expect(find.text('old result'), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      await _pumpIOUntil(tester, find.text('new result'));
      expect(find.text('new result'), findsOneWidget);
      expect(find.text('old result'), findsNothing);
      expect(
        recorder.reads.where((row) => row.args.contains('%old%')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('search audit cached results refresh after data changes', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task = await database.into(database.tasks).insertReturning(
        TasksCompanion.insert(title: 'alpha original'));
    await tester.pumpWidget(_app(database));
    await tester.enterText(_searchField(), 'alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await _pumpIOUntil(tester, find.text('alpha original'));
    await (database.update(database.tasks)..where((row) => row.id.equals(task.id)))
        .write(const TasksCompanion(title: Value('alpha updated')));
    ProviderScope.containerOf(tester.element(find.byType(SearchPage)))
        .read(refreshProvider.notifier).state++;
    await _pumpIOUntil(tester, find.text('alpha updated'));
    expect(find.text('alpha original'), findsNothing);
  });
}

Future<void> _pumpIOUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget, reason: tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).join(' | '));
}

Finder _searchField() => find.descendant(
  of: find.byType(SearchBar),
  matching: find.byType(TextField),
);

Widget _app(AppDatabase database, {bool dark = false}) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(database)],
  child: MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: const SearchPage(),
  ),
);

class _SearchReads extends QueryInterceptor {
  _SearchReads({this.oldGate});
  final Completer<void>? oldGate;
  final reads = <({String sql, List<Object?> args})>[];
  Iterable<({String sql, List<Object?> args})> get taskReads =>
      reads.where((row) => row.sql.contains('FROM "tasks"'));
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    reads.add((sql: statement, args: List.of(args)));
    if (statement.contains('FROM "tasks"') &&
        args.contains('%old%') &&
        oldGate != null) {
      await oldGate!.future;
    }
    return executor.runSelect(statement, args);
  }
}

Future<void> _pumpLoading(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
}
