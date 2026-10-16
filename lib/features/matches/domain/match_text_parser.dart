import 'package:lifehub/core/time/time_zone_resolver.dart';

import 'match_models.dart';

abstract final class MatchTextParser {
  static final _explicitDate = RegExp(
    r'(?<!\d)(?:(\d{4})[年./-])?(\d{1,2})[月./-](\d{1,2})日?(?!\d)',
  );
  static final _weekday = RegExp(
    r'(下周|本周|这周|周|星期|礼拜)\s*([一二三四五六日天1-7])(?:(?![A-Za-z\u4e00-\u9fff])|(?=凌晨|早上|上午|中午|下午|傍晚|晚上|今晚|明晚))',
  );
  static final _statusMarker = RegExp(r'(?:^|\s)(未开始|未开赛|延期|取消)(?=\s|$)');
  static final _broadcast = RegExp(
    r'CCTV\s*-?\s*\d+\+?|央视体育|腾讯体育|爱奇艺体育|咪咕(?:视频|体育)?|央视频|ESPN\d*|DAZN|TNT Sports',
    caseSensitive: false,
  );
  static MatchParseResult parse(
    String text, {
    required DateTime referenceDate,
    String defaultTimezoneId = 'Asia/Shanghai',
    String sourceType = MatchSources.screenshot,
    String? sourceLabel,
  }) {
    final drafts = <MatchDraft>[];
    final warnings = <String>[];
    DateTime? currentDate;
    (int, int)? currentTime;
    String? currentCompetition;
    final lines = text.replaceAll('\r\n', '\n').split('\n');

    for (final raw in lines) {
      final line = raw.replaceAll(RegExp(r'[^\S\t]+'), ' ').trim();
      if (line.isEmpty || _isNoise(line)) continue;
      final date = _findDate(line, referenceDate, warnings: warnings);
      if (date != null || _explicitDate.hasMatch(line)) {
        currentDate = date;
        currentTime = _findTime(line);
      }
      final hasFinishedMarker = RegExp(r'完场|已结束|进行中|比分直播').hasMatch(line);
      final teams = _findTeams(line);
      if (teams == null) {
        if (_isTimeHeading(line)) currentTime = _findTime(line);
        if (!_explicitDate.hasMatch(line) &&
            _looksLikeCompetition(line, date)) {
          currentCompetition = line;
        }
        continue;
      }
      if (hasFinishedMarker) continue;

      final time = _findTime(line) ?? currentTime;
      final explicitStatus = _explicitStatus(line);
      var (cleanA, cleanB, detectedComp) = _extractTeamsAndCompetition(
        teams.$1,
        teams.$2,
        line,
      );

      final rowComp = detectedComp ?? currentCompetition ?? '未命名赛事';
      final sport = _findSport(line) ?? _guessSportFromComp(rowComp) ?? '其他';
      final broadcast = _findBroadcast(line);
      if (sport == '其他') warnings.add('运动类型未能确定，请在预览中确认：$line');

      if (cleanA.isEmpty || cleanB.isEmpty) {
        warnings.add('无法识别参赛方：$line');
        continue;
      }
      if (currentDate == null) warnings.add('比赛缺少日期，需在预览中确认：$line');
      if (time == null) warnings.add('比赛缺少开始时间，需在预览中确认：$line');
      DateTime? start;
      if (currentDate != null && time != null) {
        try {
          start = TimeZoneResolver.resolveLocal(
            DateTime(
              currentDate.year,
              currentDate.month,
              currentDate.day,
              time.$1,
              time.$2,
            ),
            defaultTimezoneId,
          );
        } on FormatException {
          start = null;
        }
      }
      drafts.add(
        MatchDraft(
          sportType: sport,
          competition: rowComp,
          participantA: cleanA,
          participantB: cleanB,
          matchDate: currentDate,
          startAt: start,
          timezoneId: defaultTimezoneId,
          status: explicitStatus ?? MatchStatuses.scheduled,
          sourceType: sourceType,
          sourceLabel: sourceLabel,
          broadcast: broadcast,
          importFields: {
            if (broadcast != null) MatchImportField.broadcast,
            if (explicitStatus != null) MatchImportField.status,
            if (sourceLabel != null) MatchImportField.sourceLabel,
          },
        ),
      );
      currentTime = null;
    }
    if (lines.any((line) => line.trim().isNotEmpty)) {
      final blockDrafts = _parseMultiLineBlocks(
        lines,
        referenceDate: referenceDate,
        defaultTimezoneId: defaultTimezoneId,
        sourceType: sourceType,
        sourceLabel: sourceLabel,
        warnings: warnings,
      );
      for (final draft in blockDrafts) {
        if (!drafts.any(
          (existing) =>
              existing.matchDate == draft.matchDate &&
              existing.startAt == draft.startAt &&
              existing.participantA == draft.participantA &&
              existing.participantB == draft.participantB,
        )) {
          drafts.add(draft);
        }
      }
      if (drafts.isEmpty) warnings.add('未识别到包含双方参赛者的比赛行。');
    }
    return MatchParseResult(
      drafts: List.unmodifiable(drafts),
      warnings: List.unmodifiable(warnings.toSet()),
    );
  }

  static List<MatchDraft> _parseMultiLineBlocks(
    List<String> rawLines, {
    required DateTime referenceDate,
    required String defaultTimezoneId,
    required String sourceType,
    String? sourceLabel,
    required List<String> warnings,
  }) {
    final lines = rawLines
        .map((l) => l.replaceAll(RegExp(r'[^\S\t]+'), ' ').trim())
        .where((l) => l.isNotEmpty && !_isNoise(l))
        .toList();

    final drafts = <MatchDraft>[];
    String? currentComp;
    DateTime? currentDate;

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final date = _findDate(line, referenceDate);
      if (date != null || _explicitDate.hasMatch(line)) currentDate = date;
      if (date != null) {
        final compParts = <String>[];
        var j = i - 1;
        while (j >= 0) {
          final prev = lines[j];
          if (_findDate(prev, referenceDate) != null ||
              _findTime(prev) != null ||
              _findTeams(prev) != null ||
              _isPunctuationOrNoise(prev) ||
              RegExp(r'^\d{4}[/.-]\d{1,2}$').hasMatch(prev)) {
            break;
          }
          compParts.insert(0, prev);
          if (compParts.length >= 2) break;
          j--;
        }
        if (compParts.isNotEmpty) currentComp = compParts.join(' ');
      }
      if (_findTeams(line) != null || RegExp(r'完场|已结束|进行中').hasMatch(line)) {
        i++;
        continue;
      }

      if (currentDate != null && (date != null || _isTimeHeading(line))) {
        final rowComp = currentComp ?? '未命名赛事';
        final sport = _guessSportFromComp(rowComp) ?? '其他';

        (int, int)? time = _findTime(line);
        String? broadcast = _findBroadcast(line);
        final teams = <String>[];
        var k = i + 1;
        while (k < lines.length && teams.length < 2 && k <= i + 8) {
          final nextLine = lines[k];
          final nextDate = _findDate(nextLine, referenceDate);
          if (nextDate != null ||
              _findTeams(nextLine) != null ||
              RegExp(r'完场|已结束|进行中').hasMatch(nextLine)) {
            break;
          }

          final nextTime = _findTime(nextLine);
          if (nextTime != null && teams.isNotEmpty) break;
          broadcast ??= _findBroadcast(nextLine);
          if (nextTime != null && teams.isEmpty) {
            time = nextTime;
            final matchTime = RegExp(
              r'(?<!\d)(\d{1,2})[:：](\d{2})(?!\d)',
            ).firstMatch(nextLine);
            if (matchTime != null) {
              final after = nextLine.substring(matchTime.end).trim();
              final cleanAfter = _cleanTeamName(after);
              if (cleanAfter.isNotEmpty && !_isPunctuationOrNoise(cleanAfter)) {
                teams.add(cleanAfter);
              }
            }
          } else if (!_isPunctuationOrNoise(nextLine)) {
            final clean = _cleanTeamName(nextLine);
            if (clean.isNotEmpty &&
                _findTime(clean) == null &&
                _findDate(clean, referenceDate) == null &&
                !RegExp(r'^\d{4}[/.-]\d{1,2}$').hasMatch(clean)) {
              teams.add(clean);
            }
          }
          k++;
        }

        if (teams.length >= 2) {
          if (sport == '其他') {
            warnings.add('运动类型未能确定，请在预览中确认：${teams.join(' vs ')}');
          }
          final explicitStatus = _explicitStatus(
            lines.sublist(i, k).join('\n'),
          );
          DateTime? start;
          if (time != null) {
            try {
              start = TimeZoneResolver.resolveLocal(
                DateTime(
                  currentDate.year,
                  currentDate.month,
                  currentDate.day,
                  time.$1,
                  time.$2,
                ),
                defaultTimezoneId,
              );
            } on FormatException {
              start = null;
            }
          }

          drafts.add(
            MatchDraft(
              sportType: sport,
              competition: rowComp,
              participantA: teams[0],
              participantB: teams[1],
              matchDate: currentDate,
              startAt: start,
              timezoneId: defaultTimezoneId,
              status: explicitStatus ?? MatchStatuses.scheduled,
              sourceType: sourceType,
              sourceLabel: sourceLabel,
              broadcast: broadcast,
              importFields: {
                if (broadcast != null) MatchImportField.broadcast,
                if (explicitStatus != null) MatchImportField.status,
                if (sourceLabel != null) MatchImportField.sourceLabel,
              },
            ),
          );
          i = k - 1;
        }
      }
      i++;
    }

    return drafts;
  }

  static bool _isPunctuationOrNoise(String line) =>
      RegExp(r'^[-\s—－:：·•\d/]+$').hasMatch(line) &&
      !RegExp(r'\d{1,2}[:：]\d{2}').hasMatch(line);

  static String _cleanTeamName(String line) {
    return line
        .replaceAll(RegExp(r'(?:直播平台|转播平台)\s*[:：]\s*[^，,;；]+'), '')
        .replaceAll(_broadcast, '')
        .replaceAll(RegExp(r'(?:直播|转播)\s*$'), '')
        .replaceAll(RegExp(r'[\s\-—－:：]+$'), '')
        .replaceAll(RegExp(r'^[\s\-—－:：]+'), '')
        .replaceAll(RegExp(r'\b(?:完场|未开始|进行中|延期|取消)\b'), '')
        .replaceAll(_statusMarker, '')
        .trim();
  }

  static String? _explicitStatus(String line) =>
      switch (_statusMarker.firstMatch(line)?.group(1)) {
        '取消' => MatchStatuses.cancelled,
        '延期' => MatchStatuses.postponed,
        '未开始' || '未开赛' => MatchStatuses.scheduled,
        _ => null,
      };

  static bool _isNoise(String line) {
    if (RegExp(r'赔率|预测|积分榜|广告|下载|盘口', caseSensitive: false).hasMatch(line)) {
      return true;
    }
    final hasFixture =
        RegExp(r'vs\.?|对阵|对|\s[-—－]\s', caseSensitive: false).hasMatch(line) ||
        _explicitDate.hasMatch(line) ||
        _findTime(line) != null;
    return !hasFixture && RegExp(r'直播|推荐|关注|收藏').hasMatch(line);
  }

  static String? _findBroadcast(String line) {
    final named = _broadcast.firstMatch(line);
    if (named != null) return named.group(0)!.replaceAll(RegExp(r'\s+'), '');
    return RegExp(
      r'(?:直播平台|转播平台)\s*[:：]\s*([^，,;；]+)',
    ).firstMatch(line)?.group(1)?.trim();
  }

  static bool _isTimeHeading(String line) {
    if (_findTime(line) == null) return false;
    return line
        .replaceAll(_broadcast, '')
        .replaceAll(RegExp(r'(?:直播|转播)\s*$'), '')
        .replaceAll(_explicitDate, '')
        .replaceAll(_weekday, '')
        .replaceAll(RegExp(r'^(?:比赛|开始|开赛)?时间\s*[:：]?'), '')
        .replaceAll(RegExp(r'[\s\d:：上午下午晚上中午凌晨早间晚间点时分半]'), '')
        .isEmpty;
  }

  static bool _looksLikeCompetition(String line, DateTime? date) {
    if (date != null || _findTime(line) != null) return false;
    if (line.length > 60) return false;
    return !RegExp(r'^\d+$').hasMatch(line);
  }

  static String? _findSport(String line) {
    for (final sport in const [
      '足球',
      '篮球',
      '网球',
      '电竞',
      '排球',
      '棒球',
      '羽毛球',
      '乒乓球',
    ]) {
      if (line.contains(sport)) return sport;
    }
    return null;
  }

  static String? _guessSportFromComp(String comp) {
    if (RegExp(r'NBA|CBA|篮球|WNBA', caseSensitive: false).hasMatch(comp)) {
      return '篮球';
    }
    if (RegExp(
      r'英超|西甲|德甲|意甲|法甲|欧冠|中超|欧联|世界杯|亚洲杯|欧洲杯|足球|中国之队|国际友谊|男足|女足',
    ).hasMatch(comp)) {
      return '足球';
    }
    if (RegExp(
      r'LPL|LCK|KPL|S\d+|MSI|TI\d+|电竞',
      caseSensitive: false,
    ).hasMatch(comp)) {
      return '电竞';
    }
    if (RegExp(
      r'温网|美网|法网|澳网|中网|ATP|WTA|网球',
      caseSensitive: false,
    ).hasMatch(comp)) {
      return '网球';
    }
    if (RegExp(r'羽毛球|BWF|汤姆斯杯|尤伯杯', caseSensitive: false).hasMatch(comp)) {
      return '羽毛球';
    }
    if (RegExp(r'乒乓球|WTT', caseSensitive: false).hasMatch(comp)) return '乒乓球';
    if (RegExp(r'排球|FIVB', caseSensitive: false).hasMatch(comp)) return '排球';
    return null;
  }

  static DateTime? _findDate(
    String line,
    DateTime referenceDate, {
    List<String>? warnings,
  }) {
    final explicit = _explicitDate.firstMatch(line);
    final weekMatch = _weekday.firstMatch(line);
    if (explicit != null) {
      if (explicit.group(1) == null) {
        warnings?.add('日期未包含年份，暂按 ${referenceDate.year} 年解析，请在预览中确认：$line');
      }
      final date = _safeDate(
        explicit.group(1) == null
            ? referenceDate.year
            : int.parse(explicit.group(1)!),
        int.parse(explicit.group(2)!),
        int.parse(explicit.group(3)!),
      );
      if (date == null) {
        warnings?.add('日期无效，请在预览中确认：$line');
      } else if (weekMatch != null &&
          date.weekday != _weekdayNumber(weekMatch.group(2)!)) {
        warnings?.add('日期与星期不一致，已保留明确日期，请在预览中确认：$line');
      }
      return date;
    }

    // 相对日期按最长词优先，避免“大后天”被“后天”截获。
    if (RegExp(r'大后天').hasMatch(line)) {
      return _safeDate(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      )?.add(const Duration(days: 3));
    }
    if (RegExp(r'今天|今晚|今日').hasMatch(line)) {
      return DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      );
    }
    if (RegExp(r'明天|明晚|明日').hasMatch(line)) {
      return _safeDate(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      )?.add(const Duration(days: 1));
    }
    if (RegExp(r'后天|后日').hasMatch(line)) {
      return _safeDate(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      )?.add(const Duration(days: 2));
    }
    if (weekMatch != null) {
      final prefix = weekMatch.group(1)!;
      final targetWeekday = _weekdayNumber(weekMatch.group(2)!);
      var diff = targetWeekday - referenceDate.weekday;
      if (prefix == '下周') {
        diff += 7;
      } else if (prefix != '本周' && prefix != '这周' && diff < 0) {
        diff += 7;
      }
      return DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
      ).add(Duration(days: diff));
    }

    return null;
  }

  static int _weekdayNumber(String value) => switch (value) {
    '一' || '1' => DateTime.monday,
    '二' || '2' => DateTime.tuesday,
    '三' || '3' => DateTime.wednesday,
    '四' || '4' => DateTime.thursday,
    '五' || '5' => DateTime.friday,
    '六' || '6' => DateTime.saturday,
    '日' || '天' || '7' => DateTime.sunday,
    _ => throw ArgumentError.value(value, 'weekday'),
  };

  static DateTime? _safeDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    return value.year == year && value.month == month && value.day == day
        ? value
        : null;
  }

  static (int, int)? _findTime(String line) {
    final standard = RegExp(
      r'(?<!\d)(\d{1,2})[:：](\d{2})(?!\d)',
    ).firstMatch(line);
    if (standard != null) {
      final hour = int.parse(standard.group(1)!);
      final minute = int.parse(standard.group(2)!);
      if (hour <= 23 && minute <= 59) return (hour, minute);
    }

    final chinese = RegExp(
      r'(凌晨|早上|上午|中午|下午|傍晚|晚上|今晚|明晚)?\s*(\d{1,2})\s*[点时]\s*(?:(\d{1,2})分?|半)?',
    ).firstMatch(line);
    if (chinese != null) {
      final period = chinese.group(1);
      var hour = int.parse(chinese.group(2)!);
      var minute = 0;
      if (chinese.group(3) != null) {
        minute = int.parse(chinese.group(3)!);
      } else if (chinese.group(0)!.contains('半')) {
        minute = 30;
      }
      if (period != null) {
        if (['下午', '傍晚', '晚上', '今晚', '明晚'].contains(period) && hour < 12) {
          hour += 12;
        } else if (period == '凌晨' && hour == 12) {
          hour = 0;
        }
      }
      if (hour <= 23 && minute <= 59) {
        return (hour, minute);
      }
    }
    return null;
  }

  static (String, String)? _findTeams(String line) {
    final match = RegExp(
      r'(.+?)\s*(?:vs\.?|VS\.?|对阵|对)\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) return (match.group(1)!, match.group(2)!);
    if (line.contains('\t')) {
      final names = line
          .split('\t')
          .map((part) => part.trim())
          .where(
            (part) =>
                RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(part) &&
                !_explicitDate.hasMatch(part) &&
                !RegExp(
                  r'^(?:(?:下周|本周|这周|周|星期|礼拜)[一二三四五六日天1-7]|今天|明天|后天)$',
                ).hasMatch(part) &&
                _findTime(part) == null &&
                _findSport(part) != part &&
                !RegExp(
                  r'^(?:NBA|WNBA|CBA|英超|西甲|德甲|意甲|法甲|欧冠|欧联|亚冠|中超|足协杯|世界杯|欧洲杯|亚洲杯|国际友谊赛?|LPL|LCK|KPL|MSI|温网|美网|法网|澳网|中网|ATP|WTA|BWF|WTT|FIVB)$',
                  caseSensitive: false,
                ).hasMatch(part) &&
                _findBroadcast(part) == null &&
                !_isPunctuationOrNoise(part) &&
                !RegExp(
                  r'^(赛事|联赛|赛季|阶段|轮次|比赛|日期|时间|参赛|主队|客队|排名|球队|积分|场地|直播|转播)',
                ).hasMatch(part),
          )
          .toList();
      if (names.length == 2) return (names[0], names[1]);
    }
    final spacedDash = RegExp(r'(.+?)\s+[-—－]\s+(.+)$').firstMatch(line);
    return spacedDash == null
        ? null
        : (spacedDash.group(1)!, spacedDash.group(2)!);
  }

  static (String, String, String?) _extractTeamsAndCompetition(
    String rawA,
    String rawB,
    String fullLine,
  ) {
    var a = _cleanParticipant(rawA);
    var b = _cleanParticipant(rawB);
    String? detectedComp;

    // 尝试从括号中提取赛事：[英超] 阿森纳 vs 切尔西 或 【NBA】湖人 vs 勇士
    final bracket = RegExp(r'[【\[](.+?)[】\]]').firstMatch(fullLine);
    if (bracket != null) {
      detectedComp = bracket.group(1)!.trim();
      a = a.replaceAll(bracket.group(0)!, '').trim();
      b = b.replaceAll(bracket.group(0)!, '').trim();
    }

    // 常见赛事关键字智能分离：英超 阿森纳 vs 切尔西 -> 赛事: 英超, 队A: 阿森纳
    final compKeyword = RegExp(
      r'^(英超|西甲|德甲|意甲|法甲|欧冠|欧联|亚冠|中超|足协杯|世界杯|欧洲杯|NBA|CBA|LPL|LCK|KPL|温网|美网|法网|澳网|中网)(?:[第\d\sA-Za-z轮次组常规季后赛]*)\s+',
      caseSensitive: false,
    ).firstMatch(a);
    if (compKeyword != null) {
      detectedComp ??= compKeyword.group(0)!.trim();
      a = a.substring(compKeyword.group(0)!.length).trim();
    }

    return (a, b, detectedComp);
  }

  static String _cleanParticipant(String value) {
    return value
        .replaceAll(RegExp(r'(?:直播平台|转播平台)\s*[:：]\s*[^，,;；]+'), '')
        .replaceAll(_broadcast, '')
        .replaceAll(RegExp(r'(?:直播|转播)\s*$'), '')
        .replaceAll(
          RegExp(r'^.*?(?:\d{1,2}[:：]\d{2}|\d{1,2}\s*[点时](?:\d{1,2}分?|半)?)\s*'),
          '',
        )
        .replaceAll(RegExp(r'^(?:足球|篮球|网球|电竞|排球|棒球|羽毛球|乒乓球)[:：\s]*'), '')
        .replaceAll(
          RegExp(
            r'^(?:今天|今晚|明天|明晚|后天)\s*|^(?:周[一二三四五六日天]|星期[一二三四五六日天])(?:\s+|$)',
          ),
          '',
        )
        .replaceAll(RegExp(r'^\[.*?\]\s*'), '')
        .replaceAll(RegExp(r'【.*?】\s*'), '')
        .replaceAll(RegExp(r'\b(?:完场|未开始|延期|取消)\b'), '')
        .replaceAll(_statusMarker, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
