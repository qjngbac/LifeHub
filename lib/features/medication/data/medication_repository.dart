import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';

class MedicationPlanDraft {
  const MedicationPlanDraft({
    required this.name,
    required this.startDate,
    this.instructions,
    this.endDate,
    this.reminderTimes = const <String>[],
    this.notes,
    this.active = true,
  });

  final String name;
  final String? instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final List<String> reminderTimes;
  final String? notes;
  final bool active;
}

class EmergencyCardDraft {
  const EmergencyCardDraft({
    this.name,
    this.birthDate,
    this.bloodType,
    this.allergies,
    this.conditions,
    this.medications,
    this.emergencyContacts,
    this.notes,
  });

  final String? name;
  final DateTime? birthDate;
  final String? bloodType;
  final String? allergies;
  final String? conditions;
  final String? medications;
  final String? emergencyContacts;
  final String? notes;
}

class MedicationRepository {
  MedicationRepository(this._database);
  final AppDatabase _database;

  /// 紧急联系人在库里仍是**一个** `emergencyContacts` 字段，
  /// 但界面要拆成「姓名」「电话」两栏。这里用可读的分隔符把两部分存进同一字段，
  /// 好处是不用改数据库结构、备份与旧数据都能直接读；
  /// 老数据（没有分隔符）会被整体当作姓名，用户补一次电话即可。
  static const emergencyContactSeparator = ' · ';

  static ({String name, String phone}) splitEmergencyContact(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return (name: '', phone: '');
    final index = value.indexOf(emergencyContactSeparator);
    if (index < 0) return (name: value, phone: '');
    return (
      name: value.substring(0, index).trim(),
      phone: value.substring(index + emergencyContactSeparator.length).trim(),
    );
  }

  static String joinEmergencyContact(String name, String phone) {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty) return trimmedPhone;
    if (trimmedPhone.isEmpty) return trimmedName;
    return '$trimmedName$emergencyContactSeparator$trimmedPhone';
  }

  Future<MedicationPlanEntry> createPlan(MedicationPlanDraft draft) {
    final times = _normalizedTimes(draft.reminderTimes);
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (draft.endDate != null && draft.endDate!.isBefore(draft.startDate)) {
      throw ArgumentError('End date cannot precede start date.');
    }
    return _database.into(_database.medicationPlans).insertReturning(
          MedicationPlansCompanion.insert(
            name: draft.name.trim(),
            instructions: Value(_optional(draft.instructions)),
            startDate: DateKeys.toLocalDateKey(draft.startDate),
            endDate: Value(draft.endDate == null
                ? null
                : DateKeys.toLocalDateKey(draft.endDate!)),
            reminderTimesJson: Value(jsonEncode(times)),
            notes: Value(_optional(draft.notes)),
            active: Value(draft.active),
          ),
        );
  }

  Future<MedicationPlanEntry> getPlan(String id) async {
    final row = await (_database.select(_database.medicationPlans)
          ..where((item) => item.id.equals(id) & item.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw StateError('Medication plan not found: $id');
    return row;
  }

  Future<MedicationPlanEntry> updatePlan(
    String id,
    MedicationPlanDraft draft,
  ) async {
    final times = _normalizedTimes(draft.reminderTimes);
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (draft.endDate != null && draft.endDate!.isBefore(draft.startDate)) {
      throw ArgumentError('End date cannot precede start date.');
    }
    final current = await getPlan(id);
    await (_database.update(_database.medicationPlans)
          ..where((row) => row.id.equals(id)))
        .write(MedicationPlansCompanion(
      name: Value(draft.name.trim()),
      instructions: Value(_optional(draft.instructions)),
      startDate: Value(DateKeys.toLocalDateKey(draft.startDate)),
      endDate: Value(
        draft.endDate == null ? null : DateKeys.toLocalDateKey(draft.endDate!),
      ),
      reminderTimesJson: Value(jsonEncode(times)),
      notes: Value(_optional(draft.notes)),
      active: Value(draft.active),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return getPlan(id);
  }

  Future<void> deletePlan(String id) async {
    final current = await getPlan(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.medicationPlans)
          ..where((row) => row.id.equals(id)))
        .write(MedicationPlansCompanion(
      active: const Value(false),
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  List<String> reminderTimes(MedicationPlanEntry plan) =>
      (jsonDecode(plan.reminderTimesJson) as List<dynamic>).cast<String>();

  /// 某个日期下，各计划已打卡的时间点（分钟数）。
  ///
  /// 列表页用一次查询拿到全部进度，避免每个计划各查一次；
  /// 有了它才能把「08:00 打卡」显示成「08:00 已打卡」并给出 n/m 进度。
  Future<Map<String, Set<int>>> checkedInMinutesByPlan(DateTime date) async {
    final key = DateKeys.toLocalDateKey(date);
    final rows = await (_database.select(_database.medicationLogs)
          ..where((row) => row.localDate.equals(key) & row.deletedAt.isNull()))
        .get();
    final result = <String, Set<int>>{};
    for (final row in rows) {
      (result[row.planId] ??= <int>{}).add(row.timeMinutes);
    }
    return result;
  }

  bool isActiveOn(MedicationPlanEntry plan, DateTime date) {
    if (!plan.active || plan.deletedAt != null) return false;
    final key = DateKeys.toLocalDateKey(date);
    return key >= plan.startDate &&
        (plan.endDate == null || key <= plan.endDate!);
  }

  Future<List<MedicationPlanEntry>> plans({bool activeOnly = true}) {
    final query = _database.select(_database.medicationPlans)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (activeOnly) expression = expression & row.active.equals(true);
        return expression;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.name)]);
    return query.get();
  }

  Future<MedicationLogEntry> checkIn(
    String planId,
    DateTime date,
    int timeMinutes, {
    String status = 'TAKEN',
  }) async {
    if (timeMinutes < 0 || timeMinutes >= 24 * 60) {
      throw ArgumentError.value(timeMinutes, 'timeMinutes');
    }
    final key = DateKeys.toLocalDateKey(date);
    return _database.transaction(() async {
      final plan = await getPlan(planId);
      if (!isActiveOn(plan, date)) {
        throw StateError('Medication plan is not active on this date.');
      }
      final existing = await (_database.select(_database.medicationLogs)
            ..where((row) =>
                row.planId.equals(planId) &
                row.localDate.equals(key) &
                row.timeMinutes.equals(timeMinutes)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.deletedAt == null) return existing;
        await (_database.update(_database.medicationLogs)
              ..where((row) => row.id.equals(existing.id)))
            .write(MedicationLogsCompanion(
          deletedAt: const Value(null),
          status: Value(status),
          updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          version: Value(existing.version + 1),
        ));
        return (_database.select(_database.medicationLogs)
              ..where((row) => row.id.equals(existing.id)))
            .getSingle();
      }
      return _database.into(_database.medicationLogs).insertReturning(
            MedicationLogsCompanion.insert(
              planId: planId,
              localDate: key,
              timeMinutes: timeMinutes,
              status: Value(status),
            ),
          );
    });
  }

  Future<EmergencyCardEntry> saveEmergencyCard(EmergencyCardDraft draft) async {
    final today = DateTime.now();
    final minimum = DateTime(1900);
    if (draft.birthDate != null &&
        (draft.birthDate!.isBefore(minimum) ||
            draft.birthDate!
                .isAfter(DateTime(today.year, today.month, today.day)))) {
      throw ArgumentError.value(draft.birthDate, 'birthDate');
    }
    final current = await (_database.select(_database.emergencyCards)
          ..where((row) => row.deletedAt.isNull()))
        .getSingleOrNull();
    final companion = EmergencyCardsCompanion(
      name: Value(_optional(draft.name)),
      birthDate: Value(draft.birthDate == null
          ? null
          : DateKeys.toLocalDateKey(draft.birthDate!)),
      bloodType: Value(_optional(draft.bloodType)),
      allergies: Value(_optional(draft.allergies)),
      conditions: Value(_optional(draft.conditions)),
      medications: Value(_optional(draft.medications)),
      emergencyContacts: Value(_optional(draft.emergencyContacts)),
      notes: Value(_optional(draft.notes)),
      sensitive: const Value(true),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
    );
    if (current == null) {
      return _database
          .into(_database.emergencyCards)
          .insertReturning(companion);
    }
    await (_database.update(_database.emergencyCards)
          ..where((row) => row.id.equals(current.id)))
        .write(companion);
    return (_database.select(_database.emergencyCards)
          ..where((row) => row.id.equals(current.id)))
        .getSingle();
  }

  Future<EmergencyCardEntry?> emergencyCard() =>
      (_database.select(_database.emergencyCards)
            ..where((row) => row.deletedAt.isNull()))
          .getSingleOrNull();

  static List<String> _normalizedTimes(List<String> values) {
    final result = <String>{};
    for (final raw in values) {
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
      if (match == null) throw ArgumentError.value(raw, 'reminderTimes');
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour > 23 || minute > 59) {
        throw ArgumentError.value(raw, 'reminderTimes');
      }
      result.add(
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    }
    return result.toList()..sort();
  }
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
