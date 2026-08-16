import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';

class SubscriptionDraft {
  const SubscriptionDraft({
    required this.name,
    required this.amountMinor,
    required this.cycleUnit,
    required this.nextRenewalDate,
    this.category = 'OTHER',
    this.currency = 'CNY',
    this.cycleInterval = 1,
    this.fixedDays,
    this.trialEndDate,
    this.autoRenew = true,
    this.cancellationUrl,
    this.notes,
    this.reminderDays = const [7, 3, 1],
  });

  final String name;
  final int amountMinor;
  final SubscriptionCycleUnit cycleUnit;
  final DateTime nextRenewalDate;
  final String category;
  final String currency;
  final int cycleInterval;
  final int? fixedDays;
  final DateTime? trialEndDate;
  final bool autoRenew;
  final String? cancellationUrl;
  final String? notes;
  final List<int> reminderDays;
}

class SubscriptionRepository {
  SubscriptionRepository(this._database);
  final AppDatabase _database;

  Future<SubscriptionEntry> create(SubscriptionDraft draft) async {
    _validate(draft);
    return _database.into(_database.subscriptions).insertReturning(
          SubscriptionsCompanion.insert(
            name: draft.name.trim(),
            category: Value(draft.category),
            amountMinor: draft.amountMinor,
            currency: Value(draft.currency),
            cycleUnit: draft.cycleUnit.dbValue,
            cycleInterval: Value(draft.cycleInterval),
            fixedDays: Value(draft.fixedDays),
            nextRenewalDate: DateKeys.toLocalDateKey(draft.nextRenewalDate),
            trialEndDate: Value(draft.trialEndDate == null
                ? null
                : DateKeys.toLocalDateKey(draft.trialEndDate!)),
            autoRenew: Value(draft.autoRenew),
            cancellationUrl: Value(_optional(draft.cancellationUrl)),
            notes: Value(_optional(draft.notes)),
            reminderDaysJson: Value(jsonEncode(draft.reminderDays)),
          ),
        );
  }

  Future<SubscriptionEntry> get(String id) async {
    final row = await (_database.select(_database.subscriptions)
          ..where((item) => item.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Subscription not found: $id');
    return row;
  }

  Future<List<SubscriptionEntry>> list({bool includeInactive = false}) =>
      (_database.select(_database.subscriptions)
            ..where((row) {
              var result = row.deletedAt.isNull();
              if (!includeInactive) {
                result = result & row.status.equals('ACTIVE');
              }
              return result;
            })
            ..orderBy([(row) => OrderingTerm.asc(row.nextRenewalDate)]))
          .get();

  Future<FinanceEntry> confirmCharge(
    String id, {
    required int cycleDate,
    DateTime? occurredAt,
  }) async {
    late FinanceEntry finance;
    await _database.transaction(() async {
      final row = await get(id);
      if (row.status != 'ACTIVE' ||
          row.nextRenewalDate != cycleDate ||
          row.lastConfirmedCycleDate == cycleDate) {
        throw StateError('This subscription cycle is no longer due.');
      }
      finance = await _database.into(_database.financeEntries).insertReturning(
            FinanceEntriesCompanion.insert(
              direction: 'EXPENSE',
              amountMinor: row.amountMinor,
              currency: Value(row.currency),
              category: const Value('SUBSCRIPTION'),
              occurredAt: (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
              note: Value('${row.name} 订阅扣费'),
            ),
          );
      await RelationRepository(_database).link(
        EntityReference(type: 'SUBSCRIPTION', id: row.id),
        EntityReference(type: 'FINANCE', id: finance.id),
        relationType: 'CHARGE',
      );
      final next = SubscriptionRules.nextRenewal(
        from: DateKeys.fromLocalDateKey(cycleDate),
        unit: SubscriptionCycleUnitValue.fromDb(row.cycleUnit),
        interval: row.cycleInterval,
        fixedDays: row.fixedDays,
      );
      await (_database.update(_database.subscriptions)
            ..where((item) => item.id.equals(id)))
          .write(SubscriptionsCompanion(
        nextRenewalDate: Value(DateKeys.toLocalDateKey(next)),
        lastConfirmedCycleDate: Value(cycleDate),
        updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        version: Value(row.version + 1),
      ));
    });
    return finance;
  }

  Future<void> setStatus(String id, String status) async {
    if (!{'ACTIVE', 'PAUSED', 'CANCELED'}.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final row = await get(id);
    await (_database.update(_database.subscriptions)
          ..where((item) => item.id.equals(id)))
        .write(SubscriptionsCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(row.version + 1),
    ));
  }

  static void _validate(SubscriptionDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    if (draft.amountMinor <= 0) {
      throw ArgumentError.value(draft.amountMinor, 'amount');
    }
    SubscriptionRules.nextRenewal(
      from: draft.nextRenewalDate,
      unit: draft.cycleUnit,
      interval: draft.cycleInterval,
      fixedDays: draft.fixedDays,
    );
    if (draft.reminderDays.any((value) => value < 0)) {
      throw ArgumentError.value(draft.reminderDays, 'reminderDays');
    }
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
