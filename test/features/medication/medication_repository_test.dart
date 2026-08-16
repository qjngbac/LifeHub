import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';

void main() {
  late AppDatabase database;
  late MedicationRepository repository;
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MedicationRepository(database);
  });
  tearDown(() => database.close());

  test('stores user instructions and normalized multiple reminder times',
      () async {
    final plan = await repository.createPlan(MedicationPlanDraft(
      name: '维生素',
      instructions: '按包装说明记录',
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      reminderTimes: const ['20:30', '08:00', '08:00'],
    ));
    expect(repository.reminderTimes(plan), ['08:00', '20:30']);
    expect(repository.isActiveOn(plan, DateTime(2026, 8, 15)), isTrue);
    expect(repository.isActiveOn(plan, DateTime(2026, 9, 1)), isFalse);
    expect(plan.instructions, '按包装说明记录');
  });

  test('check-ins are idempotent for plan, date and reminder time', () async {
    final plan = await repository.createPlan(MedicationPlanDraft(
      name: '自定义记录',
      startDate: DateTime(2026, 8, 1),
      reminderTimes: const ['08:00'],
    ));
    final first = await repository.checkIn(plan.id, DateTime(2026, 8, 12), 480);
    final second =
        await repository.checkIn(plan.id, DateTime(2026, 8, 12), 480);
    expect(second.id, first.id);
    expect(await database.select(database.medicationLogs).get(), hasLength(1));
  });

  test('emergency card is one local sensitive record', () async {
    await repository.saveEmergencyCard(
      const EmergencyCardDraft(name: '本人', bloodType: 'A'),
    );
    final updated = await repository.saveEmergencyCard(
      const EmergencyCardDraft(name: '本人', allergies: '青霉素'),
    );
    expect(updated.sensitive, isTrue);
    expect(updated.allergies, '青霉素');
    expect(await database.select(database.emergencyCards).get(), hasLength(1));
  });

  test('updates and soft deletes a medication plan', () async {
    final plan = await repository.createPlan(MedicationPlanDraft(
      name: '旧计划',
      startDate: DateTime(2026, 8, 1),
      reminderTimes: const ['08:00'],
    ));
    final updated = await repository.updatePlan(
      plan.id,
      MedicationPlanDraft(
        name: '新计划',
        startDate: DateTime(2026, 8, 2),
        reminderTimes: const ['09:30'],
        notes: '饭后',
      ),
    );
    expect(updated.name, '新计划');
    expect(repository.reminderTimes(updated), ['09:30']);
    await repository.deletePlan(plan.id);
    expect(await repository.plans(activeOnly: false), isEmpty);
  });

  test('emergency card persists full birth date and notes', () async {
    final card = await repository.saveEmergencyCard(
      EmergencyCardDraft(
        name: '本人',
        birthDate: DateTime(2003, 2, 25),
        notes: '紧急情况下联系家人',
      ),
    );
    expect(card.birthDate, 20030225);
    expect(card.notes, '紧急情况下联系家人');
  });
}
