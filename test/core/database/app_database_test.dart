import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('fresh database creates V1.2-V1.9 tables and relation metadata',
      () async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        )
        .get();
    final names = rows.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll(<String>{
        'tasks',
        'projects',
        'events',
        'semesters',
        'courses',
        'course_schedules',
        'lists',
        'list_items',
        'habits',
        'habit_logs',
        'tags',
        'entity_tags',
        'reminders',
        'module_configs',
        'change_logs',
        'relationship_profiles',
        'mood_logs',
        'life_events',
        'cycle_records',
        'anniversaries',
        'goals',
        'milestones',
        'entity_links',
        'focus_sessions',
        'reviews',
        'inbox_items',
        'automation_rules',
        'automation_runs',
        'saved_items',
        'attachments',
        'attachment_links',
        'locations',
        'trip_profiles',
        'trip_expenses',
        'weather_locations',
        'weather_forecast_caches',
        'evening_prep_items',
        'household_items',
        'medication_plans',
        'medication_logs',
        'emergency_cards',
        'finance_entries',
        'credential_records',
        'media_series',
        'media_entries',
        'course_grades',
        'subscriptions',
        'maintenance_plans',
        'maintenance_logs',
        'reading_items',
        'parcels',
      }),
    );
    expect(database.schemaVersion, 11);
    final eventColumns =
        await database.customSelect('PRAGMA table_info(events)').get();
    expect(
      eventColumns.map((row) => row.read<String>('name')),
      contains('archived'),
    );
    expect(
      eventColumns.map((row) => row.read<String>('name')),
      containsAll(<String>{
        'preparation_minutes',
        'travel_minutes',
        'departure_reminder_enabled',
      }),
    );
    final householdColumns =
        await database.customSelect('PRAGMA table_info(household_items)').get();
    expect(
      householdColumns.map((row) => row.read<String>('name')),
      containsAll(<String>{
        'item_kind',
        'quantity',
        'unit',
        'opened_date',
        'expiry_date',
        'minimum_quantity',
      }),
    );
    final emergencyCardColumns =
        await database.customSelect('PRAGMA table_info(emergency_cards)').get();
    expect(
      emergencyCardColumns.map((row) => row.read<String>('name')),
      contains('birth_date'),
    );
    final scheduleColumns = await database
        .customSelect('PRAGMA table_info(course_schedules)')
        .get();
    final focusColumns =
        await database.customSelect('PRAGMA table_info(focus_sessions)').get();
    expect(
      focusColumns.map((row) => row.read<String>('name')),
      contains('mode'),
    );
    expect(
      scheduleColumns.map((row) => row.read<String>('name')),
      contains('archived'),
    );
    final relationColumns =
        await database.customSelect('PRAGMA table_info(entity_links)').get();
    expect(
      relationColumns.map((row) => row.read<String>('name')),
      containsAll(<String>{'relation_type', 'note'}),
    );
  });

  test('task accepts a title and applies offline defaults', () async {
    await database.into(database.tasks).insert(
          TasksCompanion.insert(title: '整理本周计划'),
        );

    final task = await database.select(database.tasks).getSingle();
    expect(task.id, isNotEmpty);
    expect(task.status, 'TODO');
    expect(task.category, 'LIFE');
    expect(task.priority, 0);
    expect(task.createdAt, greaterThan(0));
    expect(task.updatedAt, greaterThan(0));
    expect(task.version, 1);
    expect(task.deletedAt, isNull);
  });

  test('habit can only have one log for the same local date', () async {
    await database.into(database.habits).insert(
          HabitsCompanion.insert(
            id: const Value('habit-reading'),
            name: '阅读',
          ),
        );
    await database.into(database.habitLogs).insert(
          HabitLogsCompanion.insert(
            habitId: 'habit-reading',
            localDate: 20260808,
          ),
        );

    expect(
      () => database.into(database.habitLogs).insert(
            HabitLogsCompanion.insert(
              habitId: 'habit-reading',
              localDate: 20260808,
            ),
          ),
      throwsA(anything),
    );
  });
}
