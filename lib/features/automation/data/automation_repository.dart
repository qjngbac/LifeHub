import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

class AutomationRuleDraft {
  const AutomationRuleDraft({
    required this.name,
    required this.triggerType,
    required this.triggerJson,
    required this.actionType,
    required this.actionJson,
    this.enabled = true,
  });

  final String name;
  final String triggerType;
  final String triggerJson;
  final String actionType;
  final String actionJson;
  final bool enabled;
}

class AutomationRepository {
  AutomationRepository(this._database);
  final AppDatabase _database;

  Future<AutomationRuleEntry> create(AutomationRuleDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError.value(draft.name, 'name');
    final id = const Uuid().v4();
    await _database.into(_database.automationRules).insert(
          AutomationRulesCompanion.insert(
            id: Value(id),
            name: name,
            triggerType: draft.triggerType,
            triggerJson: Value(draft.triggerJson),
            actionType: draft.actionType,
            actionJson: Value(draft.actionJson),
            enabled: Value(draft.enabled),
          ),
        );
    return get(id);
  }

  Future<AutomationRuleEntry> get(String id) async {
    final row = await (_database.select(_database.automationRules)
          ..where((value) => value.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Automation rule not found.');
    return row;
  }

  Future<List<AutomationRuleEntry>> list({bool enabledOnly = false}) {
    final query = _database.select(_database.automationRules)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (enabledOnly) filter = filter & row.enabled.equals(true);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.get();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final current = await get(id);
    await (_database.update(_database.automationRules)
          ..where((row) => row.id.equals(id)))
        .write(AutomationRulesCompanion(
      enabled: Value(enabled),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
  }

  Future<bool> hasRun(String key) async =>
      await (_database.select(_database.automationRuns)
            ..where((row) =>
                row.deletedAt.isNull() & row.idempotencyKey.equals(key)))
          .getSingleOrNull() !=
      null;

  Future<void> recordRun({
    required String ruleId,
    required String key,
    required DateTime executedAt,
    String status = 'SUCCESS',
    String? message,
  }) async {
    await _database.into(_database.automationRuns).insert(
          AutomationRunsCompanion.insert(
            ruleId: ruleId,
            idempotencyKey: key,
            status: Value(status),
            message: Value(message),
            executedAt: executedAt.toUtc().millisecondsSinceEpoch,
          ),
        );
    await (_database.update(_database.automationRules)
          ..where((row) => row.id.equals(ruleId)))
        .write(AutomationRulesCompanion(
      lastRunAt: Value(executedAt.toUtc().millisecondsSinceEpoch),
    ));
  }

  Future<List<AutomationRunEntry>> runs({String? ruleId}) {
    final query = _database.select(_database.automationRuns)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (ruleId != null) filter = filter & row.ruleId.equals(ruleId);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm.desc(row.executedAt)]);
    return query.get();
  }
}
