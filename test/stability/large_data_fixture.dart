import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';

class LargeDataFixture {
  const LargeDataFixture._();

  static Future<void> seed(AppDatabase database) async {
    final base = DateTime.utc(2026, 1, 1);
    await database.batch((batch) {
      batch.insertAll(
        database.tasks,
        List.generate(
          5000,
          (index) => TasksCompanion.insert(
            id: Value('perf-task-$index'),
            title: index % 997 == 0 ? '性能针任务 $index' : '普通任务 $index',
            dueAt: Value(
                base.add(Duration(hours: index * 3)).millisecondsSinceEpoch),
            priority: Value(index % 5),
          ),
        ),
      );
      batch.insertAll(
        database.events,
        List.generate(2000, (index) {
          final start = base.add(Duration(hours: index * 5));
          return EventsCompanion.insert(
            id: Value('perf-event-$index'),
            title: index % 701 == 0 ? '性能针日程 $index' : '普通日程 $index',
            startAt: start.millisecondsSinceEpoch,
            endAt: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          );
        }),
      );
      batch.insertAll(
        database.savedItems,
        List.generate(
          1000,
          (index) => SavedItemsCompanion.insert(
            id: Value('perf-saved-$index'),
            title: index % 499 == 0 ? '性能针资料 $index' : '普通资料 $index',
            content: Value('离线资料内容 $index'),
          ),
        ),
      );
      batch.insert(
        database.semesters,
        SemestersCompanion.insert(
          id: const Value('perf-semester'),
          name: '性能测试学期',
          startDate: 20260105,
          endDate: 20260628,
          totalWeeks: const Value(25),
        ),
      );
      batch.insertAll(
        database.courses,
        List.generate(
          20,
          (index) => CoursesCompanion.insert(
            id: Value('perf-course-$index'),
            name: '课程 $index',
            semesterId: 'perf-semester',
          ),
        ),
      );
      batch.insertAll(
        database.courseSchedules,
        List.generate(
          140,
          (index) => CourseSchedulesCompanion.insert(
            id: Value('perf-schedule-$index'),
            courseId: 'perf-course-${index % 20}',
            weekday: (index % 7) + 1,
            startMinutes: 480 + ((index % 10) * 55),
            endMinutes: 525 + ((index % 10) * 55),
            weekSet: const Value('1-25'),
          ),
        ),
      );
    });
  }
}
