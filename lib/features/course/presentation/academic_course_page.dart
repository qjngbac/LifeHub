import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class AcademicCoursePage extends ConsumerStatefulWidget {
  const AcademicCoursePage({super.key, required this.courseId});
  final String courseId;

  @override
  ConsumerState<AcademicCoursePage> createState() => _AcademicCoursePageState();
}

class _AcademicCoursePageState extends ConsumerState<AcademicCoursePage> {
  var revision = 0;

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    final repository = AcademicRepository(db);
    return FutureBuilder<(CourseEntry, AcademicOverview)>(
      key: ValueKey(revision),
      future: () async {
        final course = await (db.select(db.courses)
              ..where((row) => row.id.equals(widget.courseId)))
            .getSingle();
        return (course, await repository.overview(widget.courseId));
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final course = snapshot.data!.$1;
        final overview = snapshot.data!.$2;
        return Scaffold(
          appBar: AppBar(title: Text(course.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summary(context, overview),
              _section(
                context,
                title: '作业',
                icon: Icons.assignment_outlined,
                count: overview.openAssignments.length,
                empty: '没有作业',
                details: overview.openAssignments.map(
                  (item) => _SectionDetail(
                    item.title,
                    subtitle: [
                      if (item.submissionMethod != null)
                        '提交：${item.submissionMethod}',
                      if (item.deadlineLabel != null) item.deadlineLabel!,
                      if (item.submitted) '已提交',
                    ].join(' · '),
                    submitted: item.submitted,
                    onSubmit: item.submitted
                        ? null
                        : () => _runAndRefresh(
                              () => repository.submitAssignment(
                                item.entity.reference.id,
                              ),
                            ),
                    onDelete: () => _runAndRefresh(
                      () => repository.deleteAssignment(
                        item.entity.reference.id,
                      ),
                    ),
                  ),
                ),
                onAdd: () => _addAssignment(repository),
              ),
              _section(
                context,
                title: '考试',
                icon: Icons.event_note_outlined,
                count: overview.futureExams.length,
                empty: '没有未来考试',
                details: overview.futureExams.map(
                  (item) => _SectionDetail(
                    item.title,
                    subtitle: item.scheduleLabel,
                    onDelete: () => _runAndRefresh(
                      () => repository.deleteExam(item.entity.reference.id),
                    ),
                  ),
                ),
                onAdd: () => _addExam(repository),
              ),
              _section(
                context,
                title: '资料',
                icon: Icons.bookmarks_outlined,
                count: overview.materials.length,
                empty: '没有课程资料',
                details: overview.materials.map(
                  (item) => _SectionDetail(
                    item.title,
                    onDelete: () => _runAndRefresh(
                      () => repository.deleteMaterial(item.reference.id),
                    ),
                  ),
                ),
                onAdd: () => _addMaterial(repository),
              ),
              _section(
                context,
                title: '成绩',
                icon: Icons.grade_outlined,
                count: overview.grades.length,
                empty: '没有成绩记录',
                details: overview.grades.map(
                  (item) => _SectionDetail(
                    '${item.title} ${item.score}/${item.maximum}',
                    onDelete: () => _runAndRefresh(
                      () => repository.deleteGrade(item.id),
                    ),
                  ),
                ),
                onAdd: () => _addGrade(repository),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summary(BuildContext context, AcademicOverview value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('概览', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              Chip(label: Text('${value.pendingAssignmentCount} 个待提交作业')),
              Chip(label: Text('${value.futureExams.length} 场未来考试')),
              Chip(label: Text('${value.materials.length} 份资料')),
              Chip(label: Text('${value.grades.length} 条成绩')),
            ]),
          ]),
        ),
      );

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
    required String empty,
    required Iterable<_SectionDetail> details,
    required VoidCallback onAdd,
  }) =>
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(count == 0 ? empty : '$count 条记录'),
              trailing: IconButton(
                tooltip: '添加$title',
                icon: const Icon(Icons.add),
                onPressed: onAdd,
              ),
            ),
            for (final detail in details)
              ListTile(
                dense: true,
                leading: const SizedBox(width: 24),
                title: Text(detail.title),
                subtitle: detail.subtitle == null || detail.subtitle!.isEmpty
                    ? null
                    : Text(detail.subtitle!),
                trailing: detail.onDelete == null && detail.onSubmit == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (detail.onSubmit != null || detail.submitted)
                            Tooltip(
                              message: detail.submitted ? '已提交' : '标记为已提交',
                              child: Checkbox(
                                value: detail.submitted,
                                onChanged: detail.onSubmit == null
                                    ? null
                                    : (_) => detail.onSubmit!(),
                              ),
                            ),
                          if (detail.onDelete != null)
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: detail.onDelete,
                            ),
                        ],
                      ),
              ),
          ],
        ),
      );

  Future<String?> _textDialog(
    String title,
    String label, {
    String confirmLabel = '保存',
  }) async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TextInputDialog(
        title: title,
        label: label,
        confirmLabel: confirmLabel,
      ),
    );
    return value?.isEmpty == true ? null : value;
  }

  Future<void> _addAssignment(AcademicRepository repository) async {
    final draft = await showDialog<_AssignmentInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AssignmentDialog(),
    );
    if (draft == null) return;
    await repository.createAssignment(
      courseId: widget.courseId,
      title: draft.title,
      submissionMethod: draft.submissionMethod,
      dueAt: draft.dueAt,
    );
    if (mounted) setState(() => revision++);
  }

  Future<void> _runAndRefresh(Future<void> Function() action) async {
    await action();
    if (mounted) setState(() => revision++);
  }

  Future<void> _addExam(AcademicRepository repository) async {
    final title = await _textDialog('添加考试', '考试名称');
    if (title == null) return;
    if (!mounted) return;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
      barrierDismissible: false,
    );
    if (date == null) return;
    if (!mounted) return;
    final range = await _examTimeDialog(date);
    if (range == null) return;
    await repository.createExam(
      courseId: widget.courseId,
      title: title,
      start: range.start,
      end: range.end,
      allDay: range.allDay,
    );
    if (mounted) setState(() => revision++);
  }

  Future<_ExamTimeRange?> _examTimeDialog(DateTime date) async {
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    return showDialog<_ExamTimeRange>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          DateTime at(TimeOfDay value) => DateTime(
                date.year,
                date.month,
                date.day,
                value.hour,
                value.minute,
              );

          final valid = startTime != null &&
              endTime != null &&
              at(endTime!).isAfter(at(startTime!));
          return AlertDialog(
            title: const Text('考试时间（可选）'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('开始时间'),
                  subtitle: Text(startTime?.format(context) ?? '未设置'),
                  onTap: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime:
                          startTime ?? const TimeOfDay(hour: 9, minute: 0),
                      helpText: '选择开始时间',
                    );
                    if (value != null) setDialogState(() => startTime = value);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('结束时间'),
                  subtitle: Text(endTime?.format(context) ?? '未设置'),
                  onTap: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime:
                          endTime ?? const TimeOfDay(hour: 11, minute: 0),
                      helpText: '选择结束时间',
                    );
                    if (value != null) setDialogState(() => endTime = value);
                  },
                ),
                if ((startTime == null) != (endTime == null))
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '开始和结束时间需要同时设置',
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else if (startTime != null && !valid)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '结束时间必须晚于开始时间',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _ExamTimeRange(
                    start: DateTime(date.year, date.month, date.day),
                    end: DateTime(date.year, date.month, date.day + 1),
                    allDay: true,
                  ),
                ),
                child: const Text('不设置时间'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(
                          dialogContext,
                          _ExamTimeRange(
                            start: at(startTime!),
                            end: at(endTime!),
                            allDay: false,
                          ),
                        )
                    : null,
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addMaterial(AcademicRepository repository) async {
    final title = await _textDialog('添加课程资料', '资料标题');
    if (title == null) return;
    await repository.createMaterial(courseId: widget.courseId, title: title);
    if (mounted) setState(() => revision++);
  }

  Future<void> _addGrade(AcademicRepository repository) async {
    final title = TextEditingController();
    final score = TextEditingController();
    final maximum = TextEditingController(text: '100');
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('添加成绩'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '项目名称')),
            TextField(
                controller: score,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '得分')),
            TextField(
                controller: maximum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '满分')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (accepted == true) {
      await repository.saveGrade(CourseGradeDraft(
        courseId: widget.courseId,
        title: title.text,
        score: double.parse(score.text),
        maximum: double.parse(maximum.text),
      ));
      if (mounted) setState(() => revision++);
    }
    title.dispose();
    score.dispose();
    maximum.dispose();
  }
}

class _SectionDetail {
  const _SectionDetail(
    this.title, {
    this.subtitle,
    this.submitted = false,
    this.onSubmit,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool submitted;
  final VoidCallback? onSubmit;
  final VoidCallback? onDelete;
}

class _AssignmentInput {
  const _AssignmentInput({
    required this.title,
    this.submissionMethod,
    this.dueAt,
  });

  final String title;
  final String? submissionMethod;
  final DateTime? dueAt;
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog();

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  final title = TextEditingController();
  final submissionMethod = TextEditingController();
  DateTime? dueAt;

  @override
  void dispose() {
    title.dispose();
    submissionMethod.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardSafeFormDialog(
        title: const Text('添加作业'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '作业名称'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: submissionMethod,
              decoration: const InputDecoration(
                labelText: '提交方式（可选）',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('截止时间（可选）'),
              subtitle: Text(
                dueAt == null
                    ? '未设置'
                    : '${dueAt!.year}年${dueAt!.month}月${dueAt!.day}日 '
                        '${dueAt!.hour.toString().padLeft(2, '0')}:'
                        '${dueAt!.minute.toString().padLeft(2, '0')}',
              ),
              trailing: dueAt == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: '清除截止时间',
                      onPressed: () => setState(() => dueAt = null),
                      icon: const Icon(Icons.close),
                    ),
              onTap: _pickDeadline,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: title.text.trim().isEmpty ? null : _submit,
            child: const Text('保存'),
          ),
        ],
      );

  Future<void> _pickDeadline() async {
    final initial = dueAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
      barrierDismissible: false,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: dueAt == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(dueAt!),
      helpText: '选择截止时间',
    );
    if (time == null || !mounted) return;
    setState(() {
      dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    final value = title.text.trim();
    if (value.isEmpty) return;
    final method = submissionMethod.text.trim();
    Navigator.pop(
      context,
      _AssignmentInput(
        title: value,
        submissionMethod: method.isEmpty ? null : method,
        dueAt: dueAt,
      ),
    );
  }
}

class _ExamTimeRange {
  const _ExamTimeRange({
    required this.start,
    required this.end,
    required this.allDay,
  });

  final DateTime start;
  final DateTime end;
  final bool allDay;
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String confirmLabel;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      );

  void _submit() {
    final value = controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }
}
