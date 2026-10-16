import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/core/time/time_zone_resolver.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<MatchDraft?> showMatchDraftDialog(
  BuildContext context, {
  MatchRecordEntry? current,
  MatchDraft? initial,
  bool finished = false,
  MatchSuggestions? suggestions,
  String? lastSport,
}) async {
  assert(current == null || initial == null);
  final sport = TextEditingController(
    text: current?.sportType ?? initial?.sportType ?? lastSport ?? '足球',
  );
  final competition = TextEditingController(
    text: current?.competition ?? initial?.competition,
  );
  final season = TextEditingController(
    text: current?.season ?? initial?.season,
  );
  final stage = TextEditingController(
    text: current?.stageOrRound ?? initial?.stageOrRound,
  );
  final participantA = TextEditingController(
    text: current?.participantA ?? initial?.participantA,
  );
  final participantB = TextEditingController(
    text: current?.participantB ?? initial?.participantB,
  );
  final venue = TextEditingController(text: current?.venue ?? initial?.venue);
  final broadcast = TextEditingController(
    text: current?.broadcast ?? initial?.broadcast,
  );
  final notes = TextEditingController(text: current?.notes ?? initial?.notes);
  final scoreDetail = TextEditingController(
    text: current?.scoreDetail ?? initial?.scoreDetail,
  );
  final scoreA = TextEditingController(
    text: (current?.scoreA ?? initial?.scoreA)?.toString(),
  );
  final scoreB = TextEditingController(
    text: (current?.scoreB ?? initial?.scoreB)?.toString(),
  );
  final historical =
      finished ||
      current?.status == MatchStatuses.finished ||
      initial?.status == MatchStatuses.finished;
  var date = current == null
      ? initial?.matchDate ?? DateTime.now()
      : (() {
          final key = current.matchDate;
          return DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);
        })();
  final timezoneId =
      current?.timezoneId ?? initial?.timezoneId ?? 'Asia/Shanghai';
  final storedStart = current?.startAt == null
      ? initial?.startAt
      : DateTime.fromMillisecondsSinceEpoch(current!.startAt!, isUtc: true);
  DateTime? start = storedStart == null
      ? (historical ? null : DateTime(date.year, date.month, date.day, 20))
      : TimeZoneResolver.atInstant(storedStart, timezoneId);
  var status = historical
      ? MatchStatuses.finished
      : (current?.status ?? initial?.status ?? MatchStatuses.scheduled);
  String? formError;

  final matchRoute = DialogRoute<MatchDraft>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final currentCompChips =
            suggestions?.competitionsFor(sport.text) ?? const [];
        final currentPartChips =
            suggestions?.participantsFor(sport.text) ?? const [];

        return KeyboardSafeFormDialog(
          title: Text(
            current == null ? (historical ? '录入已结束比赛' : '添加未来比赛') : '编辑比赛',
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: sport,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '运动类型 *',
                  hintText: '例如：足球、篮球、网球、电竞',
                ),
              ),
              if (suggestions != null && suggestions.sportTypes.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in suggestions.sportTypes.take(8))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              s,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => sport.text = s);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: competition,
                decoration: const InputDecoration(
                  labelText: '赛事 *',
                  hintText: '例如：英超、中国之队锦标赛',
                ),
              ),
              if (currentCompChips.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in currentCompChips.take(6))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              c,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => competition.text = c);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: season,
                      decoration: const InputDecoration(labelText: '赛季'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: stage,
                      decoration: const InputDecoration(labelText: '阶段或轮次'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: participantA,
                      decoration: const InputDecoration(
                        label: Text(
                          '参赛方 A *',
                          softWrap: true,
                          maxLines: 2,
                          style: TextStyle(fontSize: 12),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '主客对调',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: () {
                      setState(() {
                        final temp = participantA.text;
                        participantA.text = participantB.text;
                        participantB.text = temp;
                      });
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: participantB,
                      decoration: const InputDecoration(
                        label: Text(
                          '参赛方 B *',
                          softWrap: true,
                          maxLines: 2,
                          style: TextStyle(fontSize: 12),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (currentPartChips.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in currentPartChips.take(8))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              p,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() {
                                if (participantA.text.trim().isEmpty) {
                                  participantA.text = p;
                                } else if (participantB.text.trim().isEmpty) {
                                  participantB.text = p;
                                } else {
                                  participantA.text = p;
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: date,
                        );
                        if (picked != null && context.mounted) {
                          setState(() {
                            date = picked;
                            if (start != null) {
                              start = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                start!.hour,
                                start!.minute,
                              );
                            }
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '比赛日期 *',
                          labelStyle: TextStyle(fontSize: 12),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          suffixIconConstraints: BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          suffixIcon: Icon(
                            Icons.calendar_today_outlined,
                            size: 20,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                DateFormat('yyyy-').format(date),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                DateFormat('MM-dd').format(date),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            start ??
                                DateTime(date.year, date.month, date.day, 20),
                          ),
                        );
                        if (picked != null && context.mounted) {
                          setState(
                            () => start = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              picked.hour,
                              picked.minute,
                            ),
                          );
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: historical ? '开始时间' : '开始时间 *',
                          labelStyle: const TextStyle(fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (historical && start != null)
                                IconButton(
                                  tooltip: '清除开始时间',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => setState(() => start = null),
                                ),
                              if (!historical || start == null)
                                const Icon(Icons.schedule_outlined, size: 20),
                            ],
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            start == null
                                ? '未设置'
                                : DateFormat('HH:mm').format(start!),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (historical ||
                  current?.status == MatchStatuses.pendingResult) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: scoreA,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '比分 A'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        ':',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: scoreB,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '比分 B'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scoreDetail,
                  decoration: const InputDecoration(
                    labelText: '结果说明',
                    hintText: '如加时/点球',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: venue,
                      decoration: const InputDecoration(labelText: '场地'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: broadcast,
                      decoration: const InputDecoration(labelText: '直播平台'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              if (current != null &&
                  !historical &&
                  current.status != MatchStatuses.pendingResult) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: const [
                    DropdownMenuItem(
                      value: MatchStatuses.scheduled,
                      child: Text('待开始'),
                    ),
                    DropdownMenuItem(
                      value: MatchStatuses.postponed,
                      child: Text('已延期'),
                    ),
                    DropdownMenuItem(
                      value: MatchStatuses.cancelled,
                      child: Text('已取消'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => status = value ?? status),
                ),
              ],
              if (formError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsedA = int.tryParse(scoreA.text.trim());
                final parsedB = int.tryParse(scoreB.text.trim());
                final value = MatchDraft(
                  sportType: sport.text,
                  competition: competition.text,
                  season: season.text,
                  stageOrRound: stage.text,
                  participantA: participantA.text,
                  participantB: participantB.text,
                  matchDate: date,
                  startAt: start == null
                      ? null
                      : TimeZoneResolver.resolveLocal(start!, timezoneId),
                  timezoneId: start == null ? null : timezoneId,
                  scoreA: parsedA,
                  scoreB: parsedB,
                  scoreDetail: scoreDetail.text,
                  status: historical ? MatchStatuses.finished : status,
                  venue: venue.text,
                  broadcast: broadcast.text,
                  notes: notes.text,
                  favorite: current?.favorite ?? initial?.favorite ?? false,
                  sourceType:
                      current?.sourceType ??
                      initial?.sourceType ??
                      MatchSources.manual,
                  sourceKey: current?.sourceKey ?? initial?.sourceKey,
                  sourceLabel: current?.sourceLabel ?? initial?.sourceLabel,
                  importFields: initial?.importFields == null
                      ? null
                      : {
                          for (final field in MatchImportField.values)
                            if ((field != MatchImportField.sourceKey &&
                                    field != MatchImportField.sourceLabel) ||
                                initial!.importFields!.contains(field))
                              field,
                        },
                );
                final errors = value
                    .validate(now: DateTime.now())
                    .where(
                      (issue) => issue.severity == MatchIssueSeverity.error,
                    )
                    .map((issue) => issue.message)
                    .toList();
                if (errors.isNotEmpty) {
                  setState(() => formError = errors.join('\n'));
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  final draft = await Navigator.of(
    context,
    rootNavigator: true,
  ).push(matchRoute);
  await matchRoute.completed;
  for (final controller in [
    sport,
    competition,
    season,
    stage,
    participantA,
    participantB,
    venue,
    broadcast,
    notes,
    scoreDetail,
    scoreA,
    scoreB,
  ]) {
    controller.dispose();
  }
  return draft;
}

Future<String?> showMatchImportChoice(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('手动添加未来比赛'),
            onTap: () => Navigator.pop(context, 'manual'),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('录入已结束比赛'),
            onTap: () => Navigator.pop(context, 'finished'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_outlined),
            title: const Text('从文本 / 剪贴板识别'),
            onTap: () => Navigator.pop(context, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('从截图识别'),
            onTap: () => Navigator.pop(context, 'screenshot'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导入 CSV / ICS'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ],
      ),
    ),
  );
}

Future<MatchParseResult?> showTextImportDialog(BuildContext context) async {
  String initialText = '';
  try {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip != null && clip.text != null && clip.text!.trim().isNotEmpty) {
      initialText = clip.text!.trim();
    }
  } catch (_) {}

  final controller = TextEditingController(text: initialText);
  String? error;

  if (!context.mounted) return null;
  final textRoute = DialogRoute<MatchParseResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => KeyboardSafeFormDialog(
        title: const Text('从文本识别比赛'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '支持粘贴聊天消息、赛程简讯或文本，系统将智能提取对阵双方、赛事、时间和转播平台。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如：周日 20:00 英超第4轮 阿森纳 vs 切尔西 CCTV5直播',
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                setState(() => error = '请输入或粘贴赛程文本');
                return;
              }
              final result = MatchTextParser.parse(
                text,
                referenceDate: DateTime.now(),
                sourceType: MatchSources.manual,
                sourceLabel: '文本识别',
              );
              if (result.drafts.isEmpty) {
                setState(() => error = '未能识别出有效的赛事或对阵双方，请检查文本。');
                return;
              }
              Navigator.pop(dialogContext, result);
            },
            child: const Text('智能识别'),
          ),
        ],
      ),
    ),
  );
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push(textRoute);
  await textRoute.completed;
  controller.dispose();
  return result;
}

Future<void> showMatchReportDialog(
  BuildContext context,
  MatchRecordEntry row,
) async {
  final date = DateKeys.fromLocalDateKey(row.matchDate);
  final start = row.startAt == null
      ? null
      : TimeZoneResolver.atInstant(
          DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true),
          row.timezoneId ?? 'Asia/Shanghai',
        );
  final showYear = date.year != DateTime.now().year;
  final dateStr = showYear
      ? DateFormat('yyyy年M月d日').format(date)
      : DateFormat('M月d日').format(date);
  final timeStr = start == null ? '' : ' ${DateFormat('HH:mm').format(start)}';
  final matchTime = '$dateStr$timeStr';

  final scoreStr = '${row.scoreA ?? '-'} : ${row.scoreB ?? '-'}';
  final summaryText = [
    '【比赛战报】',
    '赛事：${row.competition}${row.stageOrRound != null && row.stageOrRound!.trim().isNotEmpty ? ' ${row.stageOrRound!.trim()}' : ''}',
    '对阵：${row.participantA} $scoreStr ${row.participantB}',
    if (row.scoreDetail != null && row.scoreDetail!.trim().isNotEmpty)
      '说明：${row.scoreDetail!.trim()}',
    '时间：$matchTime',
    if (row.venue != null && row.venue!.trim().isNotEmpty)
      '场地：${row.venue!.trim()}',
    if (row.broadcast != null && row.broadcast!.trim().isNotEmpty)
      '直播：${row.broadcast!.trim()}',
    '来源：LifeHub 赛事管理',
  ].join('\n');

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.emoji_events_outlined),
          SizedBox(width: 8),
          Text('赛事战报'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  children: [
                    Text(
                      '${row.competition} · ${row.stageOrRound ?? row.sportType}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            row.participantA,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            scoreStr,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.participantB,
                            textAlign: TextAlign.left,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (row.scoreDetail != null &&
                        row.scoreDetail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        row.scoreDetail!.trim(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          matchTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    if (row.venue != null && row.venue!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.place_outlined,
                              size: 13, color: colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            row.venue!.trim(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制战报'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: summaryText));
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('战报已复制到剪贴板')),
            );
          },
        ),
      ],
    ),
  );
}
