import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';

void main() {
  test(
    'search audit relation candidates filter before cap and avoid per-row reads',
    () async {
      final recorder = _CandidateReads();
      final database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(recorder),
      );
      addTearDown(database.close);
      for (var index = 0; index < 40; index++) {
        await database
            .into(database.tasks)
            .insert(
              TasksCompanion.insert(
                title: index == 39 ? 'needle' : 'other $index',
              ),
            );
      }
      recorder.reads.clear();
      final repository = RelationRepository(database);
      final found = await repository.candidates(query: 'needle');
      expect(found.map((row) => row.title), ['needle']);
      expect(
        recorder.reads.where((sql) => sql.contains('FROM "tasks"')),
        hasLength(1),
      );
      expect(recorder.reads.length, lessThanOrEqualTo(16));
      final all = await repository.candidates();
      expect(
        all.where((row) => row.reference.type == 'TASK').length,
        lessThanOrEqualTo(30),
      );
    },
  );

  test(
    'search audit relation candidates retain supported types and existing labels',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.tasks)
          .insert(
            TasksCompanion.insert(title: '任务', status: const Value('ARCHIVED')),
          );
      await database
          .into(database.tasks)
          .insert(
            TasksCompanion.insert(title: '已删除', deletedAt: const Value(1)),
          );
      await database
          .into(database.events)
          .insert(EventsCompanion.insert(title: '日程', startAt: 1, endAt: 2));
      await database
          .into(database.courses)
          .insert(CoursesCompanion.insert(name: '课程', semesterId: 'semester'));
      await database
          .into(database.goals)
          .insert(GoalsCompanion.insert(name: '目标'));
      final project = await database
          .into(database.projects)
          .insertReturning(ProjectsCompanion.insert(name: '旅行项目'));
      await database
          .into(database.locations)
          .insert(LocationsCompanion.insert(name: '地点'));
      await database
          .into(database.savedItems)
          .insert(
            SavedItemsCompanion.insert(
              title: '敏感资料标题',
              sensitive: const Value(true),
            ),
          );
      await database
          .into(database.tripProfiles)
          .insert(
            TripProfilesCompanion.insert(
              projectId: project.id,
              startDate: 20261001,
              endDate: 20261004,
            ),
          );
      await database
          .into(database.tripProfiles)
          .insert(
            TripProfilesCompanion.insert(
              projectId: 'missing',
              startDate: 20261001,
              endDate: 20261004,
            ),
          );
      await database
          .into(database.householdItems)
          .insert(
            HouseholdItemsCompanion.insert(
              name: '家庭物品',
              sensitive: const Value(true),
            ),
          );
      await database
          .into(database.financeEntries)
          .insert(
            FinanceEntriesCompanion.insert(
              direction: 'INCOME',
              amountMinor: 1,
              occurredAt: 1,
              sensitive: const Value(true),
            ),
          );
      await database
          .into(database.financeEntries)
          .insert(
            FinanceEntriesCompanion.insert(
              direction: 'EXPENSE',
              amountMinor: 1,
              occurredAt: 1,
            ),
          );
      await database
          .into(database.credentialRecords)
          .insert(CredentialRecordsCompanion.insert(name: '证件标题'));
      await database
          .into(database.subscriptions)
          .insert(
            SubscriptionsCompanion.insert(
              name: '订阅',
              amountMinor: 1,
              cycleUnit: 'MONTH',
              nextRenewalDate: 20261004,
            ),
          );
      await database
          .into(database.maintenancePlans)
          .insert(
            MaintenancePlansCompanion.insert(
              title: '保养',
              intervalDays: 30,
              nextDueAt: 1,
            ),
          );
      await database
          .into(database.readingItems)
          .insert(ReadingItemsCompanion.insert(title: '读物'));
      await database
          .into(database.parcels)
          .insert(ParcelsCompanion.insert(title: '快递'));
      final repository = RelationRepository(database);
      final results = await repository.candidates();
      expect(results.map((row) => row.reference.type).toSet(), {
        'TASK',
        'EVENT',
        'COURSE',
        'GOAL',
        'PROJECT',
        'LOCATION',
        'SAVED_ITEM',
        'TRIP',
        'HOUSEHOLD',
        'FINANCE',
        'CREDENTIAL',
        'SUBSCRIPTION',
        'MAINTENANCE',
        'READING',
        'PARCEL',
      });
      expect(results.map((row) => row.title), isNot(contains('已删除')));
      expect(
        results
            .where((row) => row.reference.type == 'FINANCE')
            .map((row) => row.title)
            .toSet(),
        {'收入', '支出'},
      );
      expect(
        results
            .where((row) => row.reference.type == 'TRIP')
            .map((row) => row.title)
            .toSet(),
        {'旅行项目', '旅行'},
      );
      expect((await repository.candidates(query: '收入')).single.title, '收入');
      expect(
        (await repository.candidates(query: '敏感资料')).single.title,
        '敏感资料标题',
      );
    },
  );
}

class _CandidateReads extends QueryInterceptor {
  final reads = <String>[];
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    reads.add(statement);
    return executor.runSelect(statement, args);
  }
}
