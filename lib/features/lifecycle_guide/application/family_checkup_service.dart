import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class FamilyCheckupService {
  const FamilyCheckupService();

  List<CheckupScheduleItem> getRecommendedCheckups({
    required int stageIndex,
    required String memberName,
    required String roleLabel,
    required List<CheckupScheduleItem> allCheckups,
  }) {
    if (allCheckups.isEmpty) return const [];

    final matched = <CheckupScheduleItem>[];
    final isFemale = memberName.contains('女') ||
        memberName.contains('妈') ||
        memberName.contains('妻') ||
        memberName.contains('妹') ||
        memberName.contains('姐') ||
        memberName.contains('婆') ||
        roleLabel.contains('女性') ||
        roleLabel.contains('孕') ||
        roleLabel.contains('更年期') ||
        stageIndex == 4;

    final isMale = memberName.contains('爸') ||
        memberName.contains('父') ||
        memberName.contains('夫') ||
        memberName.contains('哥') ||
        memberName.contains('弟') ||
        memberName.contains('公') ||
        memberName.contains('男');

    for (final c in allCheckups) {
      final item = c.item;
      final target = c.target;

      // Filter by gender specific
      if (item.contains('前列腺') || target.contains('男性')) {
        if (!isMale && !target.contains('全员')) continue;
      }
      if (item.contains('乳腺') || item.contains('宫颈') || target.contains('女性')) {
        if (!isFemale && !target.contains('全员')) continue;
      }

      // Stage-specific matching
      switch (stageIndex) {
        case 0: // 婴幼儿
        case 1: // 学龄前
          if (item.contains('视力') ||
              item.contains('口腔') ||
              item.contains('血常规') ||
              item.contains('听力')) {
            matched.add(c);
          }
          break;

        case 2: // 学龄期
          if (item.contains('视力') ||
              item.contains('口腔') ||
              item.contains('血常规') ||
              item.contains('体重')) {
            matched.add(c);
          }
          break;

        case 3: // 青年
          if (item.contains('血压') ||
              item.contains('口腔') ||
              item.contains('肝功能') ||
              item.contains('血常规') ||
              item.contains('视力') ||
              item.contains('甲状腺')) {
            matched.add(c);
          }
          break;

        case 4: // 育龄女性
          if (item.contains('乳腺') ||
              item.contains('宫颈') ||
              item.contains('甲状腺') ||
              item.contains('血压') ||
              item.contains('血常规') ||
              item.contains('口腔')) {
            matched.add(c);
          }
          break;

        case 5: // 职业承压期 25-50
          if (item.contains('胃肠镜') ||
              item.contains('血糖') ||
              item.contains('血脂') ||
              item.contains('肝功能') ||
              item.contains('血压') ||
              item.contains('口腔') ||
              (isFemale && (item.contains('乳腺') || item.contains('宫颈')))) {
            matched.add(c);
          }
          break;

        case 6: // 中年转折 45-60
          if (item.contains('胃肠镜') ||
              item.contains('骨密度') ||
              item.contains('血糖') ||
              item.contains('血脂') ||
              item.contains('肺部') ||
              item.contains('结肠') ||
              (isFemale && item.contains('乳腺')) ||
              (isMale && item.contains('前列腺'))) {
            matched.add(c);
          }
          break;

        case 7: // 老年 60-75
        case 8: // 高龄 75+
          if (item.contains('骨密度') ||
              item.contains('视力') ||
              item.contains('听力') ||
              item.contains('胃肠镜') ||
              item.contains('血压') ||
              item.contains('血糖') ||
              item.contains('血脂') ||
              item.contains('结肠') ||
              item.contains('肺部') ||
              (isMale && item.contains('前列腺'))) {
            matched.add(c);
          }
          break;

        case 9: // 慢病共病
        case 10: // 姑息
        default:
          if (item.contains('血压') ||
              item.contains('血糖') ||
              item.contains('血脂') ||
              item.contains('肝功能') ||
              item.contains('视力') ||
              item.contains('骨密度')) {
            matched.add(c);
          }
          break;
      }
    }

    final unique = <String, CheckupScheduleItem>{};
    for (final m in matched) {
      unique[m.item] = m;
    }
    if (unique.isEmpty) {
      for (final c in allCheckups.take(5)) {
        unique[c.item] = c;
      }
    }
    return unique.values.toList();
  }

  Future<void> addCheckupToTasks({
    required TaskRepository taskRepo,
    required String memberName,
    required CheckupScheduleItem checkup,
    required DateTime dueDate,
  }) async {
    final notePart = checkup.notes.isNotEmpty ? '\n注意事项：${checkup.notes}' : '';
    final draft = TaskDraft(
      title: '【体检提醒】为「$memberName」预约：${checkup.item}',
      description: '建议频率：${checkup.frequency}\n'
          '适用人群：${checkup.target}'
          '$notePart\n\n'
          '来自全生命周期健康筛查路线图',
      category: TaskCategory.life,
      priority: 1,
      dueAt: dueDate,
    );
    await taskRepo.create(draft);
  }
}
