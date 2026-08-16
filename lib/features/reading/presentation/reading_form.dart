import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<ReadingDraft?> showReadingForm(
  BuildContext context, {
  ReadingItemEntry? current,
}) async {
  final title = TextEditingController(text: current?.title);
  final author = TextEditingController(text: current?.author);
  final currentProgress = TextEditingController(
    text: current != null && current.currentProgress > 0
        ? current.currentProgress.toString()
        : '',
  );
  final totalProgress =
      TextEditingController(text: current?.totalProgress?.toString() ?? '');
  final notes = TextEditingController(text: current?.notes);
  var type = current == null
      ? ReadingType.novel
      : ReadingType.values.firstWhere(
          (value) => value.name.toUpperCase() == current.readingType,
          orElse: () => ReadingType.novel,
        );
  var unit = current == null
      ? ReadingUnit.chapter
      : ReadingUnit.values.firstWhere(
          (value) => value.name.toUpperCase() == current.progressUnit,
          orElse: () => ReadingUnit.chapter,
        );
  String? error;
  final result = await showDialog<ReadingDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '添加读物' : '编辑读物'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: current == null,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: '作者（可选）'),
            ),
            DropdownButtonFormField<ReadingType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: '类型'),
              items: ReadingType.values
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(readingTypeLabel(value)),
                      ))
                  .toList(),
              onChanged: (value) => setDialogState(() => type = value ?? type),
            ),
            DropdownButtonFormField<ReadingUnit>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: '进度单位'),
              items: ReadingUnit.values
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(readingUnitLabel(value.name.toUpperCase())),
                      ))
                  .toList(),
              onChanged: (value) => setDialogState(() => unit = value ?? unit),
            ),
            TextField(
              controller: currentProgress,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: unit == ReadingUnit.chapter
                    ? '已读章节（可选）'
                    : unit == ReadingUnit.page
                        ? '已读页数（可选）'
                        : '当前百分比（可选）',
              ),
            ),
            TextField(
              controller: totalProgress,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: unit == ReadingUnit.chapter
                    ? '总章节（可选）'
                    : unit == ReadingUnit.page
                        ? '总页数（可选）'
                        : '总进度（可选）',
              ),
            ),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = title.text.trim();
              final currentText = currentProgress.text.trim();
              final totalText = totalProgress.text.trim();
              final currentValue =
                  currentText.isEmpty ? 0 : int.tryParse(currentText);
              final totalValue =
                  totalText.isEmpty ? null : int.tryParse(totalText);
              String? problem;
              if (name.isEmpty) {
                problem = '请填写标题';
              } else if (currentValue == null || currentValue < 0) {
                problem = '已读进度必须是非负整数';
              } else if (totalText.isNotEmpty &&
                  (totalValue == null || totalValue < 0)) {
                problem = '总进度必须是非负整数';
              } else if (totalValue != null && currentValue > totalValue) {
                problem = '已读进度不能超过总进度';
              }
              if (problem != null) {
                setDialogState(() => error = problem);
                return;
              }
              Navigator.pop(
                context,
                ReadingDraft(
                  title: name,
                  author: author.text,
                  readingType: type,
                  progressUnit: unit,
                  currentProgress: currentValue!,
                  totalProgress: totalValue,
                  status: current == null
                      ? ReadingStatus.planned
                      : ReadingStatus.fromDb(current.status),
                  rating: current?.rating,
                  notes: notes.text,
                  coverPath: current?.coverPath,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  for (final controller in [
    title,
    author,
    currentProgress,
    totalProgress,
    notes,
  ]) {
    controller.dispose();
  }
  return result;
}

String readingTypeLabel(ReadingType value) => switch (value) {
      ReadingType.book => '图书',
      ReadingType.novel => '小说',
      ReadingType.comic => '漫画',
      ReadingType.paper => '论文',
      ReadingType.other => '其他',
    };

String readingUnitLabel(String value) => switch (value) {
      'PAGE' => '页',
      'CHAPTER' => '章',
      'PERCENT' => '%',
      _ => value,
    };
