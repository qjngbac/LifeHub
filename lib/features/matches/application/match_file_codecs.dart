import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/core/time/time_zone_resolver.dart';
import 'package:lifehub/features/calendar/domain/ics_codec.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';

abstract final class MatchFileCodecs {
  static const maxImportBytes = 5 * 1024 * 1024;
  static const maxImportRows = 500;

  static const csvHeaders = <String>[
    '运动类型',
    '赛事',
    '赛季',
    '阶段或轮次',
    '参赛方A',
    '参赛方B',
    '比赛日期',
    '开始时间',
    '时区',
    '场地',
    '直播平台',
    '备注',
  ];

  static const _csvImportFields = <String, MatchImportField>{
    '赛季': MatchImportField.season,
    '阶段或轮次': MatchImportField.stageOrRound,
    '比分A': MatchImportField.scoreA,
    '比分B': MatchImportField.scoreB,
    '结果说明': MatchImportField.scoreDetail,
    '状态': MatchImportField.status,
    '场地': MatchImportField.venue,
    '直播平台': MatchImportField.broadcast,
    '备注': MatchImportField.notes,
    '收藏': MatchImportField.favorite,
  };

  static List<MatchDraft> decodeCsv(
    String source, {
    DateTime? referenceDate,
    String defaultTimezoneId = 'Asia/Shanghai',
  }) {
    _checkSize(source);
    final rows = csv.decode(source);
    if (rows.isEmpty) return const [];
    if (rows.length - 1 > maxImportRows) {
      throw const FormatException('CSV 比赛记录超过 500 条限制。');
    }
    final header = rows.first.map((value) => value.toString().trim()).toList();
    final index = <String, int>{
      for (var i = 0; i < header.length; i++) header[i]: i,
    };
    String? value(List<dynamic> row, String key) {
      final at = index[key];
      if (at == null || at >= row.length) return null;
      final text = row[at].toString().trim();
      return text.isEmpty ? null : text;
    }

    final drafts = <MatchDraft>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.toString().trim().isEmpty)) continue;
      final fields = <MatchImportField>{
        for (final entry in _csvImportFields.entries)
          if (index[entry.key] != null && index[entry.key]! < row.length)
            entry.value,
      };
      final date = _parseDate(value(row, '比赛日期'), referenceDate);
      final time = value(row, '开始时间');
      final timezoneId = value(row, '时区') ?? defaultTimezoneId;
      DateTime? startAt;
      if (date != null && time != null) {
        final match = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(time);
        if (match != null) {
          final hour = int.parse(match.group(1)!);
          final minute = int.parse(match.group(2)!);
          if (hour < 24 && minute < 60) {
            try {
              startAt = TimeZoneResolver.resolveLocal(
                DateTime(date.year, date.month, date.day, hour, minute),
                timezoneId,
              );
            } on FormatException {
              startAt = null;
            }
          }
        }
      }
      drafts.add(MatchDraft(
        sportType: value(row, '运动类型'),
        competition: value(row, '赛事'),
        season: value(row, '赛季'),
        stageOrRound: value(row, '阶段或轮次'),
        participantA: value(row, '参赛方A'),
        participantB: value(row, '参赛方B'),
        matchDate: date,
        startAt: startAt,
        timezoneId: timezoneId,
        scoreA: _parseScore(value(row, '比分A')),
        scoreB: _parseScore(value(row, '比分B')),
        scoreDetail: value(row, '结果说明'),
        status: fields.contains(MatchImportField.status)
            ? value(row, '状态') ?? ''
            : MatchStatuses.scheduled,
        favorite: _parseFavorite(value(row, '收藏')),
        venue: value(row, '场地'),
        broadcast: value(row, '直播平台'),
        notes: value(row, '备注'),
        sourceType: MatchSources.csv,
        importFields: fields,
      ));
    }
    return List.unmodifiable(drafts);
  }

  static List<MatchDraft> decodeIcs(
    String source, {
    DateTime? referenceDate,
    String defaultTimezoneId = 'Asia/Shanghai',
  }) {
    return decodeIcsWithWarnings(
      source,
      referenceDate: referenceDate,
      defaultTimezoneId: defaultTimezoneId,
    ).drafts;
  }

  static MatchParseResult decodeIcsWithWarnings(
    String source, {
    DateTime? referenceDate,
    String defaultTimezoneId = 'Asia/Shanghai',
  }) {
    _checkSize(source);
    final decoded = IcsCodec.decode(
      source,
      defaultTimezoneId: defaultTimezoneId,
    );
    final drafts = <MatchDraft>[];
    final properties = _icsPropertiesByUid(source);
    for (final item in decoded.items) {
      final supplied = properties[item.uid] ?? const <String>{};
      final fields = <MatchImportField>{
        MatchImportField.sourceKey,
        MatchImportField.sourceLabel,
        if (item.location != null || supplied.contains('LOCATION'))
          MatchImportField.venue,
        if (item.notes != null || supplied.contains('DESCRIPTION'))
          MatchImportField.notes,
      };
      final timezoneId = item.timezoneId ?? defaultTimezoneId;
      final local = item.allDay
          ? item.start
          : TimeZoneResolver.atInstant(item.start, timezoneId);
      final parsed = MatchTextParser.parse(
        '${local.year}-${local.month}-${local.day}\n${_unescapeTitle(item.title)}',
        referenceDate: referenceDate ?? local,
        defaultTimezoneId: defaultTimezoneId,
        sourceType: MatchSources.ics,
        sourceLabel: 'ICS',
      );
      if (parsed.drafts.isEmpty) {
        drafts.add(MatchDraft(
          competition: '未命名赛事',
          sportType: '其他',
          participantA: null,
          participantB: null,
          matchDate: DateTime(local.year, local.month, local.day),
          startAt: item.allDay ? null : item.start.toUtc(),
          timezoneId: item.allDay ? null : timezoneId,
          venue: item.location,
          notes: item.notes,
          sourceType: MatchSources.ics,
          sourceKey: item.uid,
          sourceLabel: 'ICS',
          importFields: fields,
        ));
      } else {
        drafts.add(parsed.drafts.first.copyWith(
          matchDate: DateTime(local.year, local.month, local.day),
          startAt: item.allDay ? null : item.start.toUtc(),
          timezoneId: item.allDay ? null : timezoneId,
          venue: item.location,
          notes: item.notes,
          sourceKey: item.uid,
          importFields: {
            ...fields,
            ...?parsed.drafts.first.importFields,
          },
        ));
      }
    }
    if (drafts.length > maxImportRows) {
      throw const FormatException('ICS 比赛记录超过 500 条限制。');
    }
    return MatchParseResult(
      drafts: List.unmodifiable(drafts),
      warnings: decoded.warnings,
    );
  }

  static String encodeCsvTemplate() {
    return csv.encode([
      csvHeaders,
      [
        '足球',
        '英超',
        '2026/27',
        '第4轮',
        '阿森纳',
        '切尔西',
        '2026-09-07',
        '20:00',
        'Asia/Shanghai',
        '某体育场',
        '某平台',
        '',
      ],
    ]);
  }

  static String encodeCsv(List<MatchRecordEntry> records) {
    final rows = <List<dynamic>>[csvHeaders];
    for (final row in records) {
      final date = DateKeys.fromLocalDateKey(row.matchDate);
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      var timeStr = '';
      if (row.startAt != null) {
        final startLocal = TimeZoneResolver.atInstant(
          DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true),
          row.timezoneId ?? 'Asia/Shanghai',
        );
        timeStr = DateFormat('HH:mm').format(startLocal);
      }
      rows.add([
        row.sportType,
        row.competition,
        row.season ?? '',
        row.stageOrRound ?? '',
        row.participantA,
        row.participantB,
        dateStr,
        timeStr,
        row.timezoneId ?? 'Asia/Shanghai',
        row.venue ?? '',
        row.broadcast ?? '',
        row.notes ?? '',
      ]);
    }
    return csv.encode(rows);
  }

  static String encodeIcs(List<MatchRecordEntry> records) {
    final items = <CalendarExchangeItem>[];
    for (final row in records) {
      final titleParts = [
        row.competition,
        if (row.stageOrRound != null && row.stageOrRound!.trim().isNotEmpty)
          row.stageOrRound!.trim(),
      ];
      final title =
          '${titleParts.join(' ')}: ${row.participantA} vs ${row.participantB}';
      final DateTime start;
      final DateTime end;
      final bool allDay;
      if (row.startAt != null) {
        start = DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true)
            .toLocal();
        end = start.add(const Duration(hours: 2));
        allDay = false;
      } else {
        final d = DateKeys.fromLocalDateKey(row.matchDate);
        start = DateTime(d.year, d.month, d.day);
        end = start.add(const Duration(days: 1));
        allDay = true;
      }
      final notesList = [
        if (row.scoreA != null && row.scoreB != null)
          '比分: ${row.participantA} ${row.scoreA} : ${row.scoreB} ${row.participantB}',
        if (row.scoreDetail != null && row.scoreDetail!.trim().isNotEmpty)
          '说明: ${row.scoreDetail!.trim()}',
        if (row.broadcast != null && row.broadcast!.trim().isNotEmpty)
          '直播: ${row.broadcast!.trim()}',
        if (row.notes != null && row.notes!.trim().isNotEmpty)
          row.notes!.trim(),
      ];
      items.add(CalendarExchangeItem(
        uid: row.sourceKey ?? 'match-${row.id}',
        title: title,
        start: start,
        end: end,
        allDay: allDay,
        location: row.venue,
        notes: notesList.isEmpty ? null : notesList.join('\n'),
      ));
    }
    return IcsCodec.encode(items);
  }

  static void _checkSize(String source) {
    if (utf8.encode(source).length > maxImportBytes) {
      throw const FormatException('比赛导入文件超过 5 MB 限制。');
    }
  }

  static int? _parseScore(String? value) {
    if (value == null) return null;
    final score = int.tryParse(value);
    if (score == null) throw FormatException('比分必须是整数：$value');
    return score;
  }

  static bool _parseFavorite(String? value) {
    return switch (value?.toLowerCase()) {
      null || 'false' || '0' || '否' => false,
      'true' || '1' || '是' => true,
      _ => throw FormatException('收藏必须填写 true/false、1/0 或 是/否：$value'),
    };
  }

  static Map<String, Set<String>> _icsPropertiesByUid(String source) {
    final unfolded = source.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final properties = <String, Set<String>>{};
    String? uid;
    var names = <String>{};
    for (final line in unfolded.replaceAll('\r\n', '\n').split('\n')) {
      if (line == 'BEGIN:VEVENT') {
        uid = null;
        names = <String>{};
      } else if (line == 'END:VEVENT') {
        if (uid != null) properties.putIfAbsent(uid, () => names);
      } else {
        final separator = line.indexOf(':');
        if (separator < 1) continue;
        final name = line.substring(0, separator).split(';').first;
        names.add(name);
        if (name == 'UID') {
          uid = line
              .substring(separator + 1)
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\,', ',')
              .replaceAll(r'\;', ';')
              .replaceAll(r'\\', '\\');
        }
      }
    }
    return properties;
  }

  static DateTime? _parseDate(String? value, DateTime? referenceDate) {
    if (value == null || value.trim().isEmpty) return null;
    final full = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$')
        .firstMatch(value.trim());
    if (full == null) return null;
    final year = int.parse(full.group(1)!);
    final month = int.parse(full.group(2)!);
    final day = int.parse(full.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String _unescapeTitle(String title) => title.replaceAll('：', ' ');
}
