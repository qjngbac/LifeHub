import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/platform/course_shortcut_service.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/course/domain/course_selection.dart';
import 'package:lifehub/features/course/presentation/academic_course_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class CoursesPage extends ConsumerStatefulWidget {
  const CoursesPage({super.key});

  @override
  ConsumerState<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends ConsumerState<CoursesPage> {
  String? selectedSemesterId;
  DateTime? weekStart;
  bool editing = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = CourseRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表'),
        actions: [
          IconButton(
            tooltip: '添加到手机桌面',
            icon: const Icon(Icons.add_to_home_screen_outlined),
            onPressed: () => _showDesktopActions(context),
          ),
          TextButton(
            onPressed: () => setState(() => editing = !editing),
            child: Text(editing ? '完成' : '编辑'),
          ),
          IconButton(
            tooltip: '课程表设置',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              final semesters = await repository.semesters();
              if (!context.mounted) return;
              final current = _selectedSemester(semesters);
              await _editSemesterSettings(context, repository, current);
            },
          ),
        ],
      ),
      body: FutureBuilder<_TimetableData>(
        future: _load(repository),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(error: snapshot.error, retry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.semester == null) {
            return _EmptyTimetable(
              onPressed: () => _editSemesterSettings(
                context,
                repository,
                null,
              ),
            );
          }
          final semester = data.semester!;
          final shownWeek = weekStart ?? _initialWeekStart(semester);
          final dates =
              List.generate(7, (index) => shownWeek.add(Duration(days: index)));
          return Column(children: [
            _SemesterBar(
              semester: semester,
              semesters: data.semesters,
              dates: dates,
              onSemesterChanged: (id) => setState(() {
                selectedSemesterId = id;
                weekStart = null;
              }),
              previousWeek: () => setState(() =>
                  weekStart = shownWeek.subtract(const Duration(days: 7))),
              nextWeek: () => setState(
                  () => weekStart = shownWeek.add(const Duration(days: 7))),
              today: () => setState(() => weekStart = null),
            ),
            if (editing)
              MaterialBanner(
                content: const Text('编辑模式：点空白格添加课程，点已有课程进行修改或删除。'),
                leading: const Icon(Icons.edit_calendar_outlined),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => editing = false),
                    child: const Text('完成'),
                  ),
                ],
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: _Timetable(
                  data: data,
                  dates: dates,
                  editing: editing,
                  onCellTap: (weekday, period, value) {
                    if (editing) {
                      _editCourseCell(
                          context, repository, data, weekday, period, value);
                    } else if (value != null) {
                      _showCourseDetails(context, value);
                    }
                  },
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Future<_TimetableData> _load(CourseRepository repository) async {
    final semesters = await repository.semesters();
    final semester = _selectedSemester(semesters);
    if (semester == null) return _TimetableData(semesters: semesters);
    final courses = await repository.courses(semesterId: semester.id);
    final schedules = await repository.schedulesForSemester(semester.id);
    final configured = await repository.loadPeriods(semester.id);
    return _TimetableData(
      semesters: semesters,
      semester: semester,
      periods: configured,
      courses: courses,
      schedules: schedules,
    );
  }

  SemesterEntry? _selectedSemester(List<SemesterEntry> semesters) {
    if (semesters.isEmpty) return null;
    if (selectedSemesterId == null) return semesters.first;
    return semesters
        .where((semester) => semester.id == selectedSemesterId)
        .firstOrNull;
  }

  void _refresh() => ref.read(refreshProvider.notifier).state++;

  Future<void> _showDesktopActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('添加到手机桌面'),
            subtitle: Text('动态组件可直接显示下一节课程；快捷入口只负责打开课程表。'),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('动态课程组件'),
            subtitle: const Text('推荐：显示课程、教师、教室和时间'),
            onTap: () => Navigator.pop(context, 'widget'),
          ),
          ListTile(
            leading: const Icon(Icons.launch_outlined),
            title: const Text('课程表快捷入口'),
            onTap: () => Navigator.pop(context, 'shortcut'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'widget') {
      try {
        await WidgetSnapshotService(ref.read(databaseProvider)).refresh();
      } on Object {
        // The system pin dialog is still useful when snapshot refresh fails.
      }
    }
    final result = action == 'widget'
        ? await CourseShortcutService.requestCourseWidget()
        : await CourseShortcutService.requestCourseShortcut();
    if (!context.mounted) return;
    final message = switch (result) {
      CourseShortcutRequest.requested => '已向系统发送添加请求，请在桌面确认',
      CourseShortcutRequest.unsupported => action == 'widget'
          ? '当前桌面不支持自动固定组件，请长按桌面后手动添加 LifeHub 课程组件'
          : '当前桌面不支持固定快捷入口',
      CourseShortcutRequest.failed => '未能添加到桌面，请稍后重试',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editSemesterSettings(
    BuildContext context,
    CourseRepository repository,
    SemesterEntry? current,
  ) async {
    final now = DateTime.now();
    final name = TextEditingController(
      text: current?.name ?? '${now.year} 学年课程表',
    );
    final weeks = TextEditingController(
      text: current == null ? '' : '${current.totalWeeks}',
    );
    var start = current == null
        ? nextMondayOnOrAfter(DateTime(now.year, now.month, now.day))
        : DateKeys.fromLocalDateKey(current.startDate);
    final startDate = TextEditingController(text: _date(start));
    var periods = current == null
        ? [...CourseRepository.defaultPeriods.take(6)]
        : [...await repository.loadPeriods(current.id)];
    if (!context.mounted) return;
    final draft = await showDialog<_SemesterSettingsDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title: Text(current == null ? '设置课程表' : '课程表设置'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '学期名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: startDate,
              readOnly: true,
              decoration: InputDecoration(
                labelText: '学期开始日期',
                suffixIcon: IconButton(
                  tooltip: '选择日期',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      barrierDismissible: false,
                    );
                    if (value != null) {
                      setDialogState(() {
                        start = value;
                        startDate.text = _date(value);
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weeks,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '学期总周数',
                hintText: '例如 16、18 或 20 周',
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('每天节数', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: '减少一节',
                onPressed: periods.length <= 1
                    ? null
                    : () => setDialogState(() => periods.removeLast()),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${periods.length}'),
              IconButton(
                tooltip: '增加一节',
                onPressed: periods.length >= 15
                    ? null
                    : () {
                        final previous = periods.last;
                        final startMinutes = previous.endMinutes + 10;
                        setDialogState(() => periods.add(CoursePeriod(
                              startMinutes: startMinutes,
                              endMinutes: startMinutes + 50,
                            )));
                      },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            ...periods.indexed.map((entry) {
              final index = entry.$1;
              final period = entry.$2;
              return Card(
                child: ListTile(
                  title: Text('第 ${index + 1} 节'),
                  subtitle: Text(
                      '${_minutes(period.startMinutes)}–${_minutes(period.endMinutes)}'),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final changed = await _pickPeriod(context, period);
                    if (changed != null) {
                      setDialogState(() => periods[index] = changed);
                    }
                  },
                ),
              );
            }),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final totalWeeks = int.tryParse(weeks.text.trim());
                if (name.text.trim().isEmpty ||
                    totalWeeks == null ||
                    totalWeeks < 1 ||
                    totalWeeks > 52 ||
                    !_periodsValid(periods)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请检查学期周数和每节课时间')),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _SemesterSettingsDraft(
                    name: name.text.trim(),
                    start: start,
                    totalWeeks: totalWeeks,
                    periods: periods,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    weeks.dispose();
    startDate.dispose();
    if (draft == null) return;
    final normalizedStart = nextMondayOnOrAfter(draft.start);
    final end = normalizedStart.add(Duration(days: draft.totalWeeks * 7 - 1));
    final semesterDraft = SemesterDraft(
      name: draft.name,
      start: normalizedStart,
      end: end,
      totalWeeks: draft.totalWeeks,
    );
    final semester = current == null
        ? await repository.createSemester(semesterDraft)
        : await repository.updateSemester(current.id, semesterDraft);
    await repository.savePeriods(semester.id, draft.periods);
    if (mounted) {
      setState(() {
        selectedSemesterId = semester.id;
        weekStart = null;
      });
      _refresh();
    }
  }

  Future<CoursePeriod?> _pickPeriod(
      BuildContext context, CoursePeriod current) async {
    final start = await showTimePicker(
      context: context,
      helpText: '开始时间',
      initialTime: TimeOfDay(
        hour: current.startMinutes ~/ 60,
        minute: current.startMinutes % 60,
      ),
      barrierDismissible: false,
    );
    if (start == null || !context.mounted) return null;
    final end = await showTimePicker(
      context: context,
      helpText: '结束时间',
      initialTime: TimeOfDay(
        hour: current.endMinutes ~/ 60,
        minute: current.endMinutes % 60,
      ),
      barrierDismissible: false,
    );
    if (end == null) return null;
    final value = CoursePeriod(
      startMinutes: start.hour * 60 + start.minute,
      endMinutes: end.hour * 60 + end.minute,
    );
    if (value.endMinutes <= value.startMinutes && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return null;
    }
    return value;
  }

  Future<void> _editCourseCell(
    BuildContext context,
    CourseRepository repository,
    _TimetableData data,
    int weekday,
    CoursePeriod period,
    _CellValue? existing,
  ) async {
    final semester = data.semester!;
    final name = TextEditingController(text: existing?.course.name ?? '');
    final teacher = TextEditingController(text: existing?.course.teacher ?? '');
    final room = TextEditingController(text: existing?.course.room ?? '');
    final selectedWeeks = existing == null
        ? {for (var week = 1; week <= semester.totalWeeks; week++) week}
        : DateKeys.parseWeekSet(
            existing.schedule.weekSet,
            totalWeeks: semester.totalWeeks,
          );
    var startWeek = selectedWeeks.reduce((a, b) => a < b ? a : b);
    var endWeek = selectedWeeks.reduce((a, b) => a > b ? a : b);
    var parity = selectedWeeks.every((week) => week.isOdd)
        ? WeekParity.odd
        : selectedWeeks.every((week) => week.isEven)
            ? WeekParity.even
            : WeekParity.all;
    var startPeriodIndex = existing == null
        ? data.periods.indexOf(period)
        : data.periods.indexWhere(
            (value) => value.startMinutes == existing.schedule.startMinutes,
          );
    var endPeriodIndex = existing == null
        ? startPeriodIndex
        : data.periods.indexWhere(
            (value) => value.endMinutes == existing.schedule.endMinutes,
          );
    if (startPeriodIndex < 0) startPeriodIndex = 0;
    if (endPeriodIndex < startPeriodIndex) endPeriodIndex = startPeriodIndex;
    var color = existing?.course.color ?? _courseColors.first;
    final result = await showDialog<_CourseEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title:
              Text(existing == null ? '添加课程 · 周${_weekday(weekday)}' : '修改课程'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '课程名称',
                counterText: '',
              ),
            ),
            TextField(
              controller: teacher,
              decoration: const InputDecoration(labelText: '老师（可选）'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: room,
              decoration: const InputDecoration(labelText: '教室（可选）'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: color,
              decoration: const InputDecoration(labelText: '课程颜色'),
              items: _courseColors
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Row(children: [
                          CircleAvatar(
                              radius: 8, backgroundColor: _parseColor(value)),
                          const SizedBox(width: 10),
                          Text(_colorName(value)),
                        ]),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setDialogState(() => color = value ?? color),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: startWeek,
                  decoration: const InputDecoration(labelText: '开始周'),
                  items: [
                    for (var week = 1; week <= semester.totalWeeks; week++)
                      DropdownMenuItem(value: week, child: Text('$week 周')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    startWeek = value ?? startWeek;
                    if (endWeek < startWeek) endWeek = startWeek;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: endWeek,
                  decoration: const InputDecoration(labelText: '结束周'),
                  items: [
                    for (var week = 1; week <= semester.totalWeeks; week++)
                      DropdownMenuItem(value: week, child: Text('$week 周')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    endWeek = value ?? endWeek;
                    if (startWeek > endWeek) startWeek = endWeek;
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            SegmentedButton<WeekParity>(
              segments: const [
                ButtonSegment(value: WeekParity.all, label: Text('全部')),
                ButtonSegment(value: WeekParity.odd, label: Text('单周')),
                ButtonSegment(value: WeekParity.even, label: Text('双周')),
              ],
              selected: {parity},
              onSelectionChanged: (value) =>
                  setDialogState(() => parity = value.single),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: startPeriodIndex,
                  decoration: const InputDecoration(labelText: '开始节次'),
                  items: [
                    for (var index = 0; index < data.periods.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text('第 ${index + 1} 节'),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    startPeriodIndex = value ?? startPeriodIndex;
                    if (endPeriodIndex < startPeriodIndex) {
                      endPeriodIndex = startPeriodIndex;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: endPeriodIndex,
                  decoration: const InputDecoration(labelText: '结束节次'),
                  items: [
                    for (var index = 0; index < data.periods.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text('第 ${index + 1} 节'),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    endPeriodIndex = value ?? endPeriodIndex;
                    if (startPeriodIndex > endPeriodIndex) {
                      startPeriodIndex = endPeriodIndex;
                    }
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '周${_weekday(weekday)} · '
                '${_minutes(data.periods[startPeriodIndex].startMinutes)}–'
                '${_minutes(data.periods[endPeriodIndex].endMinutes)}',
              ),
            ),
          ]),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _CourseEditResult.delete()),
                child: Text('删除课程',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  return;
                }
                final weeks = weeksForRange(
                  startWeek: startWeek,
                  endWeek: endWeek,
                  parity: parity,
                );
                if (weeks.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('所选范围内没有对应单双周')),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _CourseEditResult.save(
                    name: name.text.trim(),
                    teacher: teacher.text.trim(),
                    room: room.text.trim(),
                    color: color,
                    weekSet: formatWeekSet(weeks),
                    startMinutes: data.periods[startPeriodIndex].startMinutes,
                    endMinutes: data.periods[endPeriodIndex].endMinutes,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    teacher.dispose();
    room.dispose();
    if (result == null) return;
    if (!context.mounted) return;
    if (result.delete) {
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('删除课程？'),
              content: Text('“${existing!.course.name}”及其全部上课时间都会删除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      await repository.deleteCourse(existing!.course.id);
    } else {
      try {
        final draft = CourseDraft(
          name: result.name!,
          semesterId: semester.id,
          teacher: result.teacher,
          room: result.room,
          color: result.color!,
        );
        final scheduleDraft = CourseScheduleDraft(
          courseId: existing?.course.id ?? '',
          weekday: weekday,
          startMinutes: result.startMinutes!,
          endMinutes: result.endMinutes!,
          weekSet: result.weekSet!,
        );
        await repository.saveCourseWithSchedule(
          course: draft,
          schedule: scheduleDraft,
          courseId: existing?.course.id,
          scheduleId: existing?.schedule.id,
        );
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('课程保存失败：$error')),
          );
        }
        return;
      }
    }
    _refresh();
    await refreshReminders(ref);
  }

  Future<void> _showCourseDetails(
      BuildContext context, _CellValue value) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                  backgroundColor: _parseColor(value.course.color)),
              title: Text(value.course.name),
              subtitle: Text([
                if (value.course.teacher != null) value.course.teacher!,
                if (value.course.room != null) value.course.room!,
                '第 ${value.schedule.weekSet} 周',
              ].join(' · ')),
              trailing: IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AcademicCoursePage(courseId: value.course.id),
                  ),
                );
              },
              icon: const Icon(Icons.school_outlined),
              label: const Text('打开学业中心'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TimetableData {
  const _TimetableData({
    required this.semesters,
    this.semester,
    this.periods = const [],
    this.courses = const [],
    this.schedules = const [],
  });

  final List<SemesterEntry> semesters;
  final SemesterEntry? semester;
  final List<CoursePeriod> periods;
  final List<CourseEntry> courses;
  final List<CourseScheduleEntry> schedules;
}

class _SemesterBar extends StatelessWidget {
  const _SemesterBar({
    required this.semester,
    required this.semesters,
    required this.dates,
    required this.onSemesterChanged,
    required this.previousWeek,
    required this.nextWeek,
    required this.today,
  });

  final SemesterEntry semester;
  final List<SemesterEntry> semesters;
  final List<DateTime> dates;
  final ValueChanged<String> onSemesterChanged;
  final VoidCallback previousWeek;
  final VoidCallback nextWeek;
  final VoidCallback today;

  @override
  Widget build(BuildContext context) {
    final start = DateKeys.fromLocalDateKey(semester.startDate);
    final end = DateKeys.fromLocalDateKey(semester.endDate);
    final week = DateKeys.semesterWeek(dates.first, start, end) ??
        DateKeys.semesterWeek(dates.last, start, end);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(children: [
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: semester.id,
              isExpanded: true,
              items: semesters
                  .map((value) => DropdownMenuItem(
                      value: value.id, child: Text(value.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) onSemesterChanged(value);
              },
            ),
          ),
        ),
        if (week != null) Chip(label: Text('第 $week 周')),
        IconButton(
            tooltip: '上一周',
            onPressed: previousWeek,
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            tooltip: '下一周',
            onPressed: nextWeek,
            icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: today, child: const Text('本周')),
      ]),
    );
  }
}

class _Timetable extends StatelessWidget {
  const _Timetable({
    required this.data,
    required this.dates,
    required this.editing,
    required this.onCellTap,
  });

  final _TimetableData data;
  final List<DateTime> dates;
  final bool editing;
  final void Function(int weekday, CoursePeriod period, _CellValue? value)
      onCellTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    const labelWidth = 58.0;
    const rowHeight = 68.0;
    final values = _activeValues(data, dates);
    final coveredCells = <(int, int)>{};
    for (final value in values) {
      final span = CoursePeriodSpan.fromMinutes(
        periods: data.periods,
        startMinutes: value.schedule.startMinutes,
        endMinutes: value.schedule.endMinutes,
      );
      for (var index = span.startIndex; index <= span.endIndex; index++) {
        coveredCells.add((value.schedule.weekday, index));
      }
    }
    return Column(children: [
      Row(children: [
        const SizedBox(
          width: 58,
          height: 54,
          child: Center(child: Text('节次\n时间', textAlign: TextAlign.center)),
        ),
        ...dates.map((date) {
          final active = _sameDay(date, today);
          return Expanded(
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Text(
                '周${_weekday(date.weekday)}\n${date.month}/${date.day}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }),
      ]),
      LayoutBuilder(builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - labelWidth) / 7;
        final height = data.periods.length * rowHeight;
        return SizedBox(
          height: height,
          child: Stack(children: [
            for (final entry in data.periods.indexed)
              Positioned(
                left: 0,
                top: entry.$1 * rowHeight,
                width: labelWidth,
                height: rowHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '第${entry.$1 + 1}节\n'
                    '${_minutes(entry.$2.startMinutes)}\n'
                    '${_minutes(entry.$2.endMinutes)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            for (final entry in data.periods.indexed)
              for (final date in dates)
                if (!coveredCells.contains((date.weekday, entry.$1)))
                  Positioned(
                    left: labelWidth + (date.weekday - 1) * columnWidth,
                    top: entry.$1 * rowHeight,
                    width: columnWidth,
                    height: rowHeight,
                    child: InkWell(
                      onTap: editing
                          ? () => onCellTap(date.weekday, entry.$2, null)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _sameDay(date, today)
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: .28)
                              : Colors.transparent,
                          border: Border.all(
                            color: _sameDay(date, today)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: editing
                            ? Icon(
                                Icons.add,
                                size: 16,
                                color: Theme.of(context).colorScheme.outline,
                              )
                            : null,
                      ),
                    ),
                  ),
            for (final value in values)
              Builder(builder: (context) {
                final span = CoursePeriodSpan.fromMinutes(
                  periods: data.periods,
                  startMinutes: value.schedule.startMinutes,
                  endMinutes: value.schedule.endMinutes,
                );
                final column = value.schedule.weekday - 1;
                return Positioned(
                  left: labelWidth + column * columnWidth + 2,
                  top: span.startIndex * rowHeight + 2,
                  width: columnWidth - 4,
                  height: span.length * rowHeight - 4,
                  child: Material(
                    key: ValueKey('course-block-${value.course.id}'),
                    color: Color.alphaBlend(
                      _parseColor(value.course.color).withValues(alpha: .30),
                      Theme.of(context).colorScheme.surface,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onCellTap(
                        value.schedule.weekday,
                        data.periods[span.startIndex],
                        value,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              value.course.name,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (value.course.teacher != null)
                              Text(
                                value.course.teacher!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 8),
                              ),
                            if (value.course.room != null)
                              Text(
                                value.course.room!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 8),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ]),
        );
      }),
    ]);
  }
}

class _CellValue {
  const _CellValue({required this.course, required this.schedule});
  final CourseEntry course;
  final CourseScheduleEntry schedule;
}

List<_CellValue> _activeValues(_TimetableData data, List<DateTime> dates) {
  final semester = data.semester!;
  final start = DateKeys.fromLocalDateKey(semester.startDate);
  final end = DateKeys.fromLocalDateKey(semester.endDate);
  final courses = {for (final course in data.courses) course.id: course};
  final result = <_CellValue>[];
  for (final schedule in data.schedules) {
    final course = courses[schedule.courseId];
    if (course == null) continue;
    final date = dates[schedule.weekday - 1];
    final week = DateKeys.semesterWeek(date, start, end);
    if (week == null ||
        !DateKeys.parseWeekSet(schedule.weekSet,
                totalWeeks: semester.totalWeeks)
            .contains(week)) {
      continue;
    }
    final excluded = (jsonDecode(schedule.excludedDates) as List<dynamic>)
        .map((value) => value as int)
        .toSet();
    if (excluded.contains(DateKeys.toLocalDateKey(date))) continue;
    try {
      CoursePeriodSpan.fromMinutes(
        periods: data.periods,
        startMinutes: schedule.startMinutes,
        endMinutes: schedule.endMinutes,
      );
    } on ArgumentError {
      continue;
    }
    result.add(_CellValue(course: course, schedule: schedule));
  }
  return result;
}

class _SemesterSettingsDraft {
  const _SemesterSettingsDraft({
    required this.name,
    required this.start,
    required this.totalWeeks,
    required this.periods,
  });
  final String name;
  final DateTime start;
  final int totalWeeks;
  final List<CoursePeriod> periods;
}

class _CourseEditResult {
  const _CourseEditResult.delete()
      : delete = true,
        name = null,
        teacher = null,
        room = null,
        color = null,
        weekSet = null,
        startMinutes = null,
        endMinutes = null;

  const _CourseEditResult.save({
    required this.name,
    required this.teacher,
    required this.room,
    required this.color,
    required this.weekSet,
    required this.startMinutes,
    required this.endMinutes,
  }) : delete = false;

  final bool delete;
  final String? name;
  final String? teacher;
  final String? room;
  final String? color;
  final String? weekSet;
  final int? startMinutes;
  final int? endMinutes;
}

class _EmptyTimetable extends StatelessWidget {
  const _EmptyTimetable({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_view_week_outlined, size: 64),
            const SizedBox(height: 16),
            Text('先设置学期、周数和每天的节次时间',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.tune),
              label: const Text('课程表设置'),
            ),
          ]),
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.retry});
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 12),
            const Text('课程表加载失败'),
            const SizedBox(height: 4),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: retry, child: const Text('重试')),
          ]),
        ),
      );
}

bool _periodsValid(List<CoursePeriod> periods) {
  if (periods.isEmpty) return false;
  var previousEnd = -1;
  for (final period in periods) {
    if (period.endMinutes <= period.startMinutes ||
        period.startMinutes < previousEnd) {
      return false;
    }
    previousEnd = period.endMinutes;
  }
  return true;
}

DateTime _initialWeekStart(SemesterEntry semester) {
  final start = DateKeys.fromLocalDateKey(semester.startDate);
  final end = DateKeys.fromLocalDateKey(semester.endDate);
  final now = DateTime.now();
  final base = now.isBefore(start) || now.isAfter(end) ? start : now;
  final day = DateTime(base.year, base.month, base.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekday(int value) =>
    const ['一', '二', '三', '四', '五', '六', '日'][value - 1];

String _minutes(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

const _courseColors = <String>[
  '#4F46E5',
  '#EF4444',
  '#F97316',
  '#EAB308',
  '#22C55E',
  '#14B8A6',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
];

Color _parseColor(String source) {
  final hex = source.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

String _colorName(String value) => switch (value) {
      '#4F46E5' => '靛蓝',
      '#EF4444' => '红色',
      '#F97316' => '橙色',
      '#EAB308' => '黄色',
      '#22C55E' => '绿色',
      '#14B8A6' => '青色',
      '#3B82F6' => '蓝色',
      '#8B5CF6' => '紫色',
      '#EC4899' => '粉色',
      _ => '自定义',
    };
