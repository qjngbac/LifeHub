import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/time_zone_resolver.dart';
import 'package:lifehub/features/matches/application/match_import_service.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/presentation/match_dialogs.dart';

class MatchImportPreviewPage extends ConsumerStatefulWidget {
  const MatchImportPreviewPage({required this.preview, super.key});

  final MatchImportPreview preview;

  @override
  ConsumerState<MatchImportPreviewPage> createState() =>
      _MatchImportPreviewPageState();
}

class _MatchImportPreviewPageState
    extends ConsumerState<MatchImportPreviewPage> {
  late List<MatchImportPreviewRow> rows;

  @override
  void initState() {
    super.initState();
    rows = List.of(widget.preview.rows);
  }

  @override
  Widget build(BuildContext context) {
    final selected = rows.where((row) => row.selected).length;
    final hasSelectedErrors = rows
        .any((row) => row.selected && row.state == MatchPreviewState.invalid);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入预览'),
        actions: [
          TextButton(
            onPressed: selected == 0 || hasSelectedErrors ? null : _save,
            child: Text('保存 $selected 条'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (widget.preview.warnings.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.preview.warnings.join('\n')),
              ),
            ),
          for (var index = 0; index < rows.length; index++)
            _PreviewCard(
              row: rows[index],
              onChanged: (value) => setState(() => rows[index] = value),
              onEdit: () => _edit(index),
              onRemove: () => setState(() => rows.removeAt(index)),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('没有识别到可预览的比赛')),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final repository = MatchRepository(ref.read(databaseProvider));
    try {
      await MatchImportService().saveSelectedWithRepository(
        MatchImportPreview(rows: rows, warnings: widget.preview.warnings),
        repository,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _edit(int index) async {
    final current = rows[index];
    final draft = await showMatchDraftDialog(
      context,
      initial: current.draft,
    );
    if (draft == null || !mounted) return;
    final issues = draft
        .validate(now: DateTime.now())
        .where((issue) => issue.severity == MatchIssueSeverity.error)
        .toList(growable: false);
    final duplicates = issues.isEmpty
        ? await MatchRepository(ref.read(databaseProvider))
            .findPossibleDuplicates(draft)
        : const <MatchRecordEntry>[];
    if (!mounted) return;
    final duplicate = duplicates.isNotEmpty;
    setState(() {
      rows[index] = MatchImportPreviewRow(
        draft: draft,
        issues: issues,
        state: issues.isNotEmpty
            ? MatchPreviewState.invalid
            : duplicate
                ? MatchPreviewState.duplicate
                : MatchPreviewState.ready,
        possibleDuplicate: duplicate,
        existingId: duplicate ? duplicates.first.id : null,
        selected: !duplicate,
      );
    });
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.row,
    required this.onChanged,
    required this.onEdit,
    required this.onRemove,
  });

  final MatchImportPreviewRow row;
  final ValueChanged<MatchImportPreviewRow> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final draft = row.draft;
    final timezoneId = draft.timezoneId;
    final start = draft.startAt != null &&
            timezoneId != null &&
            TimeZoneResolver.isValid(timezoneId)
        ? TimeZoneResolver.atInstant(draft.startAt!, timezoneId)
        : null;
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: row.selected,
            onChanged: (value) =>
                onChanged(row.copyWith(selected: value ?? false)),
            title: Text(
              '${draft.participantA ?? '待填写'} vs ${draft.participantB ?? '待填写'}',
            ),
            subtitle: Text([
              draft.sportType ?? '未填写运动',
              draft.competition ?? '未填写赛事',
              if (start != null)
                '${DateFormat('yyyy-MM-dd HH:mm').format(start)} ($timezoneId)'
              else if (draft.matchDate != null)
                DateFormat('yyyy-MM-dd').format(draft.matchDate!),
              if (row.issues.isNotEmpty)
                row.issues.map((issue) => issue.message).join(' '),
              if (row.possibleDuplicate)
                row.selected ? '保存后更新已有比赛' : '可能已存在，默认跳过',
            ].join(' · ')),
            secondary:
                row.possibleDuplicate ? const Chip(label: Text('可能已存在')) : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('移除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
