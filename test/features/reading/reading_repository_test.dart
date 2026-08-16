import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';

void main() {
  test('reading progress and module-local search are persisted', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = ReadingRepository(db);
    final row = await repository.create(const ReadingDraft(
      title: '雪山生存手册',
      readingType: ReadingType.book,
      progressUnit: ReadingUnit.page,
      totalProgress: 200,
    ));
    await repository.updateProgress(row.id, 40, now: DateTime(2026, 8, 11));

    final updated = await repository.get(row.id);
    expect(updated.currentProgress, 40);
    expect(updated.status, ReadingStatus.reading.dbValue);
    expect(await repository.search('雪山'), hasLength(1));
    expect(await repository.continueReading(), hasLength(1));
  });

  test('current and total progress may each be filled independently', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = ReadingRepository(db);
    final empty = await repository.create(const ReadingDraft(title: '未规划'));
    expect(empty.currentProgress, 0);
    expect(empty.totalProgress, isNull);
    final currentOnly = await repository.create(const ReadingDraft(
      title: '无总数',
      currentProgress: 2,
    ));
    expect(currentOnly.currentProgress, 2);
    expect(currentOnly.totalProgress, isNull);
    final totalOnly = await repository.create(const ReadingDraft(
      title: '只填总数',
      totalProgress: 80,
    ));
    expect(totalOnly.currentProgress, 0);
    expect(totalOnly.totalProgress, 80);
    final valid = await repository.create(const ReadingDraft(
      title: '三体',
      progressUnit: ReadingUnit.chapter,
      currentProgress: 12,
      totalProgress: 40,
    ));
    expect(valid.currentProgress, 12);
    expect(
      () => repository.create(const ReadingDraft(
        title: '进度反转',
        currentProgress: 50,
        totalProgress: 40,
      )),
      throwsRangeError,
    );
  });

  test('updates all reading metadata and soft deletes it', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = ReadingRepository(db);
    final row = await repository.create(const ReadingDraft(title: '旧标题'));
    final updated = await repository.update(
      row.id,
      const ReadingDraft(
        title: '新标题',
        author: '作者',
        readingType: ReadingType.novel,
        progressUnit: ReadingUnit.chapter,
        currentProgress: 8,
        totalProgress: 30,
        notes: '备注',
      ),
    );
    expect(updated.title, '新标题');
    expect(updated.readingType, 'NOVEL');
    expect(updated.progressUnit, 'CHAPTER');
    expect(updated.currentProgress, 8);
    await repository.delete(row.id);
    expect(await repository.list(), isEmpty);
  });
}
