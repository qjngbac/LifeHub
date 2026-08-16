import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<MediaSeriesEntry?> showMediaSeriesEditor(
  BuildContext context,
  MediaRepository repository, {
  MediaSeriesEntry? existing,
  MediaCategory? presetCategory,
}) async {
  final title = TextEditingController(text: existing?.title);
  final description = TextEditingController(text: existing?.description);
  final year = TextEditingController(text: existing?.releaseYear?.toString());
  final rating = TextEditingController(text: existing?.rating?.toString());
  final note = TextEditingController(text: existing?.note);
  var category = existing == null
      ? presetCategory ?? MediaCategory.tv
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
  return existing == null
      ? repository.createSeries(draft)
      : repository.updateSeries(existing.id, draft);
}

Future<MediaEntry?> showMediaEntryEditor(
  BuildContext context,
  MediaRepository repository, {
  MediaEntry? existing,
  MediaCategory? presetCategory,
  String? presetSeriesId,
}) async {
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
      ? presetCategory ?? MediaCategory.tv
      : MediaCategory.fromDb(existing.category);
  var entryType = existing == null
      ? (category == MediaCategory.movie
          ? MediaEntryType.movie
          : MediaEntryType.season)
      : MediaEntryType.fromDb(existing.entryType);
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
              TextFormField(
                controller: subtitle,
                decoration: const InputDecoration(labelText: '副标题（可选）'),
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
              DropdownButtonFormField<String?>(
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
                onChanged: (value) => setDialogState(() => seriesId = value),
              ),
              DropdownButtonFormField<MediaEntryType>(
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
                controller: description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '简介（可选）'),
              ),
              TextFormField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注（可选）'),
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
  return existing == null
      ? repository.createEntry(draft)
      : repository.updateEntry(existing.id, draft);
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
