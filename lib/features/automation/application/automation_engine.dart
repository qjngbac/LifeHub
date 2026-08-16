import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/automation/data/automation_repository.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class AutomationEngine {
  AutomationEngine(this._database);
  final AppDatabase _database;

  Future<int> runDue(DateTime now) async {
    final repository = AutomationRepository(_database);
    final rules = await repository.list(enabledOnly: true);
    var executed = 0;
    for (final rule in rules) {
      if (!await _matches(rule, now)) continue;
      final key = '${rule.id}:${DateKeys.toLocalDateKey(now)}';
      try {
        final didRun = await _database.transaction(() async {
          if (await repository.hasRun(key)) return false;
          await _execute(rule, now);
          await repository.recordRun(
            ruleId: rule.id,
            key: key,
            executedAt: now,
          );
          return true;
        });
        if (didRun) executed++;
      } catch (error) {
        if (!await repository.hasRun(key)) {
          await repository.recordRun(
            ruleId: rule.id,
            key: key,
            executedAt: now,
            status: 'FAILED',
            message: error.toString(),
          );
        }
      }
    }
    return executed;
  }

  Future<bool> _matches(AutomationRuleEntry rule, DateTime now) async {
    final trigger = jsonDecode(rule.triggerJson);
    if (trigger is! Map) return false;
    switch (rule.triggerType) {
      case 'WEEKLY':
        return trigger['weekday'] == now.weekday;
      case 'DAILY':
        return true;
      case 'COURSE_REVIEW':
        final afterMinutes = trigger['afterMinutes'];
        return trigger['weekday'] == now.weekday &&
            afterMinutes is int &&
            now.hour * 60 + now.minute >= afterMinutes;
      case 'ANNIVERSARY_BEFORE':
        return await _matchingAnniversary(rule, now) != null;
      default:
        return false;
    }
  }

  Future<void> _execute(AutomationRuleEntry rule, DateTime now) async {
    final action = jsonDecode(rule.actionJson);
    if (action is! Map) throw const FormatException('Invalid action');
    switch (rule.actionType) {
      case 'CREATE_TASK':
        var title = action['title']?.toString().trim() ?? '';
        if (rule.triggerType == 'ANNIVERSARY_BEFORE') {
          final anniversary = await _matchingAnniversary(rule, now);
          if (anniversary == null) return;
          title = title.replaceAll('{anniversary}', anniversary.title);
        }
        if (title.isEmpty) throw const FormatException('Missing task title');
        await TaskRepository(_database).create(TaskDraft(title: title));
      case 'ROLLOVER_TASKS':
        await _rolloverTasks(now);
      default:
        throw UnsupportedError('Unsupported automation action.');
    }
  }

  Future<AnniversaryEntry?> _matchingAnniversary(
    AutomationRuleEntry rule,
    DateTime now,
  ) async {
    final trigger = jsonDecode(rule.triggerJson);
    if (trigger is! Map) return null;
    final id = trigger['anniversaryId']?.toString();
    final daysBefore = trigger['daysBefore'];
    if (id == null || daysBefore is! int || daysBefore < 0) return null;
    final repository = AnniversaryRepository(_database);
    for (final value in await repository.listAll()) {
      if (value.id == id && repository.daysUntil(value, now) == daysBefore) {
        return value;
      }
    }
    return null;
  }

  Future<void> _rolloverTasks(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final startMs = today.toUtc().millisecondsSinceEpoch;
    final dueMs = DateTime(now.year, now.month, now.day, 23, 59)
        .toUtc()
        .millisecondsSinceEpoch;
    final changedAt = now.toUtc().millisecondsSinceEpoch;
    final overdue = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('TODO') &
              row.dueAt.isSmallerThanValue(startMs)))
        .get();
    for (final task in overdue) {
      await (_database.update(_database.tasks)
            ..where((row) => row.id.equals(task.id)))
          .write(TasksCompanion(
        dueAt: Value(dueMs),
        updatedAt: Value(changedAt),
        version: Value(task.version + 1),
      ));
    }
  }
}
