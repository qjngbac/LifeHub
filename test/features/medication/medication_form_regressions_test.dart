import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/emergency_card_page.dart';
import 'package:lifehub/features/medication/presentation/medication_page.dart';

/// 用药提醒与急救卡的回归：
/// 1. 表单必填/格式校验必须有反馈，而不是静默 return 或直接抛异常；
/// 2. 打卡按钮要能反映"今天已完成"；
/// 3. 急救卡只展示填过的字段，未填项汇总成一行（不再是一墙"未填写"卡片）。
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> pumpMedication(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: MedicationPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpEmergency(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: EmergencyCardPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('提醒计划表单校验', () {
    testWidgets('名称留空时给出提示且不关闭弹窗', (tester) async {
      await pumpMedication(tester);
      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();
      expect(find.text('添加提醒计划'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('请输入名称'), findsOneWidget);
      expect(
        find.text('添加提醒计划'),
        findsOneWidget,
        reason: '校验失败时不应该关闭弹窗',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('提醒时间格式错误时给出提示，而不是抛出异常', (tester) async {
      await pumpMedication(tester);
      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '消炎药');
      // 第 3 个输入框是提醒时间（名称 / 说明 / 时间 / 备注）
      await tester.enterText(find.byType(TextFormField).at(2), '8点');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('格式不对'), findsOneWidget);
      expect(
        find.text('添加提醒计划'),
        findsOneWidget,
        reason: '非法时间以前会直接抛 ArgumentError，现在必须留在表单里提示',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('时间留空也会被拦下', (tester) async {
      await pumpMedication(tester);
      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '消炎药');
      await tester.enterText(find.byType(TextFormField).at(2), '');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('至少填写一个提醒时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('今日打卡状态', () {
    testWidgets('打卡后按钮变成已完成并显示进度', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final repository = MedicationRepository(database);
      await repository.createPlan(
        MedicationPlanDraft(
          name: '消炎药',
          startDate: today,
          reminderTimes: const ['10:00'],
        ),
      );

      await pumpMedication(tester);
      expect(find.text('10:00 打卡'), findsOneWidget);
      expect(find.text('今日 0/1'), findsOneWidget);

      await tester.tap(find.text('10:00 打卡'));
      await tester.pumpAndSettle();

      expect(find.text('10:00 已打卡'), findsOneWidget);
      expect(find.text('10:00 打卡'), findsNothing);
      expect(find.text('今日 1/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('仓库层校验与打卡查询', () {
    test('非法提醒时间仍然会被仓库拒绝（UI 必须先拦）', () async {
      await expectLater(
        MedicationRepository(database).createPlan(
          MedicationPlanDraft(
            name: '消炎药',
            startDate: DateTime(2026, 8, 1),
            reminderTimes: const ['8点'],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('紧急联系人以「姓名 · 电话」单字段存取，并兼容老数据', () {
      expect(
        MedicationRepository.joinEmergencyContact('妈妈', '13800000000'),
        '妈妈 · 13800000000',
      );
      expect(MedicationRepository.joinEmergencyContact('妈妈', '  '), '妈妈');
      expect(MedicationRepository.joinEmergencyContact('', '119'), '119');
      expect(
        MedicationRepository.joinEmergencyContact('', ''),
        '',
      );

      final parsed =
          MedicationRepository.splitEmergencyContact('妈妈 · 13800000000');
      expect(parsed.name, '妈妈');
      expect(parsed.phone, '13800000000');

      // 老数据没有分隔符：整体当姓名，用户补一次电话即可
      final legacy = MedicationRepository.splitEmergencyContact('妈妈 13800000000');
      expect(legacy.name, '妈妈 13800000000');
      expect(legacy.phone, '');
      expect(MedicationRepository.splitEmergencyContact(null).name, '');
    });

    test('checkedInMinutesByPlan 一次取回当天各计划的打卡时间点', () async {
      final repository = MedicationRepository(database);
      final today = DateTime(2026, 8, 12);
      final first = await repository.createPlan(
        MedicationPlanDraft(
          name: 'A',
          startDate: DateTime(2026, 8, 1),
          reminderTimes: const ['08:00'],
        ),
      );
      final second = await repository.createPlan(
        MedicationPlanDraft(
          name: 'B',
          startDate: DateTime(2026, 8, 1),
          reminderTimes: const ['09:00'],
        ),
      );
      await repository.checkIn(first.id, today, 480);
      await repository.checkIn(first.id, today, 1230);
      await repository.checkIn(second.id, today, 540);

      final map = await repository.checkedInMinutesByPlan(today);
      expect(map[first.id], unorderedEquals(<int>[480, 1230]));
      expect(map[second.id], unorderedEquals(<int>[540]));
      expect(
        await repository.checkedInMinutesByPlan(DateTime(2026, 8, 13)),
        isEmpty,
      );
    });
  });

  group('急救卡展示', () {
    testWidgets('未填写的字段汇总成一行，不再是一墙“未填写”卡片', (tester) async {
      await MedicationRepository(database)
          .saveEmergencyCard(const EmergencyCardDraft(bloodType: 'O 型'));
      await pumpEmergency(tester);

      expect(find.text('O 型'), findsOneWidget);
      expect(
        find.text('未填写'),
        findsNothing,
        reason: '旧实现每个空字段都渲染一张卡片 + 一句"未填写"',
      );
      expect(find.textContaining('未填写：'), findsOneWidget);
      expect(find.text('还没有填写过敏、既往情况或正在使用的药物'), findsOneWidget);
      expect(find.text('建议填写至少一位联系人及其电话'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('填过的字段正常展示，并从“未填写”里消失', (tester) async {
      await MedicationRepository(database).saveEmergencyCard(
        const EmergencyCardDraft(
          name: '本人',
          bloodType: 'O 型',
          allergies: '青霉素',
        ),
      );
      await pumpEmergency(tester);

      expect(find.text('本人'), findsOneWidget);
      expect(
        find.textContaining('过敏信息'),
        findsOneWidget,
        reason: '填了过敏信息后就只剩区块标题这一处，不该再出现在“未填写”汇总里',
      );
      expect(
        find.textContaining('未填写：'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('完全没填时展示引导而不是空卡片', (tester) async {
      await pumpEmergency(tester);
      expect(find.text('还没有急救卡'), findsOneWidget);
      expect(find.text('填写急救卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('紧急联系人拆成身份与电话两栏，存回单字段并各自回填', (tester) async {
      await pumpEmergency(tester);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      TextField byLabel(String label) => tester.widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField && widget.decoration?.labelText == label,
            ),
          );

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '身份（姓名）',
        ),
        '妈妈',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.decoration?.labelText == '电话',
        ),
        '13800000000',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        (await MedicationRepository(database).emergencyCard())
            ?.emergencyContacts,
        '妈妈 · 13800000000',
      );

      // 再次打开时两栏各自回填
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(byLabel('身份（姓名）').controller?.text, '妈妈');
      expect(byLabel('电话').controller?.text, '13800000000');
      expect(tester.takeException(), isNull);
    });

    testWidgets('多行字段默认只占一行，内容变多才长高', (tester) async {
      await pumpEmergency(tester);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      for (final label in ['过敏信息', '既往情况', '备注']) {
        final field = tester.widget<TextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          ),
        );
        expect(field.minLines, 1, reason: '$label 默认应只有一行');
        expect(field.maxLines, isNull, reason: '$label 内容变多时应自动长高');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('提醒计划表单的字段高度', () {
    testWidgets('说明与备注默认为一行，内容多时才多行', (tester) async {
      await pumpMedication(tester);
      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();

      final growable = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((field) => field.maxLines == null)
          .toList();
      expect(
        growable,
        hasLength(2),
        reason: '只有「你的说明」和「备注」需要按内容自动增高，其余字段保持一行',
      );
      expect(growable.every((field) => field.minLines == 1), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
