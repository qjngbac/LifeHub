import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/first_aid/data/first_aid_repository.dart';
import 'package:lifehub/features/first_aid/domain/first_aid_models.dart';
import 'package:lifehub/features/first_aid/presentation/first_aid_page.dart';

/// 急救知识「找得到、看得懂、信得过」的回归：
/// 1. 按紧急等级筛选；
/// 2. 搜索必须覆盖场景名 / 适用子环境 / 条目编号；
/// 3. 操作步骤按 ①②③ 拆成有序条目；
/// 4. 内容来源与审核时间必须可取。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FirstAidKnowledge knowledge;

  setUp(() async {
    knowledge = await FirstAidRepository(bundle: rootBundle).load();
  });

  test('按紧急等级筛选，且计数与全库一致', () {
    final counts = knowledge.riskCounts;
    expect(counts[FirstAidRisk.emergency], greaterThan(100));
    expect(counts[FirstAidRisk.high], greaterThan(100));
    expect(
      counts.values.reduce((a, b) => a + b),
      knowledge.items.length,
      reason: '三个等级的计数之和必须等于全库条数',
    );

    final emergency =
        FirstAidRepository.filter(knowledge, risk: FirstAidRisk.emergency);
    expect(emergency, isNotEmpty);
    expect(emergency.every((item) => item.risk == FirstAidRisk.emergency),
        isTrue);
    expect(emergency, hasLength(counts[FirstAidRisk.emergency]!));
  });

  test('搜索覆盖场景名：搜「灾害环境」能拿到该场景全部条目', () {
    final sceneItems =
        knowledge.items.where((item) => item.sceneId == 'scene_18').toList();
    expect(sceneItems, isNotEmpty);

    final hits = FirstAidRepository.filter(knowledge, query: '灾害环境');
    for (final item in sceneItems) {
      expect(hits.map((entry) => entry.id), contains(item.id));
    }
  });

  test('搜索覆盖适用子环境：搜「雷暴」这类词不再漏条目', () {
    final hits = FirstAidRepository.filter(knowledge, query: '雷暴');
    expect(hits, isNotEmpty);
    // 命中条目应当来自提到"雷暴"的场景
    expect(
      hits.every((item) {
        final scene = knowledge.sceneById(item.sceneId);
        return scene != null &&
            (scene.subEnvironments.contains('雷暴') ||
                scene.name.contains('雷暴') ||
                item.matches('雷暴'));
      }),
      isTrue,
    );
  });

  test('搜索覆盖条目编号', () {
    final target = knowledge.items.first;
    final hits = FirstAidRepository.filter(
      knowledge,
      query: '${target.number}',
    );
    expect(hits.map((item) => item.id), contains(target.id));
  });

  test('既有正文搜索能力不回退', () {
    expect(FirstAidRepository.filter(knowledge, query: '止血'), isNotEmpty);
    expect(FirstAidRepository.filter(knowledge, query: '纽扣电池'), isNotEmpty);
  });

  test('操作步骤按 ①②③ 拆成有序条目', () {
    final steps = splitCircledSteps(
      '①避开车流、火、电；②呼叫救援；③先处理无正常呼吸和大出血。',
    );
    expect(steps, hasLength(3));
    expect(steps.first, '避开车流、火、电');
    expect(steps.last, contains('先处理无正常呼吸和大出血'));
  });

  test('阿拉伯编号 1. 2. 3. 同样能拆开（数据里两种格式都有）', () {
    final steps = splitCircledSteps(
      '1. 设置警示并让施工设备停机；2. 检查反应和呼吸；3. 有大出血时直接压迫止血。',
    );
    expect(steps, hasLength(3));
    expect(steps.first, '设置警示并让施工设备停机');
    expect(steps.last, contains('直接压迫止血'));
  });

  test('正文里的数字（如 5cm）不会被误当成编号', () {
    expect(
      splitCircledSteps('按压深度约 5cm，频率 100 至 120 次每分钟。'),
      ['按压深度约 5cm，频率 100 至 120 次每分钟。'],
    );
  });

  test('单段步骤不拆行，空内容返回空列表', () {
    expect(splitCircledSteps('直接呼救并等待救援。'), ['直接呼救并等待救援。']);
    expect(splitCircledSteps('   '), isEmpty);
  });

  test('禁忌按分号拆成条目', () {
    expect(
      splitSemicolons('不冲入仍危险的现场；不先处理小擦伤而忽略呼吸。'),
      hasLength(2),
    );
    expect(splitSemicolons('只有一句禁忌'), ['只有一句禁忌']);
  });

  test('真实数据里的每条步骤都能被拆开', () async {
    final unstrippable = knowledge.items
        .where((item) => splitCircledSteps(item.steps).length < 2)
        .toList();
    expect(
      unstrippable,
      isEmpty,
      reason: '全部 261 条都应是 ①②③ 结构，出现拆不开的说明数据格式变了',
    );
  });

  test('内容来源与审核时间可取（详情页用于展示可信度）', () {
    expect(knowledge.reviewedAt, isNotEmpty);
    expect(knowledge.sources, isNotEmpty);
    expect(
      knowledge.sources.every((source) => source.title.isNotEmpty),
      isTrue,
    );
    expect(knowledge.sceneById('scene_18')?.name, '灾害环境');
    expect(knowledge.sceneById('不存在的场景'), isNull);
  });
}
