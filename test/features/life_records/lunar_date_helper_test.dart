import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/lunar_date_helper.dart';

void main() {
  group('LunarDateHelper & LunarInfo', () {
    test('converts lunar date to solar accurately', () {
      // 2026年农历八月十五（中秋节）对应公历 2026年9月25日
      final solar = LunarDateHelper.lunarToSolar(
        year: 2026,
        month: 8,
        day: 15,
        isLeapMonth: false,
      );
      expect(solar.year, equals(2026));
      expect(solar.month, equals(9));
      expect(solar.day, equals(25));
    });

    test('serializes and deserializes LunarInfo with metadata json', () {
      const info = LunarInfo(
        isLunar: true,
        lunarYear: 2026,
        lunarMonth: 8,
        lunarDay: 15,
        isLeapMonth: false,
      );
      final json = info.toMetadataJson();
      final restored = LunarInfo.fromMetadata(json);

      expect(restored.isLunar, isTrue);
      expect(restored.lunarYear, equals(2026));
      expect(restored.lunarMonth, equals(8));
      expect(restored.lunarDay, equals(15));
      expect(restored.isLeapMonth, isFalse);
      expect(restored.chineseMonthName, equals('八月'));
      expect(restored.chineseDayName, equals('十五'));
      expect(restored.fullLunarString, equals('农历 八月十五'));
    });

    test('calculates next lunar occurrence for yearly recurring anniversary', () {
      // 农历八月十五
      // 2026年9月1日（中秋前）
      final nextBefore = LunarDateHelper.nextLunarOccurrence(
        month: 8,
        day: 15,
        isLeapMonth: false,
        from: DateTime(2026, 9, 1),
        repeatYearly: true,
      );
      expect(nextBefore, equals(DateTime(2026, 9, 25)));

      // 2026年10月8日（中秋已过，下一次应为2027年农历八月十五）
      final nextAfter = LunarDateHelper.nextLunarOccurrence(
        month: 8,
        day: 15,
        isLeapMonth: false,
        from: DateTime(2026, 10, 8),
        repeatYearly: true,
      );
      // 2027年农历八月十五对应公历 2027年9月15日
      expect(nextAfter, equals(DateTime(2027, 9, 15)));
    });

    test('detects leap months properly', () {
      // 2025年有闰六月
      expect(LunarDateHelper.getLeapMonthInYear(2025), equals(6));
      // 2026年无闰月
      expect(LunarDateHelper.getLeapMonthInYear(2026), equals(0));
    });

    test('generates lunar summary for solar dates', () {
      final summary = LunarDateHelper.getLunarSummary(DateTime(2026, 9, 25));
      expect(summary, contains('八月十五'));
      expect(summary, contains('中秋节'));
    });
  });

  group('AnniversaryRepository Lunar Integration', () {
    test('creates and retrieves lunar anniversary entry', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repo = AnniversaryRepository(database);

      final entry = await repo.create(AnniversaryDraft(
        title: '妈妈农历生日',
        date: DateTime(2026, 9, 25),
        isLunar: true,
        lunarYear: 1968,
        lunarMonth: 8,
        lunarDay: 15,
        repeatYearly: true,
        category: 'BIRTHDAY',
      ));

      final lunarInfo = LunarInfo.fromMetadata(entry.metadata);
      expect(lunarInfo.isLunar, isTrue);
      expect(lunarInfo.lunarMonth, equals(8));
      expect(lunarInfo.lunarDay, equals(15));
      expect(lunarInfo.fullLunarString, equals('农历 八月十五'));

      // 计算距离2026-10-08的天数
      final days = repo.daysUntil(entry, DateTime(2026, 10, 8));
      expect(days, equals(DateTime(2027, 9, 15).difference(DateTime(2026, 10, 8)).inDays));
    });
  });
}
