import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/trip/data/trip_expense_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';

void main() {
  late AppDatabase database;
  late TripRepository trips;
  late TripExpenseRepository expenses;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    trips = TripRepository(database);
    expenses = TripExpenseRepository(database);
  });
  tearDown(() => database.close());

  test('trip creation is project-backed and overview aggregates tasks',
      () async {
    final trip = await trips.create(TripDraft(
      name: '杭州三日游',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));
    final project = await (database.select(database.projects)
          ..where((row) => row.id.equals(trip.projectId)))
        .getSingle();
    expect(project.name, '杭州三日游');

    await TaskRepository(database).create(TaskDraft(
      title: '订高铁票',
      projectId: trip.projectId,
    ));
    final overview = await trips.overview(trip.id);
    expect(overview.tasks.single.title, '订高铁票');
  });

  test('rejects an end date before the start date', () {
    expect(
      () => trips.create(TripDraft(
        name: '无效旅行',
        startDate: DateTime(2026, 8, 20),
        endDate: DateTime(2026, 8, 19),
      )),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('expenses validate amount and summarize each currency separately',
      () async {
    final trip = await trips.create(TripDraft(
      name: '海边游',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));
    await expenses.create(TripExpenseDraft(
      tripId: trip.id,
      title: '晚餐',
      amountCents: 12800,
      currency: 'CNY',
      expenseDate: DateTime(2026, 8, 12),
      category: TripExpenseCategory.food,
      payer: '我',
    ));
    await expenses.create(TripExpenseDraft(
      tripId: trip.id,
      title: '船票',
      amountCents: 2000,
      currency: 'USD',
      expenseDate: DateTime(2026, 8, 13),
    ));
    expect(
        await expenses.totalsByCurrency(trip.id), {'CNY': 12800, 'USD': 2000});
    expect(await expenses.payerTotals(trip.id), {
      'CNY': {'我': 12800},
      'USD': {'未填写': 2000},
    });
    expect(
      () => expenses.create(TripExpenseDraft(
        tripId: trip.id,
        title: '无效',
        amountCents: 0,
        expenseDate: DateTime(2026, 8, 12),
      )),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('completed trips remain visible and keep a post-trip review', () async {
    final trip = await trips.create(TripDraft(
      name: '周末旅行',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));

    await trips.complete(trip.id);
    await trips.savePostTripReview(trip.id, '路线轻松，下次少带一件外套。');

    final visible = await trips.list();
    expect(visible.map((value) => value.id), contains(trip.id));
    expect((await trips.get(trip.id)).status, 'COMPLETED');
    expect((await trips.get(trip.id)).notes, contains('下次'));
  });

  test('city template creates a packing list and preparation tasks', () async {
    final trip = await trips.create(TripDraft(
      name: '城市旅行',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));

    await trips.applyTemplate(trip.id, 'CITY');

    final overview = await trips.overview(trip.id);
    expect(overview.lists.single.title, '旅行装备');
    expect(overview.tasks.map((value) => value.title), contains('确认交通'));
    final items = await (database.select(database.listItems)
          ..where((row) => row.listId.equals(overview.lists.single.id)))
        .get();
    expect(items.map((value) => value.textValue), contains('身份证件'));
  });
}
