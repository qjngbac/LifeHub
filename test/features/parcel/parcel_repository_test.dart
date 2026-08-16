import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';

void main() {
  test('pending pickup is ordered by deadline and can be collected', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = ParcelRepository(db);
    final later = await repository.create(ParcelDraft(
      title: '书籍',
      status: ParcelStatus.ready,
      pickupDeadline: DateTime(2026, 8, 15),
      pickupCode: '3-5-99',
    ));
    final sooner = await repository.create(ParcelDraft(
      title: '生活用品',
      status: ParcelStatus.ready,
      pickupDeadline: DateTime(2026, 8, 13),
    ));

    expect((await repository.pendingPickup()).map((e) => e.id),
        [sooner.id, later.id]);
    await repository.markCollected(sooner.id, at: DateTime(2026, 8, 12));
    expect((await repository.get(sooner.id)).status,
        ParcelStatus.collected.dbValue);
    expect(await repository.search('3-5-99'), hasLength(1));
  });

  test('advances, edits and deletes a parcel record', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = ParcelRepository(db);
    final parcel = await repository.create(const ParcelDraft(
      title: '鼠标',
      notes: '机械鼠标，明天下午到',
    ));
    expect((await repository.advance(parcel.id)).status,
        ParcelStatus.ready.dbValue);
    expect((await repository.advance(parcel.id)).status,
        ParcelStatus.collected.dbValue);
    final updated = await repository.update(
      parcel.id,
      const ParcelDraft(
        title: '无线鼠标',
        notes: '放在前台',
        status: ParcelStatus.ready,
      ),
    );
    expect(updated.title, '无线鼠标');
    expect(updated.notes, '放在前台');
    await repository.delete(parcel.id);
    expect(await repository.list(), isEmpty);
  });
}
