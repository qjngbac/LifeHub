import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/course/domain/course_projection.dart';

void main() {
  test('course schedule projects valid weeks and honors excluded dates', () {
    final events = CourseProjection.eventsForWindow(
      course: const CourseSpec(
        id: 'course-1',
        name: '高等数学',
        room: 'A101',
      ),
      semester: SemesterSpec(
        id: 'semester-1',
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 12, 27),
        totalWeeks: 16,
      ),
      schedule: const CourseScheduleSpec(
        id: 'schedule-1',
        weekday: DateTime.monday,
        startMinutes: 8 * 60,
        endMinutes: 9 * 60 + 40,
        weekSet: '1-2',
        excludedDateKeys: {20260914},
      ),
      windowStart: DateTime(2026, 9, 7),
      windowEnd: DateTime(2026, 9, 21),
    );

    expect(events, hasLength(1));
    expect(events.single.stableId, 'schedule-1:20260907');
    expect(events.single.start, DateTime(2026, 9, 7, 8));
    expect(events.single.end, DateTime(2026, 9, 7, 9, 40));
    expect(events.single.title, '高等数学');
  });
}
