import 'dart:convert';
import 'package:lunar/lunar.dart';

/// 农历（阴历）信息模型
class LunarInfo {
  const LunarInfo({
    required this.isLunar,
    this.lunarYear,
    this.lunarMonth,
    this.lunarDay,
    this.isLeapMonth = false,
  });

  final bool isLunar;
  final int? lunarYear;
  final int? lunarMonth;
  final int? lunarDay;
  final bool isLeapMonth;

  static const List<String> monthNames = [
    '正月',
    '二月',
    '三月',
    '四月',
    '五月',
    '六月',
    '七月',
    '八月',
    '九月',
    '十月',
    '冬月',
    '腊月',
  ];

  static const List<String> dayNames = [
    '初一',
    '初二',
    '初三',
    '初四',
    '初五',
    '初六',
    '初七',
    '初八',
    '初九',
    '初十',
    '十一',
    '十二',
    '十三',
    '十四',
    '十五',
    '十六',
    '十七',
    '十八',
    '十九',
    '二十',
    '廿一',
    '廿二',
    '廿三',
    '廿四',
    '廿五',
    '廿六',
    '廿七',
    '廿八',
    '廿九',
    '三十',
  ];

  String get chineseMonthName {
    if (lunarMonth == null || lunarMonth! < 1 || lunarMonth! > 12) return '';
    final base = monthNames[lunarMonth! - 1];
    return isLeapMonth ? '闰$base' : base;
  }

  String get chineseDayName {
    if (lunarDay == null || lunarDay! < 1 || lunarDay! > 30) return '';
    return dayNames[lunarDay! - 1];
  }

  String get fullLunarString {
    if (!isLunar || lunarMonth == null || lunarDay == null) return '';
    return '农历 $chineseMonthName$chineseDayName';
  }

  static LunarInfo fromMetadata(String? metadata) {
    if (metadata == null || metadata.trim().isEmpty) {
      return const LunarInfo(isLunar: false);
    }
    try {
      final parsed = jsonDecode(metadata);
      if (parsed is Map) {
        final isLunar =
            parsed['isLunar'] == true || parsed['calendar'] == 'LUNAR';
        if (!isLunar) return const LunarInfo(isLunar: false);
        return LunarInfo(
          isLunar: true,
          lunarYear: parsed['lunarYear'] as int?,
          lunarMonth: parsed['lunarMonth'] as int?,
          lunarDay: parsed['lunarDay'] as int?,
          isLeapMonth: parsed['isLeapMonth'] == true,
        );
      }
    } catch (_) {}
    return const LunarInfo(isLunar: false);
  }

  String toMetadataJson([String? existingMetadata]) {
    Map<String, dynamic> map = {};
    if (existingMetadata != null && existingMetadata.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(existingMetadata);
        if (parsed is Map<String, dynamic>) map = Map.from(parsed);
      } catch (_) {}
    }
    if (isLunar) {
      map['isLunar'] = true;
      map['calendar'] = 'LUNAR';
      map['lunarYear'] = lunarYear;
      map['lunarMonth'] = lunarMonth;
      map['lunarDay'] = lunarDay;
      map['isLeapMonth'] = isLeapMonth;
    } else {
      map.remove('isLunar');
      map.remove('calendar');
      map.remove('lunarYear');
      map.remove('lunarMonth');
      map.remove('lunarDay');
      map.remove('isLeapMonth');
    }
    return jsonEncode(map);
  }
}

/// 农历历法与转换工具类
class LunarDateHelper {
  LunarDateHelper._();

  /// 将公历日期转为 Lunar 对象
  static Lunar solarToLunar(DateTime solar) => Lunar.fromDate(solar);

  /// 将农历（年、月、日、是否闰月）安全转为对应的公历日期
  static DateTime lunarToSolar({
    required int year,
    required int month,
    required int day,
    bool isLeapMonth = false,
  }) {
    final clampedMonth = month.clamp(1, 12);
    final clampedDay = day.clamp(1, 30);
    if (isLeapMonth) {
      try {
        final lunar = Lunar.fromYmd(year, -clampedMonth, clampedDay);
        final solar = lunar.getSolar();
        return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
      } catch (_) {
        // 当年若无该闰月，回退至平月（传统民俗通例）
      }
    }
    try {
      final lunar = Lunar.fromYmd(year, clampedMonth, clampedDay);
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      // 容错兜底：若该月只有29天（小月），自动吸附到29日
      final lunar = Lunar.fromYmd(year, clampedMonth, 29);
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    }
  }

  /// 计算下一次农历纪念日/倒数日对应的公历日期
  static DateTime nextLunarOccurrence({
    required int month,
    required int day,
    bool isLeapMonth = false,
    required DateTime from,
    required bool repeatYearly,
    int? originalYear,
  }) {
    final today = DateTime(from.year, from.month, from.day);
    if (!repeatYearly) {
      final targetYear = originalYear ?? from.year;
      return lunarToSolar(
        year: targetYear,
        month: month,
        day: day,
        isLeapMonth: isLeapMonth,
      );
    }

    var candidate = lunarToSolar(
      year: today.year,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
    );
    if (candidate.isBefore(today)) {
      candidate = lunarToSolar(
        year: today.year + 1,
        month: month,
        day: day,
        isLeapMonth: isLeapMonth,
      );
    }
    return candidate;
  }

  /// 获取公历日期对应的农历简述（如“农历八月廿八”或“农历八月十五 · 中秋节”）
  static String getLunarSummary(DateTime solar) {
    try {
      final lunar = Lunar.fromDate(solar);
      final festivals = lunar.getFestivals();
      final festText = festivals.isNotEmpty ? ' · ${festivals.first}' : '';
      return '农历 ${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}$festText';
    } catch (_) {
      return '';
    }
  }

  /// 查询指定年份的闰月月份（无闰月返回 0）
  static int getLeapMonthInYear(int year) {
    try {
      return LunarYear.fromYear(year).getLeapMonth();
    } catch (_) {
      return 0;
    }
  }
}
