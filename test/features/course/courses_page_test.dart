import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/course/presentation/courses_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

void main() {
  testWidgets('mobile timetable shows seven days, periods and course cells',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = CourseRepository(database);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));
    final semester = await repository.createSemester(SemesterDraft(
      name: '测试学期',
      start: start,
      end: start.add(const Duration(days: 16 * 7 - 1)),
      totalWeeks: 16,
    ));
    await repository.savePeriods(semester.id, const [
      CoursePeriod(startMinutes: 480, endMinutes: 530),
      CoursePeriod(startMinutes: 540, endMinutes: 590),
    ]);
    final course = await repository.createCourse(
      CourseDraft(
        name: '高等数学',
        semesterId: semester.id,
        teacher: '王老师',
        room: 'A101',
      ),
    );
    await repository.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: DateTime.monday,
      startMinutes: 480,
      endMinutes: 590,
      weekSet: '1-16',
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: CoursesPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('周六'), findsOneWidget);
    expect(find.textContaining('周日'), findsOneWidget);
    expect(find.textContaining('第1节'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('王老师'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.add),
      findsNWidgets(12),
      reason: '跨两节的课程色块下方不应继续构建两个加号。',
    );
    final courseMaterials = tester.widgetList<Material>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.borderRadius == BorderRadius.circular(8) &&
            widget.color != null,
      ),
    );
    expect(courseMaterials, hasLength(1));
    expect(courseMaterials.single.color!.a, 1.0);
    expect(find.byKey(ValueKey('course-block-${course.id}')), findsOneWidget);

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardSafeFormDialog), findsOneWidget);
    final actionCenters = <double>[
      tester.getCenter(find.text('删除课程')).dy,
      tester.getCenter(find.text('取消').last).dy,
      tester.getCenter(find.text('保存')).dy,
    ];
    expect(actionCenters.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('semester settings use aligned fields and named time pickers',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: CoursesPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程表设置'));
    await tester.pumpAndSettle();

    expect(find.byType(KeyboardSafeFormDialog), findsOneWidget);
    for (final label in ['学期名称', '学期开始日期', '学期总周数']) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
        findsOneWidget,
      );
    }
    final weeksField = tester.widget<TextField>(find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '学期总周数',
    ));
    expect(weeksField.decoration?.hintText, '例如 16、18 或 20 周');
    expect(weeksField.decoration?.helperText, isNull);
    expect(weeksField.controller?.text, isEmpty);

    await tester.tap(find.text('第 1 节'));
    await tester.pumpAndSettle();
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('选择时间'), findsNothing);
  });
}
