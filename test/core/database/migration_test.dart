import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';

void main() {
  for (final version in [10, 11]) {
    test('schema $version rolls back failed DDL and can retry the upgrade',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('lifehub_migration_failure_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      await _seedCurrentDatabase(file);
      final interceptor = _FailAfterFirstMigrationDdl();
      final database = AppDatabase.forTesting(NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('DROP TABLE match_records');
          if (version == 10) {
            raw.execute('ALTER TABLE focus_sessions DROP COLUMN mode');
          }
          raw.execute('PRAGMA user_version = $version');
        },
      ).interceptWith(interceptor));
      try {
        await expectLater(
          database.select(database.tasks).get(),
          throwsA(isA<_InjectedMigrationFailure>()),
        );
      } finally {
        await database.close();
      }
      expect(interceptor.injected, isTrue);

      final inspector = NativeDatabase(file);
      try {
        await inspector.ensureOpen(_InspectWithoutMigration(version));
        expect(
          (await inspector.runSelect('PRAGMA user_version', []))
              .single['user_version'],
          version,
        );
        expect(
          await inspector.runSelect(
            "SELECT name FROM sqlite_master WHERE name = 'match_records'",
            [],
          ),
          isEmpty,
        );
        final columns = await inspector.runSelect(
          'PRAGMA table_info(focus_sessions)',
          [],
        );
        expect(columns.any((row) => row['name'] == 'mode'), version == 11);
        expect(
          (await inspector.runSelect('SELECT title FROM tasks', []))
              .single['title'],
          '保留旧任务',
        );
      } finally {
        await inspector.close();
      }

      final retry = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect((await retry.select(retry.tasks).getSingle()).id, 'legacy-task');
        expect(await retry.select(retry.matchRecords).get(), isEmpty);
        expect(
          (await retry.select(retry.focusSessions).getSingle()).mode,
          version == 10 ? 'COUNTDOWN' : 'COUNTUP',
        );
        expect(
          (await retry.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          13,
        );
      } finally {
        await retry.close();
      }
    });
  }
  for (var version = 1; version <= 11; version++) {
    test('SQLite schema $version upgrades to 13 without losing records',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('lifehub_migrate_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      await _seedCurrentDatabase(file);
      final database = AppDatabase.forTesting(NativeDatabase(
        file,
        setup: (raw) {
          // Reconstruct old DDL from the table/column introduction versions in
          // app_database.dart. Git retains schemas 11 (0335817) and 12, not 1-10.
          for (final index in raw.select(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name NOT LIKE 'sqlite_%'",
          )) {
            raw.execute('DROP INDEX "${index['name']}"');
          }
          for (final entry in _introducedTables.entries) {
            if (version < entry.value) {
              raw.execute('DROP TABLE "${entry.key}"');
            }
          }
          void removeColumns(String table, List<String> columns) {
            for (final column in columns) {
              raw.execute('ALTER TABLE "$table" DROP COLUMN "$column"');
            }
          }

          if (version < 3) {
            removeColumns('events', ['archived']);
            removeColumns('course_schedules', ['archived']);
          }
          if (version >= 4 && version < 7) {
            removeColumns('entity_links', ['relation_type', 'note']);
          }
          if (version < 9) {
            removeColumns('events', [
              'preparation_minutes',
              'travel_minutes',
              'departure_reminder_enabled',
            ]);
            removeColumns('reminders', ['reminder_kind']);
            if (version >= 7) {
              removeColumns('household_items', [
                'item_kind',
                'quantity',
                'unit',
                'opened_date',
                'expiry_date',
                'minimum_quantity',
              ]);
            }
          }
          if (version >= 7 && version < 10) {
            removeColumns('emergency_cards', ['birth_date']);
            raw.execute(
                'ALTER TABLE emergency_cards ADD COLUMN birth_year INTEGER');
            raw.execute('UPDATE emergency_cards SET birth_year = 1980');
          }
          if (version >= 4 && version < 11) {
            removeColumns('focus_sessions', ['mode']);
          }
          if (version >= 7 && version < 13) {
            removeColumns('finance_entries', [
              'account_id',
              'target_account_id',
              'sub_category',
              'expense_nature',
              'is_reimbursable',
              'reimburse_status',
              'tags_json',
              'related_entry_id',
            ]);
          }
          raw.execute('PRAGMA user_version = $version');
          expect(raw.select('PRAGMA user_version').single['user_version'],
              version);
          expect(
            raw.select(
                "SELECT name FROM sqlite_master WHERE name = 'match_records'"),
            isEmpty,
          );
        },
      ));
      addTearDown(database.close);

      final task = await database.select(database.tasks).getSingle();
      expect(task.id, 'legacy-task');
      expect(task.title, '保留旧任务');
      expect(task.description, 'existing description');
      expect(task.priority, 3);
      expect(task.version, 7);
      expect(task.dueAt, 1790000000000);
      expect(task.createdAt, 1700000000000);
      expect(task.updatedAt, 1710000000000);
      expect(task.metadata, '{"legacy":true}');
      expect(task.deletedAt, isNull);
      final pragma =
          await database.customSelect('PRAGMA user_version').getSingle();
      expect(pragma.read<int>('user_version'), 13);

      final event = await database.select(database.events).getSingle();
      expect(event.title, '旧归档日程');
      expect(event.archived, version < 3);
      expect(event.deletedAt, version < 3 ? isNull : 1720000000000);
      expect(event.preparationMinutes, version < 9 ? 0 : 15);
      expect(event.travelMinutes, version < 9 ? 0 : 30);

      if (version >= 4) {
        final link = await database.select(database.entityLinks).getSingle();
        expect(link.sourceId, 'legacy-task');
        expect(link.relationType, version < 7 ? isNull : 'RELATED');
        expect(link.note, version < 7 ? isNull : 'existing relation');
        final focus = await database.select(database.focusSessions).getSingle();
        expect(focus.plannedMinutes, 25);
        expect(focus.mode, version < 11 ? 'COUNTDOWN' : 'COUNTUP');
      } else {
        await database.into(database.focusSessions).insert(
              FocusSessionsCompanion.insert(
                  plannedMinutes: 25, startedAt: 1730000000000),
            );
        expect((await database.select(database.focusSessions).getSingle()).mode,
            'COUNTDOWN');
      }
      if (version >= 7) {
        final household =
            await database.select(database.householdItems).getSingle();
        expect(household.name, '旧物品');
        expect(household.itemKind, version < 9 ? 'DURABLE' : 'CONSUMABLE');
        expect(household.quantity, version < 9 ? 1 : 2.5);
        final card = await database.select(database.emergencyCards).getSingle();
        expect(card.name, '旧急救卡');
        expect(card.birthDate, version < 10 ? 19800101 : 19800506);
      } else {
        await database.into(database.emergencyCards).insert(
              const EmergencyCardsCompanion(
                  name: Value('新急救卡'), birthDate: Value(19800506)),
            );
        expect(
            (await database.select(database.emergencyCards).getSingle())
                .birthDate,
            19800506);
      }
      expect(await database.select(database.matchRecords).get(), isEmpty);
      await database.into(database.matchRecords).insert(
            MatchRecordsCompanion.insert(
              sportType: '足球',
              competition: '英超',
              participantA: 'A',
              participantB: 'B',
              matchDate: 20261004,
            ),
          );
      expect(
          (await database.select(database.matchRecords).getSingle())
              .participantA,
          'A');
      expect(
          await database
              .customSelect('PRAGMA integrity_check')
              .getSingle()
              .then((row) => row.read<String>('integrity_check')),
          'ok');
    });
  }
}

class _InjectedMigrationFailure implements Exception {}

class _FailAfterFirstMigrationDdl extends QueryInterceptor {
  bool injected = false;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_InterceptMigrationOpen(user, this));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (!injected &&
        RegExp(r'^(CREATE TABLE|ALTER TABLE)', caseSensitive: false)
            .hasMatch(statement.trimLeft())) {
      injected = true;
      throw _InjectedMigrationFailure();
    }
  }
}

class _InterceptMigrationOpen implements QueryExecutorUser {
  _InterceptMigrationOpen(this.user, this.interceptor);
  final QueryExecutorUser user;
  final QueryInterceptor interceptor;

  @override
  int get schemaVersion => user.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      user.beforeOpen(executor.interceptWith(interceptor), details);
}

class _InspectWithoutMigration implements QueryExecutorUser {
  _InspectWithoutMigration(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}
}

Future<void> _seedCurrentDatabase(File file) async {
  final database = AppDatabase.forTesting(NativeDatabase(file));
  try {
    await database.into(database.tasks).insert(TasksCompanion.insert(
          id: const Value('legacy-task'),
          title: '保留旧任务',
          description: const Value('existing description'),
          priority: const Value(3),
          dueAt: const Value(1790000000000),
          version: const Value(7),
          createdAt: const Value(1700000000000),
          updatedAt: const Value(1710000000000),
          metadata: const Value('{"legacy":true}'),
        ));
    await database.into(database.events).insert(EventsCompanion.insert(
          id: const Value('legacy-event'),
          title: '旧归档日程',
          startAt: 1730000000000,
          endAt: 1730003600000,
          deletedAt: const Value(1720000000000),
          preparationMinutes: const Value(15),
          travelMinutes: const Value(30),
        ));
    await database
        .into(database.entityLinks)
        .insert(EntityLinksCompanion.insert(
          sourceType: 'TASK',
          sourceId: 'legacy-task',
          targetType: 'EVENT',
          targetId: 'legacy-event',
          relationType: const Value('RELATED'),
          note: const Value('existing relation'),
        ));
    await database
        .into(database.focusSessions)
        .insert(FocusSessionsCompanion.insert(
          mode: const Value('COUNTUP'),
          plannedMinutes: 25,
          startedAt: 1730000000000,
        ));
    await database
        .into(database.householdItems)
        .insert(HouseholdItemsCompanion.insert(
          name: '旧物品',
          itemKind: const Value('CONSUMABLE'),
          quantity: const Value(2.5),
        ));
    await database.into(database.emergencyCards).insert(
          const EmergencyCardsCompanion(
              name: Value('旧急救卡'), birthDate: Value(19800506)),
        );
  } finally {
    await database.close();
  }
}

const _introducedTables = <String, int>{
  'relationship_profiles': 2,
  'mood_logs': 2,
  'life_events': 2,
  'cycle_records': 2,
  'anniversaries': 2,
  'goals': 4,
  'milestones': 4,
  'entity_links': 4,
  'focus_sessions': 4,
  'reviews': 4,
  'inbox_items': 5,
  'automation_rules': 5,
  'automation_runs': 5,
  'saved_items': 6,
  'attachments': 6,
  'attachment_links': 6,
  'locations': 6,
  'trip_profiles': 6,
  'trip_expenses': 6,
  'weather_locations': 7,
  'weather_forecast_caches': 7,
  'evening_prep_items': 7,
  'household_items': 7,
  'medication_plans': 7,
  'medication_logs': 7,
  'emergency_cards': 7,
  'finance_entries': 7,
  'credential_records': 7,
  'media_series': 8,
  'media_entries': 8,
  'course_grades': 9,
  'subscriptions': 9,
  'maintenance_plans': 9,
  'maintenance_logs': 9,
  'reading_items': 9,
  'parcels': 9,
  'match_records': 12,
  'finance_accounts': 13,
};
