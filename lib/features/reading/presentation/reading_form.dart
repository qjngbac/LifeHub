import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<ReadingDraft?> showReadingForm(
  BuildContext context, {
  ReadingItemEntry? current,
}) {
  return showDialog<ReadingDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReadingFormDialog(current: current),
  );
}

class ReadingFormDialog extends StatefulWidget {
  const ReadingFormDialog({super.key, this.current});

  final ReadingItemEntry? current;

  @override
  State<ReadingFormDialog> createState() => _ReadingFormDialogState();
}

class _ReadingFormDialogState extends State<ReadingFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _currentProgress;
  late final TextEditingController _totalProgress;
  late final TextEditingController _ratingController;
  late final TextEditingController _notes;

  late ReadingType _type;
  late ReadingUnit _unit;
  late ReadingStatus _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _title = TextEditingController(text: current?.title);
    _author = TextEditingController(text: current?.author);
    _currentProgress = TextEditingController(
      text: current != null && current.currentProgress > 0
          ? current.currentProgress.toString()
          : '',
    );
    _totalProgress =
        TextEditingController(text: current?.totalProgress?.toString() ?? '');
    _ratingController = TextEditingController(
      text: current?.rating != null ? current!.rating.toString() : '',
    );
    _notes = TextEditingController(text: current?.notes);

    _type = current == null
        ? ReadingType.novel
        : ReadingType.values.firstWhere(
            (value) => value.name.toUpperCase() == current.readingType,
            orElse: () => ReadingType.novel,
          );

    _unit = current == null
        ? ReadingUnit.chapter
        : ReadingUnit.values.firstWhere(
            (value) => value.name.toUpperCase() == current.progressUnit,
            orElse: () => ReadingUnit.chapter,
          );

    _status = current == null
        ? ReadingStatus.reading
        : ReadingStatus.values.firstWhere(
            (value) => value.dbValue == current.status,
            orElse: () => ReadingStatus.reading,
          );
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _currentProgress.dispose();
    _totalProgress.dispose();
    _ratingController.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final name = _title.text.trim();
    final currentText = _currentProgress.text.trim();
    final totalText = _totalProgress.text.trim();
    final currentValue =
        currentText.isEmpty ? 0 : int.tryParse(currentText);
    final totalValue =
        totalText.isEmpty ? null : int.tryParse(totalText);

    double? ratingValue;
    if (_ratingController.text.trim().isNotEmpty) {
      ratingValue = double.tryParse(_ratingController.text.trim());
      if (ratingValue == null || ratingValue < 0 || ratingValue > 10) {
        setState(() => _error = '评分必须在 0 到 10 之间');
        return;
      }
    }

    String? problem;
    if (name.isEmpty) {
      problem = '请填写读物标题';
    } else if (currentValue == null || currentValue < 0) {
      problem = '当前进度必须是非负整数';
    } else if (totalText.isNotEmpty &&
        (totalValue == null || totalValue < 0)) {
      problem = '总进度必须是非负整数';
    } else if (totalValue != null && currentValue > totalValue) {
      problem = '当前进度不能超过总进度';
    }

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    Navigator.pop(
      context,
      ReadingDraft(
        title: name,
        author: _author.text.trim().isEmpty ? null : _author.text.trim(),
        readingType: _type,
        progressUnit: _unit,
        currentProgress: currentValue!,
        totalProgress: totalValue,
        status: _status,
        rating: ratingValue,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        coverPath: widget.current?.coverPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardSafeFormDialog(
      title: Text(widget.current == null ? '添加读物' : '编辑读物'),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: widget.current == null,
              decoration: const InputDecoration(
                labelText: '读物标题 *',
                hintText: '如 三体、百年孤独',
                prefixIcon: Icon(Icons.book_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _author,
              decoration: const InputDecoration(
                labelText: '作者（可选）',
                hintText: '如 刘慈欣',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '读物类型',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTypeButton(
                    theme,
                    ReadingType.book,
                    _type == ReadingType.book,
                    () => setState(() => _type = ReadingType.book),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTypeButton(
                    theme,
                    ReadingType.novel,
                    _type == ReadingType.novel,
                    () => setState(() => _type = ReadingType.novel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTypeButton(
                    theme,
                    ReadingType.comic,
                    _type == ReadingType.comic,
                    () => setState(() => _type = ReadingType.comic),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTypeButton(
                    theme,
                    ReadingType.paper,
                    _type == ReadingType.paper,
                    () => setState(() => _type = ReadingType.paper),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTypeButton(
                    theme,
                    ReadingType.other,
                    _type == ReadingType.other,
                    () => setState(() => _type = ReadingType.other),
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '进度单位',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '页',
                    _unit == ReadingUnit.page,
                    () => setState(() => _unit = ReadingUnit.page),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '章',
                    _unit == ReadingUnit.chapter,
                    () => setState(() => _unit = ReadingUnit.chapter),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '%',
                    _unit == ReadingUnit.percent,
                    () => setState(() => _unit = ReadingUnit.percent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _currentProgress,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '当前进度',
                      hintText: '0',
                      suffixText: readingUnitLabel(_unit.name.toUpperCase()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _totalProgress,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '全书总数',
                      hintText: '选填',
                      suffixText: readingUnitLabel(_unit.name.toUpperCase()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '阅读状态',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '想读',
                    _status == ReadingStatus.planned,
                    () => setState(() => _status = ReadingStatus.planned),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '在读',
                    _status == ReadingStatus.reading,
                    () => setState(() => _status = ReadingStatus.reading),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '已读完',
                    _status == ReadingStatus.completed,
                    () => setState(() => _status = ReadingStatus.completed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '搁置',
                    _status == ReadingStatus.paused,
                    () => setState(() => _status = ReadingStatus.paused),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSimpleButton(
                    theme,
                    '弃读',
                    _status == ReadingStatus.dropped,
                    () => setState(() => _status = ReadingStatus.dropped),
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ratingController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '评分（0 - 10分，可选）',
                hintText: '如 9.0',
                prefixIcon: Icon(Icons.star_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '读书感想与备注（可选）',
                hintText: '记录金句、摘录或个人书评…',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
  }
}

String readingTypeLabel(ReadingType value) => switch (value) {
      ReadingType.book => '图书',
      ReadingType.novel => '小说',
      ReadingType.comic => '漫画',
      ReadingType.paper => '论文',
      ReadingType.other => '其他',
    };

IconData readingTypeIcon(ReadingType value) => switch (value) {
      ReadingType.book => Icons.menu_book_rounded,
      ReadingType.novel => Icons.auto_stories_rounded,
      ReadingType.comic => Icons.photo_library_rounded,
      ReadingType.paper => Icons.description_rounded,
      ReadingType.other => Icons.bookmark_rounded,
    };

String readingUnitLabel(String value) => switch (value) {
      'PAGE' => '页',
      'CHAPTER' => '章',
      'PERCENT' => '%',
      _ => value,
    };

String readingStatusLabel(String status) => switch (status) {
      'PLANNED' => '想读',
      'READING' => '在读',
      'PAUSED' => '搁置',
      'COMPLETED' => '已读完',
      'DROPPED' => '弃读',
      _ => status,
    };

Widget _buildTypeButton(
  ThemeData theme,
  ReadingType t,
  bool isSelected,
  VoidCallback onTap,
) {
  final colorScheme = theme.colorScheme;
  return Material(
    color: isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.6)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              readingTypeIcon(t),
              size: 16,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              readingTypeLabel(t),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildSimpleButton(
  ThemeData theme,
  String label,
  bool isSelected,
  VoidCallback onTap,
) {
  final colorScheme = theme.colorScheme;
  return Material(
    color: isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.6)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
      ),
    ),
  );
}
