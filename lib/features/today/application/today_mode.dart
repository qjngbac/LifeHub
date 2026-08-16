import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/today/application/today_service.dart';

abstract final class TodayModeRanking {
  static List<TaskEntry> tasks(
    Iterable<TaskEntry> source,
    Set<LifeMode> modes,
  ) {
    final indexed = source.indexed.toList();
    indexed.sort((a, b) {
      final score = taskScore(b.$2, modes).compareTo(taskScore(a.$2, modes));
      return score != 0 ? score : a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  static List<TodayEvent> events(
    Iterable<TodayEvent> source,
    Set<LifeMode> modes,
  ) {
    final indexed = source.indexed.toList();
    indexed.sort((a, b) {
      final score = eventScore(b.$2, modes).compareTo(eventScore(a.$2, modes));
      if (score != 0) return score;
      return a.$2.start.compareTo(b.$2.start);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  static int taskScore(TaskEntry task, Set<LifeMode> modes) {
    var score = 0;
    if (modes.contains(LifeMode.student) &&
        task.category == TaskCategory.study) {
      score += 4;
    }
    if (modes.contains(LifeMode.work) &&
        (task.category == TaskCategory.work || task.projectId != null)) {
      score += 4;
    }
    if (modes.contains(LifeMode.daily) && task.category == TaskCategory.life) {
      score += 3;
    }
    if (modes.contains(LifeMode.outdoor) &&
        task.category == TaskCategory.outdoor) {
      score += 4;
    }
    return score;
  }

  static int eventScore(TodayEvent event, Set<LifeMode> modes) =>
      modes.contains(LifeMode.student) && event.isCourse ? 4 : 0;
}
