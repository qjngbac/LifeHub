import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/evening/data/evening_plan_repository.dart';

void main() {
  late AppDatabase database;
  late EveningPlanRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = EveningPlanRepository(database);
  });
  tearDown(() => database.close());

  test('loads only tomorrow facts and active course weeks', () async {
    final tomorrow = DateTime(2026, 8, 12); // Wednesday, semester week 2.
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            id: const Value('tomorrow-task'),
            title: '带材料',
            dueAt: Value(DateTime(2026, 8, 12, 18).millisecondsSinceEpoch),
          ),
        );
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            title: '后天任务',
            dueAt: Value(DateTime(2026, 8, 13, 18).millisecondsSinceEpoch),
          ),
        );
    await database.into(database.events).insert(
          EventsCompanion.insert(
            title: '看展',
            startAt: DateTime(2026, 8, 12, 10).millisecondsSinceEpoch,
            endAt: DateTime(2026, 8, 12, 11).millisecondsSinceEpoch,
          ),
        );
    await database.into(database.semesters).insert(
          SemestersCompanion.insert(
            id: const Value('semester'),
            name: '秋季',
            startDate: 20260803,
            endDate: 20261220,
          ),
        );
    await database.into(database.courses).insert(
          CoursesCompanion.insert(
            id: const Value('course'),
            name: '高等数学',
            semesterId: 'semester',
          ),
        );
    await database.into(database.courseSchedules).insert(
          CourseSchedulesCompanion.insert(
            courseId: 'course',
            weekday: DateTime.wednesday,
            startMinutes: 8 * 60,
            endMinutes: 10 * 60,
            weekSet: const Value('2,4,6'),
          ),
        );

    final plan = await repository.load(tomorrow);
    expect(plan.tasks.map((value) => value.title), ['带材料']);
    expect(plan.events.map((value) => value.title), ['看展']);
    expect(plan.courses.single.course.name, '高等数学');
  });

  test('adds, checks and keeps linked preparation items', () async {
    final date = DateTime(2026, 8, 12);
    final item = await repository.addPrepItem(
      date,
      '充电宝',
      sourceType: 'TASK',
      sourceId: 'task-1',
    );
    await repository.setPrepChecked(item.id, true);

    final plan = await repository.load(date);
    expect(plan.prepItems.single.title, '充电宝');
    expect(plan.prepItems.single.checked, isTrue);
    expect(plan.prepItems.single.sourceType, 'TASK');
  });
}
