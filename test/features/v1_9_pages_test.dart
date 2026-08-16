import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/features/course/presentation/academic_course_page.dart';
import 'package:lifehub/features/finance/presentation/subscriptions_page.dart';
import 'package:lifehub/features/finance/data/subscription_repository.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';
import 'package:lifehub/features/parcel/presentation/parcels_page.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/reading/presentation/reading_page.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';

void main() {
  testWidgets('academic course exposes five learning sections', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester'),
          name: '2026 秋季',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await db.into(db.courses).insert(CoursesCompanion.insert(
          id: const Value('course'),
          name: '离散数学',
          semesterId: 'semester',
        ));
    final academics = AcademicRepository(db);
    await academics.createAssignment(
      courseId: 'course',
      title: '完成离散数学作业',
      submissionMethod: '学习通提交',
    );
    await academics.createExam(
      courseId: 'course',
      title: '离散数学期末考试',
      start: DateTime(2027, 1, 10, 9),
      end: DateTime(2027, 1, 10, 11),
    );
    await academics.createMaterial(
      courseId: 'course',
      title: '离散数学复习资料',
    );
    await academics.saveGrade(const CourseGradeDraft(
      courseId: 'course',
      title: '第一次测验',
      score: 92,
    ));
    await _pump(tester, db, const AcademicCoursePage(courseId: 'course'));
    expect(find.text('离散数学'), findsOneWidget);
    for (final label in ['概览', '作业', '考试', '资料']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('完成离散数学作业'), findsOneWidget);
    expect(find.textContaining('学习通提交'), findsOneWidget);
    expect(find.text('离散数学期末考试'), findsOneWidget);
    expect(find.text('2027年1月10日 09:00-11:00'), findsOneWidget);
    expect(find.text('离散数学复习资料'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('成绩'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('成绩'), findsWidgets);
    expect(find.text('第一次测验 92.0/100.0'), findsOneWidget);
  });

  testWidgets('assignment form combines method and deadline', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester'),
          name: '2026 秋季',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await db.into(db.courses).insert(CoursesCompanion.insert(
          id: const Value('course'),
          name: '高等数学',
          semesterId: 'semester',
        ));
    await _pump(tester, db, const AcademicCoursePage(courseId: 'course'));

    await tester.tap(find.byTooltip('添加作业'));
    await tester.pumpAndSettle();
    expect(find.text('作业名称'), findsOneWidget);
    expect(find.text('提交方式（可选）'), findsOneWidget);
    expect(find.text('截止时间（可选）'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('new daily modules show useful empty states', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db, const ReadingPage());
    expect(find.text('还没有阅读记录'), findsOneWidget);
    await _pump(tester, db, const ParcelsPage());
    expect(find.text('还没有快递记录'), findsOneWidget);
    expect(find.textContaining('运输中 → 待取件 → 已取件'), findsOneWidget);
    await _pump(tester, db, const SubscriptionsPage());
    expect(find.text('还没有订阅记录'), findsOneWidget);
  });

  testWidgets('reading parcel and subscription open useful detail pages',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await ReadingRepository(db).create(
      const ReadingDraft(title: '测试读物', notes: '阅读备注'),
    );
    await ParcelRepository(db).create(
      const ParcelDraft(title: '测试快递', pickupCode: '123456'),
    );
    await SubscriptionRepository(db).create(SubscriptionDraft(
      name: '测试订阅',
      amountMinor: 990,
      cycleUnit: SubscriptionCycleUnit.month,
      nextRenewalDate: DateTime(2026, 9, 1),
    ));

    await _pump(tester, db, const ReadingPage());
    await tester.tap(find.text('测试读物'));
    await tester.pumpAndSettle();
    expect(find.text('关联关系'), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);

    await _pump(tester, db, const ParcelsPage());
    await tester.tap(find.text('测试快递'));
    await tester.pumpAndSettle();
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('关联关系'), findsOneWidget);

    await _pump(tester, db, const SubscriptionsPage());
    await tester.tap(find.text('测试订阅'));
    await tester.pumpAndSettle();
    expect(find.text('关联关系'), findsOneWidget);
  });

  testWidgets('parcel editor exposes a pickup deadline', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db, const ParcelsPage());

    await tester.tap(find.text('快递'));
    await tester.pumpAndSettle();

    expect(find.text('取件截止（可选）'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget home) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(key: ValueKey(home.runtimeType), home: home),
  ));
  await tester.pumpAndSettle();
}
