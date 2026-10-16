import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/lifecycle_guide/application/medication_food_interaction_service.dart';
import 'package:lifehub/features/lifecycle_guide/data/lifecycle_repository.dart';
import 'package:lifehub/features/lifecycle_guide/domain/family_profile_model.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/lifecycle_guide_page.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/food_guide_view.dart';
import 'package:lifehub/features/lifecycle_guide/application/family_checkup_service.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/food_nutrition_comparison_sheet.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/safety_checklist_export_sheet.dart';

import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_stage_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LifecycleCatalog testCatalog;
  late String rawCatalog;
  late LifecycleRepository testRepo;

  setUpAll(() {
    final file =
        File('assets/content/lifecycle_guide/catalog.json');
    rawCatalog = file.readAsStringSync();
    testCatalog =
        LifecycleCatalog.fromJson(jsonDecode(rawCatalog) as Map<String, dynamic>);
    testRepo = LifecycleRepository(bundle: _TestAssetBundle(rawCatalog));
  });

  group('LifecycleCatalog Data & Search Tests', () {
    test('catalog contains all parsed sections and non-empty items', () {
      expect(testCatalog.stages.length, 11);
      for (final s in testCatalog.stages) {
        expect(s.subsections.isNotEmpty, true, reason: '${s.codeLabel} has empty subsections');
        for (final sub in s.subsections) {
          final hasContent = sub.bullets.isNotEmpty || sub.tables.isNotEmpty;
          expect(hasContent, true, reason: '${s.codeLabel} subsection ${sub.title} has no content');
        }
      }
      expect(testCatalog.fruits.length, 56);
      for (final f in testCatalog.fruits) {
        expect(f.calories.contains('kcal / 100g (可食部)'), true, reason: '${f.name} missing standard calories');
        expect(f.specialComponent.isNotEmpty && f.specialComponent != '-' && f.specialComponent != '—', true, reason: '${f.name} invalid specialComponent');
        expect(f.precautions.isNotEmpty && f.precautions != '-' && f.precautions != '—', true, reason: '${f.name} invalid precautions');
      }
      expect(testCatalog.vegetables.length, 50);
      for (final v in testCatalog.vegetables) {
        expect(v.calories.contains('kcal / 100g (可食部)'), true, reason: '${v.name} missing standard calories');
        expect(v.nutrition.isNotEmpty && v.nutrition != '-' && v.nutrition != '—', true, reason: '${v.name} invalid nutrition');
        expect(v.specialPhyto.isNotEmpty && v.specialPhyto != '-' && v.specialPhyto != '—', true, reason: '${v.name} invalid specialPhyto');
      }
      expect(testCatalog.seasonCalendar.length, 12);
      expect(testCatalog.envTopics.length, greaterThanOrEqualTo(20));
      expect(testCatalog.drugInteractions.length, greaterThanOrEqualTo(10));
      expect(testCatalog.rumors.length, greaterThanOrEqualTo(20));
      expect(testCatalog.replacementSchedule.length, greaterThanOrEqualTo(7));
      expect(testCatalog.checkupSchedule.length, greaterThanOrEqualTo(15));
      expect(testCatalog.commonPitfalls.length, greaterThanOrEqualTo(10));
    });

    test('search for 西柚 hits drug interaction and fruit item', () {
      final results = testCatalog.search('西柚');
      expect(results.isNotEmpty, true);
      expect(
          results.any((r) => r.sourceBadge.contains('水果图鉴')), true);
      expect(
          results.any((r) => r.sourceBadge.contains('药物禁忌')), true);
    });

    test('search for 甲醛 hits indoor air topics', () {
      final results = testCatalog.search('甲醛');
      expect(results.isNotEmpty, true);
      expect(results.any((r) => r.title.contains('室内空气') || r.details.contains('甲醛')), true);
    });

    test('search for A类 hits baby clothing standard', () {
      final results = testCatalog.search('A类');
      expect(results.isNotEmpty, true);
    });

    test('search for 菠菜 hits spinach with oxalate warning', () {
      final results = testCatalog.search('菠菜');
      expect(results.isNotEmpty, true);
      final spinach = results.firstWhere((r) => r.title == '菠菜');
      expect(spinach.details.contains('草酸'), true);
    });

    test('search with empty query returns empty list', () {
      expect(testCatalog.search(''), isEmpty);
      expect(testCatalog.search('   '), isEmpty);
    });
  });

  group('LifecycleGuidePage Widget Tests', () {
    testWidgets('renders search bar, hot keywords, tabs and views',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleGuidePage(repository: testRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and search input
      expect(find.text('生命选品'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify hot search chips
      expect(find.text('西柚'), findsOneWidget);
      expect(find.text('甲醛'), findsOneWidget);

      // Verify 4 tabs
      expect(find.text('人生阶段 (11)'), findsOneWidget);
      expect(find.textContaining('食物与水果'), findsOneWidget);
      expect(find.textContaining('日用环境'), findsOneWidget);
      expect(find.textContaining('避坑与图谱'), findsOneWidget);

      // Tap on Tab 2 (食物与水果)
      await tester.tap(find.textContaining('食物与水果'));
      await tester.pumpAndSettle();
      expect(find.textContaining('应季月历'), findsOneWidget);

      // Tap on Tab 3 (日用环境)
      await tester.tap(find.textContaining('日用环境'));
      await tester.pumpAndSettle();
      expect(find.text('物品更换周期'), findsOneWidget);

      // Tap on Tab 4 (避坑与图谱)
      await tester.tap(find.textContaining('避坑与图谱'));
      await tester.pumpAndSettle();
      expect(find.textContaining('药物相互作用'), findsOneWidget);

      // Test search
      await tester.enterText(find.byType(TextField), '西柚');
      await tester.pumpAndSettle();

      expect(find.textContaining('西柚'), findsWidgets);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Should be back to tabs
      expect(find.text('人生阶段 (11)'), findsOneWidget);
    });

    testWidgets('clicking hot keyword chip initiates search immediately',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleGuidePage(repository: testRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Click hot chip 甲醛
      await tester.tap(find.text('甲醛'));
      await tester.pumpAndSettle();

      expect(find.textContaining('室内空气'), findsWidgets);
    });
  });

  group('FamilyProfile Tests', () {
    test('default profiles are valid and encode/decode cleanly', () {
      final list = FamilyMemberProfile.defaultProfiles;
      expect(list.length, 3);
      expect(list[0].name, '本人');
      expect(list[1].name, '宝宝');
      expect(list[2].name, '父母');

      final encoded = FamilyMemberProfile.encodeList(list);
      final decoded = FamilyMemberProfile.decodeList(encoded);
      expect(decoded.length, 3);
      expect(decoded[0].name, '本人');
      expect(decoded[1].name, '宝宝');
      expect(decoded[2].name, '父母');
    });

    testWidgets('LifecycleStageView family member switcher works', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LifecycleStageView(stages: testCatalog.stages),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check family switcher header
      expect(find.text('家庭成员画像'), findsOneWidget);
      expect(find.text('一键直达'), findsOneWidget);
      expect(find.text('本人'), findsOneWidget);
      expect(find.text('宝宝'), findsOneWidget);
      expect(find.text('父母'), findsOneWidget);

      // Tap on 宝宝 (Index 0, 阶段 1)
      await tester.tap(find.text('宝宝'));
      await tester.pumpAndSettle();
      expect(find.textContaining('宝宝'), findsWidgets);
      expect(find.textContaining('已定位至家庭成员：宝宝'), findsOneWidget);

      // Tap on 父母 (Index 7, 阶段 8)
      await tester.tap(find.text('父母'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已定位至家庭成员：父母'), findsOneWidget);

      // Tap on 添加成员
      await tester.tap(find.text('添加成员'));
      await tester.pumpAndSettle();
      expect(find.text('添加家庭成员画像'), findsOneWidget);
      expect(find.text('成员称呼'), findsOneWidget);

      // Enter name
      await tester.enterText(find.widgetWithText(TextField, '如：妈妈、妻子、二宝、外公'), '爱人');
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('爱人'), findsOneWidget);
    });
  });

  group('Medication Food Interaction Tests', () {
    test('detects statin and grapefruit collision', () {
      const service = MedicationFoodInteractionService(
        activeMedicationNames: ['阿托伐他汀钙片'],
      );
      final alert = service.checkFoodAlert('西柚', ['柑橘类', '高钾']);
      expect(alert, isNotNull);
      expect(alert!.drugCategory.contains('他汀'), true);
      expect(alert.isDanger, true);

      final safeAlert = service.checkFoodAlert('苹果', ['温带水果']);
      expect(safeAlert, isNull);
    });

    test('detects warfarin and deep green leafy vegetables collision', () {
      const service = MedicationFoodInteractionService(
        activeMedicationNames: ['华法林钠片'],
      );
      final alert = service.checkFoodAlert('菠菜', ['深绿色蔬菜', '维k']);
      expect(alert, isNotNull);
      expect(alert!.drugCategory.contains('华法林'), true);
    });

    test('detects ACEI/ARB antihypertensive and high potassium food', () {
      const service = MedicationFoodInteractionService(
        activeMedicationNames: ['氯沙坦钾片'],
      );
      final alert = service.checkFoodAlert('香蕉', ['热带水果', '高钾']);
      expect(alert, isNotNull);
      expect(alert!.drugCategory.contains('降压'), true);
    });

    testWidgets('FoodGuideView displays in-season highlight strip and medication alert', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const interactionService = MedicationFoodInteractionService(
        activeMedicationNames: ['阿托伐他汀钙片'],
      );

      final grapefruit = testCatalog.fruits.firstWhere(
        (f) => f.name.contains('西柚') || f.name.contains('葡萄柚'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoodGuideView(
              fruits: [grapefruit],
              vegetables: testCatalog.vegetables,
              seasonCalendar: testCatalog.seasonCalendar,
              topics: testCatalog.foodTopics,
              interactionService: interactionService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check In-Season Highlight Banner
      expect(find.textContaining('最值吃'), findsOneWidget);

      // Check Medication Alert on Grapefruit card
      expect(find.textContaining('您正在服用「阿托伐他汀钙片」'), findsOneWidget);
    });
  });

  group('FamilyCheckupService Tests', () {
    test('recommends checkups appropriately for different life stages', () {
      const service = FamilyCheckupService();
      final seniorCheckups = service.getRecommendedCheckups(
        stageIndex: 7,
        memberName: '父母',
        roleLabel: '老年',
        allCheckups: testCatalog.checkupSchedule,
      );
      expect(seniorCheckups.any((c) => c.item.contains('骨密度')), true);
      expect(seniorCheckups.any((c) => c.item.contains('视力') || c.item.contains('眼底')), true);

      final femaleCheckups = service.getRecommendedCheckups(
        stageIndex: 4,
        memberName: '妈妈',
        roleLabel: '育龄女性',
        allCheckups: testCatalog.checkupSchedule,
      );
      expect(femaleCheckups.any((c) => c.item.contains('乳腺') || c.item.contains('宫颈')), true);
    });
  });

  group('FoodNutritionComparisonSheet Tests', () {
    test('evaluates nutrition metrics correctly', () {
      final watermelon = FoodNutritionProfile.defaults.firstWhere((p) => p.name == '西瓜');
      final apple = FoodNutritionProfile.defaults.firstWhere((p) => p.name == '苹果');

      expect(watermelon.calories < apple.calories, true);
      expect(watermelon.gi > apple.gi, true);
      expect(apple.dietaryFiber > watermelon.dietaryFiber, true);
    });

    testWidgets('renders dual-column comparison sheet and radar chart', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apple = FoodNutritionProfile.defaults.firstWhere((p) => p.name == '苹果');
      final watermelon = FoodNutritionProfile.defaults.firstWhere((p) => p.name == '西瓜');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoodNutritionComparisonSheet(
              initialA: apple,
              initialB: watermelon,
              fruits: testCatalog.fruits,
              vegetables: testCatalog.vegetables,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('果蔬营养双栏对比与雷达'), findsOneWidget);
      expect(find.text('蔬果 A'), findsOneWidget);
      expect(find.text('蔬果 B'), findsOneWidget);
      expect(find.textContaining('热量 (kcal / 100g)'), findsOneWidget);
      expect(find.textContaining('血糖生成指数 (GI)'), findsOneWidget);
      expect(find.textContaining('膳食纤维'), findsOneWidget);
      expect(find.textContaining('选购与食用建议'), findsOneWidget);
    });
  });

  group('SafetyChecklistExportSheet Tests', () {
    testWidgets('renders safety redlines checklist and export actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final stage =
          testCatalog.stages.firstWhere((s) => s.redlines.isNotEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafetyChecklistExportSheet(
              stage: stage,
              memberName: '长辈',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('选品避坑安全清单导出'), findsOneWidget);
      expect(find.text('复制微信文本'), findsOneWidget);
      expect(find.text('生成长图卡片'), findsOneWidget);
      expect(find.textContaining('专属成员：长辈'), findsOneWidget);
      expect(find.textContaining('核心安全红线'), findsOneWidget);
    });
  });
}

class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle(this.content);
  final String content;

  @override
  Future<String> loadString(String key, {bool cache = true}) async => content;

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(content);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
