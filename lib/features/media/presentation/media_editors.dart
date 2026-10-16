import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/media/application/media_preferences.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MediaSeriesEntry?> showMediaSeriesEditor(
  BuildContext context,
  MediaRepository repository, {
  MediaSeriesEntry? existing,
  MediaCategory? presetCategory,
  MediaPreferences? preferences,
}) async {
  final preferenceStore =
      preferences ?? MediaPreferences(await SharedPreferences.getInstance());
  if (!context.mounted) return null;
  final title = TextEditingController(text: existing?.title);
  final description = TextEditingController(text: existing?.description);
  final year = TextEditingController(text: existing?.releaseYear?.toString());
  final rating = TextEditingController(text: existing?.rating?.toString());
  final note = TextEditingController(text: existing?.note);
  var category = existing == null
      ? presetCategory ?? preferenceStore.loadCategory() ?? MediaCategory.tv
      : MediaCategory.fromDb(existing.category);
  final formKey = GlobalKey<FormState>();
  final save = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => KeyboardSafeFormDialog(
        title: Text(existing == null ? '添加系列' : '修改系列'),
        body: Form(
          key: formKey,
          child: Column(children: [
            TextFormField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '系列名称 *'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写系列名称' : null,
            ),
            DropdownButtonFormField<MediaCategory>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '分类'),
              items: MediaCategory.values
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => category = value);
              },
            ),
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: existing != null &&
                  (existing.description != null ||
                      existing.releaseYear != null ||
                      existing.rating != null ||
                      existing.note != null),
              title: const Text('更多信息'),
              children: [
                TextFormField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '简介（可选）'),
                ),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '年份'),
                      validator: _optionalIntegerValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: rating,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '评分 0～10'),
                      validator: _ratingValidator,
                    ),
                  ),
                ]),
                TextFormField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注（可选）'),
                ),
              ],
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (save != true) return null;
  final draft = MediaSeriesDraft(
    title: title.text,
    category: category,
    description: description.text,
    releaseYear: _optionalInt(year.text),
    rating: _optionalDouble(rating.text),
    note: note.text,
  );
  final saved = existing == null
      ? repository.createSeries(draft)
      : repository.updateSeries(existing.id, draft);
  final result = await saved;
  if (existing == null) {
    await preferenceStore.saveSelection(category: category);
  }
  return result;
}

Future<MediaEntry?> showMediaEntryEditor(
  BuildContext context,
  MediaRepository repository, {
  MediaEntry? existing,
  MediaCategory? presetCategory,
  String? presetSeriesId,
  MediaPreferences? preferences,
}) async {
  final preferenceStore =
      preferences ?? MediaPreferences(await SharedPreferences.getInstance());
  final allSeries = await repository.listSeries();
  if (!context.mounted) return null;
  final title = TextEditingController(text: existing?.title);
  final subtitle = TextEditingController(text: existing?.subtitle);
  final total =
      TextEditingController(text: existing?.totalEpisodes?.toString());
  final completed = TextEditingController(
      text: existing?.completedEpisodes.toString() ?? '0');
  final durationMinutes = TextEditingController(
      text: existing?.durationSeconds == null
          ? null
          : (existing!.durationSeconds! ~/ 60).toString());
  final positionMinutes = TextEditingController(
      text: existing == null
          ? '0'
          : (existing.playbackPositionSeconds ~/ 60).toString());
  final year = TextEditingController(text: existing?.releaseYear?.toString());
  final rating = TextEditingController(text: existing?.rating?.toString());
  final description = TextEditingController(text: existing?.description);
  final note = TextEditingController(text: existing?.note);
  var category = existing == null
      ? presetCategory ?? preferenceStore.loadCategory() ?? MediaCategory.tv
      : MediaCategory.fromDb(existing.category);
  var entryType = existing == null
      ? preferenceStore.loadEntryType() ??
          (category == MediaCategory.movie
              ? MediaEntryType.movie
              : MediaEntryType.season)
      : MediaEntryType.fromDb(existing.entryType);
  if (category == MediaCategory.movie && entryType == MediaEntryType.season) {
    entryType = MediaEntryType.movie;
  }
  var status = existing == null
      ? MediaWatchStatus.plan
      : MediaWatchStatus.fromDb(existing.watchStatus);
  String? seriesId = existing?.seriesId ?? presetSeriesId;
  final formKey = GlobalKey<FormState>();
  final save = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final series = allSeries
            .where((item) => item.category == category.dbValue)
            .toList();
        if (!series.any((item) => item.id == seriesId)) seriesId = null;
        final episodes = entryType.usesEpisodeProgress;
        return KeyboardSafeFormDialog(
          title: Text(existing == null ? '添加作品' : '修改作品'),
          body: Form(
            key: formKey,
            child: Column(children: [
              TextFormField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '作品名称 *'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请填写作品名称' : null,
              ),
              DropdownButtonFormField<MediaCategory>(
                key: ValueKey('category-${category.dbValue}'),
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: MediaCategory.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    category = value;
                    seriesId = null;
                    if (value == MediaCategory.movie &&
                        entryType == MediaEntryType.season) {
                      entryType = MediaEntryType.movie;
                    }
                  });
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey(
                        'series-${category.dbValue}-$seriesId-${allSeries.length}',
                      ),
                      initialValue: seriesId,
                      decoration: const InputDecoration(labelText: '所属系列（可选）'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('独立作品'),
                        ),
                        ...series.map((item) => DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text(item.title),
                            )),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => seriesId = value),
                    ),
                  ),
                  IconButton(
                    tooltip: '新建系列',
                    onPressed: () async {
                      final created = await showMediaSeriesEditor(
                        dialogContext,
                        repository,
                        presetCategory: category,
                        preferences: preferenceStore,
                      );
                      if (created != null && dialogContext.mounted) {
                        setDialogState(() {
                          allSeries.add(created);
                          seriesId = created.id;
                        });
                      }
                    },
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                ],
              ),
              DropdownButtonFormField<MediaEntryType>(
                key: ValueKey('type-${entryType.dbValue}'),
                initialValue: entryType,
                decoration: const InputDecoration(labelText: '作品类型'),
                items: MediaEntryType.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => entryType = value);
                },
              ),
              DropdownButtonFormField<MediaWatchStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: '观看状态'),
                items: MediaWatchStatus.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => status = value);
                },
              ),
              if (episodes)
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: total,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '总集数（可空）'),
                      validator: _optionalNonNegativeValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: completed,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '已看集数'),
                      validator: _requiredNonNegativeValidator,
                    ),
                  ),
                ])
              else
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: durationMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '总时长（分钟）'),
                      validator: _optionalNonNegativeValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: positionMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '已看位置（分钟）'),
                      validator: _requiredNonNegativeValidator,
                    ),
                  ),
                ]),
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: existing != null &&
                    (existing.subtitle != null ||
                        existing.releaseYear != null ||
                        existing.rating != null ||
                        existing.description != null ||
                        existing.note != null),
                title: const Text('更多信息'),
                children: [
                  TextFormField(
                    controller: subtitle,
                    decoration: const InputDecoration(labelText: '副标题（可选）'),
                  ),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: year,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '年份'),
                        validator: _optionalIntegerValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: rating,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: '评分 0～10'),
                        validator: _ratingValidator,
                      ),
                    ),
                  ]),
                  TextFormField(
                    controller: description,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '简介（可选）'),
                  ),
                  TextFormField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '备注（可选）'),
                  ),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  if (save != true) return null;
  final usesEpisodes = entryType.usesEpisodeProgress;
  final totalEpisodes = usesEpisodes ? _optionalInt(total.text) : null;
  final completedEpisodes = usesEpisodes ? int.parse(completed.text) : 0;
  final durationSeconds = usesEpisodes
      ? null
      : _optionalInt(durationMinutes.text)?.let((value) => value * 60);
  final playbackSeconds =
      usesEpisodes ? 0 : int.parse(positionMinutes.text) * 60;
  if (totalEpisodes != null && completedEpisodes > totalEpisodes ||
      durationSeconds != null && playbackSeconds > durationSeconds) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前进度不能超过总集数或总时长')),
      );
    }
    return null;
  }
  final draft = MediaEntryDraft(
    title: title.text,
    subtitle: subtitle.text,
    category: category,
    entryType: entryType,
    seriesId: seriesId,
    sortKey: existing?.sortKey,
    releaseYear: _optionalInt(year.text),
    description: description.text,
    watchStatus: status,
    totalEpisodes: totalEpisodes,
    completedEpisodes: completedEpisodes,
    durationSeconds: durationSeconds,
    playbackPositionSeconds: playbackSeconds,
    lastWatchedAt: existing?.lastWatchedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(existing!.lastWatchedAt!),
    rating: _optionalDouble(rating.text),
    note: note.text,
  );
  final saved = existing == null
      ? repository.createEntry(draft)
      : repository.updateEntry(existing.id, draft);
  final result = await saved;
  if (existing == null) {
    await preferenceStore.saveSelection(
      category: category,
      entryType: entryType,
    );
  }
  return result;
}

Future<List<MediaEntry>?> showMediaSeasonBatchEditor(
  BuildContext context,
  MediaRepository repository, {
  required MediaSeriesEntry series,
}) async {
  final drafts = await showDialog<List<MediaEntryDraft>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SeasonBatchDialog(series: series),
  );
  if (drafts == null) return null;
  try {
    return await repository.createEntries(drafts);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mediaEditorError(error))),
      );
    }
    return null;
  }
}

class _SeasonBatchDialog extends StatefulWidget {
  const _SeasonBatchDialog({required this.series});

  final MediaSeriesEntry series;

  @override
  State<_SeasonBatchDialog> createState() => _SeasonBatchDialogState();
}

class _SeasonBatchDialogState extends State<_SeasonBatchDialog> {
  final formKey = GlobalKey<FormState>();
  final rows = <_SeasonBatchRow>[_SeasonBatchRow(title: '第1季')];

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardSafeFormDialog(
        title: const Text('批量添加季'),
        body: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('系列：${widget.series.title}'),
              Text('分类：${MediaCategory.fromDb(widget.series.category).label}'),
              const SizedBox(height: 8),
              const Text('每一季独立记录总集数和已看集数。'),
              const SizedBox(height: 8),
              ...List.generate(
                rows.length,
                (index) => _buildSeasonBatchRow(
                  context,
                  rows[index],
                  index,
                  rows.length,
                  setState,
                  onRemove: () {
                    final removed = rows[index];
                    setState(() => rows.removeAt(index));
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      removed.dispose();
                    });
                  },
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  rows.add(_SeasonBatchRow(title: '第${rows.length + 1}季'));
                }),
                icon: const Icon(Icons.add),
                label: const Text('添加一季'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      );

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final result = _seasonBatchDrafts(rows, widget.series);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每季名称不能重复，且已看集数不能超过总集数。')),
      );
      return;
    }
    Navigator.pop(context, result);
  }
}

Widget _buildSeasonBatchRow(
  BuildContext context,
  _SeasonBatchRow row,
  int index,
  int rowCount,
  StateSetter setDialogState, {
  required VoidCallback onRemove,
}) {
  return Card(
    key: ValueKey('season-batch-row-$index'),
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '第 ${index + 1} 季',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (rowCount > 1)
              IconButton(
                tooltip: '删除第 ${index + 1} 季',
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
              ),
          ]),
          TextFormField(
            key: ValueKey('season-batch-title-$index'),
            controller: row.title,
            decoration: const InputDecoration(labelText: '季名称 *'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请填写季名称' : null,
          ),
          Row(children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('season-batch-total-$index'),
                controller: row.total,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '总集数（可空）'),
                validator: _optionalNonNegativeValidator,
                onChanged: (value) {
                  if (row.markedCompleted && value.trim().isNotEmpty) {
                    row.completed.text = value.trim();
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: ValueKey('season-batch-completed-$index'),
                controller: row.completed,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '已看集数'),
                validator: _requiredNonNegativeValidator,
              ),
            ),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: row.markedCompleted,
            title: const Text('本季已看完'),
            onChanged: (value) => setDialogState(() {
              row.markedCompleted = value ?? false;
              if (row.markedCompleted && row.total.text.trim().isNotEmpty) {
                row.completed.text = row.total.text.trim();
              }
            }),
          ),
        ],
      ),
    ),
  );
}

List<MediaEntryDraft>? _seasonBatchDrafts(
  List<_SeasonBatchRow> rows,
  MediaSeriesEntry series,
) {
  final titles = <String>{};
  final category = MediaCategory.fromDb(series.category);
  final drafts = <MediaEntryDraft>[];
  for (final row in rows) {
    final title = row.title.text.trim();
    if (!titles.add(title)) {
      return null;
    }
    final total = _optionalInt(row.total.text);
    var completed = int.parse(row.completed.text.trim());
    if (row.markedCompleted && total != null) completed = total;
    if (total != null && completed > total) return null;
    final completedStatus =
        row.markedCompleted || total != null && total > 0 && completed == total;
    drafts.add(MediaEntryDraft(
      title: title,
      category: category,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      watchStatus: completedStatus
          ? MediaWatchStatus.completed
          : completed > 0
              ? MediaWatchStatus.watching
              : MediaWatchStatus.plan,
      totalEpisodes: total,
      completedEpisodes: completed,
    ));
  }
  return drafts;
}

class _SeasonBatchRow {
  _SeasonBatchRow({required String title})
      : title = TextEditingController(text: title),
        total = TextEditingController(),
        completed = TextEditingController(text: '0');

  final TextEditingController title;
  final TextEditingController total;
  final TextEditingController completed;
  var markedCompleted = false;

  void dispose() {
    title.dispose();
    total.dispose();
    completed.dispose();
  }
}

String _mediaEditorError(Object error) {
  if (error is RangeError) return '请检查每季的集数进度。';
  if (error is ArgumentError) return '请检查批量添加内容。';
  return '保存失败，请稍后重试。';
}

String? _optionalIntegerValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return int.tryParse(value.trim()) == null ? '请输入整数' : null;
}

String? _optionalNonNegativeValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = int.tryParse(value.trim());
  return parsed == null || parsed < 0 ? '请输入不小于 0 的整数' : null;
}

String? _requiredNonNegativeValidator(String? value) {
  if (value == null || value.trim().isEmpty) return '请填写进度';
  return _optionalNonNegativeValidator(value);
}

String? _ratingValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = double.tryParse(value.trim());
  return parsed == null || parsed < 0 || parsed > 10 ? '评分为 0～10' : null;
}

int? _optionalInt(String value) =>
    value.trim().isEmpty ? null : int.parse(value.trim());
double? _optionalDouble(String value) =>
    value.trim().isEmpty ? null : double.parse(value.trim());

extension _Let<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
