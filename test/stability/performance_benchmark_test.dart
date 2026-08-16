import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/data_hub/application/data_hub_preferences.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/search/data/search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'large_data_fixture.dart';

void main() {
  late AppDatabase database;

  setUpAll(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final watch = Stopwatch()..start();
    await LargeDataFixture.seed(database);
    watch.stop();
    // ignore: avoid_print
    print('PERF seed_8140_rows_ms=${watch.elapsedMilliseconds}');
    expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
  });

  tearDownAll(() => database.close());

  test('large local search stays responsive', () async {
    final watch = Stopwatch()..start();
    final results = await SearchRepository(database).search('性能针');
    watch.stop();
    // ignore: avoid_print
    print('PERF global_search_ms=${watch.elapsedMilliseconds}');
    expect(results, isNotEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('month event window stays responsive', () async {
    final watch = Stopwatch()..start();
    final rows = await EventRepository(database).occurrencesWindow(
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
    );
    watch.stop();
    // ignore: avoid_print
    print('PERF calendar_month_ms=${watch.elapsedMilliseconds}');
    expect(rows, isNotEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('semester timetable query stays responsive', () async {
    final watch = Stopwatch()..start();
    final rows =
        await CourseRepository(database).schedulesForSemester('perf-semester');
    watch.stop();
    // ignore: avoid_print
    print('PERF timetable_semester_ms=${watch.elapsedMilliseconds}');
    expect(rows, hasLength(140));
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('data hub layout normalization stays responsive', () async {
    SharedPreferences.setMockInitialValues({
      DataHubPreferences.orderKey:
          List.generate(32, (index) => 'module-$index').reversed.toList(),
    });
    final preferences = DataHubPreferences(
      await SharedPreferences.getInstance(),
    );
    final available = List.generate(32, (index) => 'module-$index');
    final watch = Stopwatch()..start();
    for (var index = 0; index < 1000; index++) {
      preferences.loadLayout(available);
    }
    watch.stop();
    // ignore: avoid_print
    print('PERF data_hub_1000_loads_ms=${watch.elapsedMilliseconds}');
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
