import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/evening/data/evening_plan_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late EveningPlanRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = EveningPlanRepository(database);
  });
  tearDown(() => database.close());

  test('deferral advances revisions, audits changes and skips completed tasks',
      () async {
    final tasks = TaskRepository(database);
    final active = await tasks.create(TaskDraft(
      title: '顺延任务', dueAt: DateTime(2026, 10, 1, 18),
    ));
    final completed = await tasks.create(TaskDraft(
      title: '已完成任务', dueAt: DateTime(2026, 10, 1, 18),
    ));
    await tasks.setStatus(completed.id, TaskStatus.done);
    final completedBefore = await tasks.get(completed.id);
    await repository.deferTasks(
      [active.id, completed.id], DateTime(2026, 10, 2),
    );
    final after = await tasks.get(active.id);
    expect(after.dueAt, DateTime(2026, 10, 2, 23, 59).millisecondsSinceEpoch);
    expect(after.version, active.version + 1);
    final logs = await (database.select(database.changeLogs)
          ..where((row) => row.entityId.equals(active.id))).get();
    expect(logs.where((row) => row.operation == 'UPDATE'), hasLength(1));
    final completedAfter = await tasks.get(completed.id);
    expect(completedAfter.dueAt, completedBefore.dueAt);
    expect(completedAfter.version, completedBefore.version);
  });

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

  test('tomorrow expands earlier repeating events with occurrence times', () async {
    final events = EventRepository(database);
    final event = await events.create(EventDraft(
      title: '重复出门', start: DateTime(2026, 8, 10, 9),
      end: DateTime(2026, 8, 10, 10), repeatRule: 'FREQ=DAILY;INTERVAL=1',
      preparationMinutes: 15, travelMinutes: 30, departureReminderEnabled: true,
    ));
    final archived = await events.create(EventDraft(
      title: '归档日程', start: DateTime(2026, 8, 10, 11),
      end: DateTime(2026, 8, 10, 12), repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await events.archive(archived.id);
    final plan = await repository.load(DateTime(2026, 8, 12));
    expect(plan.events.single.id, event.id);
    expect(plan.events.single.startAt, DateTime(2026, 8, 12, 9).millisecondsSinceEpoch);
    expect(plan.events.single.endAt, DateTime(2026, 8, 12, 10).millisecondsSinceEpoch);
    expect(plan.events.single.travelMinutes, 30);
  });

  test('tomorrow lists only TODO and IN_PROGRESS tasks', () async {
    final tasks = TaskRepository(database);
    for (final status in [TaskStatus.todo, TaskStatus.inProgress,
      TaskStatus.done, TaskStatus.canceled, TaskStatus.archived]) {
      final task = await tasks.create(TaskDraft(
        title: status, dueAt: DateTime(2026, 8, 12, 18),
      ));
      if (status != TaskStatus.todo) await tasks.setStatus(task.id, status);
    }
    final plan = await repository.load(DateTime(2026, 8, 12));
    expect(plan.tasks.map((row) => row.title),
        unorderedEquals([TaskStatus.todo, TaskStatus.inProgress]));
  });
}
