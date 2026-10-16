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
import 'package:lifehub/features/course/presentation/academic_center_page.dart';
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
            tooltip: '学业中心',
            icon: const Icon(Icons.school_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AcademicCenterPage(
                    semesterId: selectedSemesterId,
                  ),
                ),
              );
              _refresh();
            },
          ),
          TextButton(
            onPressed: () => setState(() => editing = !editing),
            child: Text(editing ? '完成' : '编辑'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (val) async {
              if (val == 'settings') {
                final semesters = await repository.semesters();
                if (!context.mounted) return;
                final current = _selectedSemester(semesters);
                await _editSemesterSettings(context, repository, current);
              } else if (val == 'desktop') {
                _showDesktopActions(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20),
                    SizedBox(width: 12),
                    Text('课程表设置'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'desktop',
                child: Row(
                  children: [
                    Icon(Icons.add_to_home_screen_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('添加到手机桌面'),
                  ],
                ),
              ),
            ],
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
          final now = DateTime.now();
          final todayLocalDateKey = DateKeys.toLocalDateKey(now);
          final semStart = DateKeys.fromLocalDateKey(semester.startDate);
          final semEnd = DateKeys.fromLocalDateKey(semester.endDate);
          final currentWeek = DateKeys.semesterWeek(now, semStart, semEnd);
          _CellValue? upcomingClass;
          int? upcomingDiffMinutes;
          bool isHappeningNow = false;

          if (currentWeek != null) {
            final coursesMap = {for (final c in data.courses) c.id: c};
            final todaySchedules = data.schedules.where((s) {
              if (s.weekday != now.weekday) return false;
              final weeks = DateKeys.parseWeekSet(s.weekSet,
                  totalWeeks: semester.totalWeeks);
              if (!weeks.contains(currentWeek)) return false;
              final excluded = (jsonDecode(s.excludedDates) as List<dynamic>)
                  .map((v) => v as int)
                  .toSet();
              return !excluded.contains(todayLocalDateKey);
            }).toList();

            final currentMinutes = now.hour * 60 + now.minute;
            for (final s in todaySchedules) {
              final course = coursesMap[s.courseId];
              if (course == null) continue;
              if (currentMinutes >= s.startMinutes &&
                  currentMinutes < s.endMinutes) {
                upcomingClass = _CellValue(course: course, schedule: s);
                upcomingDiffMinutes = s.endMinutes - currentMinutes;
                isHappeningNow = true;
                break;
              } else if (s.startMinutes > currentMinutes &&
                  s.startMinutes - currentMinutes <= 60) {
                if (upcomingClass == null ||
                    s.startMinutes - currentMinutes <
                        (upcomingDiffMinutes ?? 999)) {
                  upcomingClass = _CellValue(course: course, schedule: s);
                  upcomingDiffMinutes = s.startMinutes - currentMinutes;
                  isHappeningNow = false;
                }
              }
            }
          }

          final coursesById = {for (final course in data.courses) course.id: course};
          final unmatchedCourses = <_CellValue>[
            for (final schedule in data.schedules)
              if (!_hasPeriodSpan(data.periods, schedule) &&
                  coursesById.containsKey(schedule.courseId))
                _CellValue(course: coursesById[schedule.courseId]!, schedule: schedule),
          ];
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
            if (upcomingClass != null)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isHappeningNow
                      ? Colors.green.shade50
                      : Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHappeningNow
                        ? Colors.green.shade300
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isHappeningNow ? Icons.school_outlined : Icons.alarm,
                      color: isHappeningNow
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isHappeningNow
                            ? '正在上课：${upcomingClass.course.name}${upcomingClass.course.room != null && upcomingClass.course.room!.isNotEmpty ? ' · ${upcomingClass.course.room}' : ''}（还有 $upcomingDiffMinutes 分钟下课）'
                            : '即将上课：${upcomingClass.course.name}${upcomingClass.course.room != null && upcomingClass.course.room!.isNotEmpty ? ' · ${upcomingClass.course.room}' : ''}（$upcomingDiffMinutes 分钟后）',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isHappeningNow
                              ? Colors.green.shade900
                              : Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                child: Column(children: [
                  if (unmatchedCourses.isNotEmpty)
                    Card(
                      child: Column(children: [
                        const ListTile(
                          title: Text('未匹配节次的排课'),
                          subtitle: Text('原上课时间已保留，可在编辑模式调整节次。'),
                        ),
                        for (final value in unmatchedCourses)
                          ListTile(
                            title: Text(value.course.name),
                            subtitle: Text('周${_weekday(value.schedule.weekday)} · '
                                '${_minutes(value.schedule.startMinutes)}–'
                                '${_minutes(value.schedule.endMinutes)}'),
                            trailing: editing ? const Icon(Icons.edit_outlined) : null,
                            onTap: () {
                              if (editing) {
                                _editCourseCell(context, repository, data,
                                    value.schedule.weekday, data.periods.first, value);
                              } else {
                                _showCourseDetails(context, value);
                              }
                            },
                          ),
                      ]),
                    ),
                  _Timetable(
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
                ]),
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
        await WidgetSnapshotService(ref.read(databaseProvider)).refresh(
          preferences: ref.read(sharedPreferencesProvider),
        );
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
      await refreshReminders(ref);
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
    var weeksChanged = false;
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
    var useExistingTime = existing != null &&
        !_hasPeriodSpan(data.periods, existing.schedule);
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('全学期'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setDialogState(() {
                    weeksChanged = true;
                    startWeek = 1;
                    endWeek = semester.totalWeeks;
                    parity = WeekParity.all;
                  }),
                ),
                ActionChip(
                  label: const Text('前半学期'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setDialogState(() {
                    weeksChanged = true;
                    startWeek = 1;
                    endWeek = (semester.totalWeeks / 2).ceil();
                    parity = WeekParity.all;
                  }),
                ),
                ActionChip(
                  label: const Text('后半学期'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setDialogState(() {
                    weeksChanged = true;
                    startWeek = (semester.totalWeeks / 2).ceil() + 1;
                    endWeek = semester.totalWeeks;
                    parity = WeekParity.all;
                  }),
                ),
                ActionChip(
                  label: const Text('单周'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setDialogState(() {
                    weeksChanged = true;
                    parity = WeekParity.odd;
                  }),
                ),
                ActionChip(
                  label: const Text('双周'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setDialogState(() {
                    weeksChanged = true;
                    parity = WeekParity.even;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('start_week_$startWeek'),
                  initialValue: startWeek,
                  decoration: const InputDecoration(labelText: '开始周'),
                  items: [
                    for (var week = 1; week <= semester.totalWeeks; week++)
                      DropdownMenuItem(value: week, child: Text('$week 周')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    weeksChanged = true;
                    startWeek = value ?? startWeek;
                    if (endWeek < startWeek) endWeek = startWeek;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('end_week_$endWeek'),
                  initialValue: endWeek,
                  decoration: const InputDecoration(labelText: '结束周'),
                  items: [
                    for (var week = 1; week <= semester.totalWeeks; week++)
                      DropdownMenuItem(value: week, child: Text('$week 周')),
                  ],
                  onChanged: (value) => setDialogState(() {
                    weeksChanged = true;
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
              onSelectionChanged: (value) => setDialogState(() {
                weeksChanged = true;
                parity = value.single;
              }),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('start_period_${useExistingTime ? 'custom' : startPeriodIndex}'),
                  initialValue: useExistingTime ? null : startPeriodIndex,
                  decoration: const InputDecoration(labelText: '开始节次'),
                  items: [
                    for (var index = 0; index < data.periods.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text('第 ${index + 1} 节'),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    useExistingTime = false;
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
                  key: ValueKey('end_period_${useExistingTime ? 'custom' : endPeriodIndex}'),
                  initialValue: useExistingTime ? null : endPeriodIndex,
                  decoration: const InputDecoration(labelText: '结束节次'),
                  items: [
                    for (var index = 0; index < data.periods.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text('第 ${index + 1} 节'),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    useExistingTime = false;
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
                '${_minutes(useExistingTime ? existing!.schedule.startMinutes : data.periods[startPeriodIndex].startMinutes)}–'
                '${_minutes(useExistingTime ? existing!.schedule.endMinutes : data.periods[endPeriodIndex].endMinutes)}',
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
                    weekSet: existing != null && !weeksChanged
                        ? existing.schedule.weekSet
                        : formatWeekSet(weeks),
                    startMinutes: useExistingTime ? existing!.schedule.startMinutes
                        : data.periods[startPeriodIndex].startMinutes,
                    endMinutes: useExistingTime ? existing!.schedule.endMinutes
                        : data.periods[endPeriodIndex].endMinutes,
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
          excludedDateKeys: existing == null ? const {} :
              (jsonDecode(existing.schedule.excludedDates) as List<dynamic>)
                  .cast<int>().toSet(),
          roomOverride: existing?.schedule.roomOverride,
          reminderMinutes: existing?.schedule.reminderMinutes,
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
                    builder: (_) => AcademicCenterPage(
                      semesterId: selectedSemesterId,
                      initialCourseId: value.course.id,
                    ),
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
    const headerHeight = 54.0;
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

    final activeDayIndex = dates.indexWhere((d) => _sameDay(d, today));

    // 计算被跨节课程覆盖的节次水平分界线（避免多节课程中间露出横线）
    final coveredDividers = <(int col, int periodIndex)>{};
    for (final value in values) {
      final span = CoursePeriodSpan.fromMinutes(
        periods: data.periods,
        startMinutes: value.schedule.startMinutes,
        endMinutes: value.schedule.endMinutes,
      );
      if (span.length > 1) {
        final col = value.schedule.weekday - 1;
        for (var i = span.startIndex + 1; i <= span.endIndex; i++) {
          coveredDividers.add((col, i));
        }
      }
    }

    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth = (constraints.maxWidth - labelWidth) / 7;
      final bodyHeight = data.periods.length * rowHeight;
      final totalHeight = headerHeight + bodyHeight;
      final colorScheme = Theme.of(context).colorScheme;

      return CustomPaint(
        painter: _TimetableGridPainter(
          labelWidth: labelWidth,
          columnWidth: columnWidth,
          headerHeight: headerHeight,
          rowHeight: rowHeight,
          periodCount: data.periods.length,
          activeDayIndex: activeDayIndex,
          coveredDividers: coveredDividers,
          lineColor: colorScheme.outlineVariant,
          headerBgColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          activeDayBgColor: colorScheme.primaryContainer.withValues(alpha: 0.22),
          activeHeaderBgColor: colorScheme.primaryContainer.withValues(alpha: 0.65),
        ),
        child: SizedBox(
          width: constraints.maxWidth,
          height: totalHeight,
          child: Stack(children: [
            // 表头左上角：节次/时间
            const Positioned(
              left: 0,
              top: 0,
              width: labelWidth,
              height: headerHeight,
              child: Center(
                child: Text(
                  '节次\n时间',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
            // 表头星期与日期
            for (final (index, date) in dates.indexed)
              Positioned(
                left: labelWidth + index * columnWidth,
                top: 0,
                width: columnWidth,
                height: headerHeight,
                child: Center(
                  child: Text(
                    '周${_weekday(date.weekday)}\n${date.month}/${date.day}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _sameDay(date, today)
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            // 节次侧边栏（左侧第1节、第2节...）
            for (final entry in data.periods.indexed)
              Positioned(
                left: 0,
                top: headerHeight + entry.$1 * rowHeight,
                width: labelWidth,
                height: rowHeight,
                child: Center(
                  child: Text(
                    '第${entry.$1 + 1}节\n'
                    '${_minutes(entry.$2.startMinutes)}\n'
                    '${_minutes(entry.$2.endMinutes)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            // 空空格子点击响应与编辑模式加号
            for (final entry in data.periods.indexed)
              for (final date in dates)
                if (!coveredCells.contains((date.weekday, entry.$1)))
                  Positioned(
                    left: labelWidth + (date.weekday - 1) * columnWidth,
                    top: headerHeight + entry.$1 * rowHeight,
                    width: columnWidth,
                    height: rowHeight,
                    child: InkWell(
                      onTap: editing
                          ? () => onCellTap(date.weekday, entry.$2, null)
                          : null,
                      child: Center(
                        child: editing
                            ? Icon(
                                Icons.add,
                                size: 16,
                                color: colorScheme.outline,
                              )
                            : null,
                      ),
                    ),
                  ),
            // 课程卡片渲染
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
                  top: headerHeight + span.startIndex * rowHeight + 2,
                  width: columnWidth - 4,
                  height: span.length * rowHeight - 4,
                  child: Material(
                    key: ValueKey('course-block-${value.course.id}'),
                    color: Color.alphaBlend(
                      _parseColor(value.course.color).withValues(alpha: .30),
                      colorScheme.surface,
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: columnWidth - 8),
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
                    ),
                  ),
                );
              }),
          ]),
        ),
      );
    });
  }
}

class _TimetableGridPainter extends CustomPainter {
  const _TimetableGridPainter({
    required this.labelWidth,
    required this.columnWidth,
    required this.headerHeight,
    required this.rowHeight,
    required this.periodCount,
    required this.activeDayIndex,
    required this.coveredDividers,
    required this.lineColor,
    required this.headerBgColor,
    required this.activeDayBgColor,
    required this.activeHeaderBgColor,
  });

  final double labelWidth;
  final double columnWidth;
  final double headerHeight;
  final double rowHeight;
  final int periodCount;
  final int activeDayIndex;
  final Set<(int col, int periodIndex)> coveredDividers;
  final Color lineColor;
  final Color headerBgColor;
  final Color activeDayBgColor;
  final Color activeHeaderBgColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyHeight = periodCount * rowHeight;
    final totalHeight = headerHeight + bodyHeight;
    final totalWidth = size.width;

    // 1. 填充表头背景
    final headerPaint = Paint()
      ..color = headerBgColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, headerHeight), headerPaint);

    // 2. 高亮今天所在列（温和半透明）
    if (activeDayIndex >= 0 && activeDayIndex < 7) {
      final left = labelWidth + activeDayIndex * columnWidth;
      final activeHeaderPaint = Paint()
        ..color = activeHeaderBgColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, columnWidth, headerHeight),
        activeHeaderPaint,
      );

      final activeBodyPaint = Paint()
        ..color = activeDayBgColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(left, headerHeight, columnWidth, bodyHeight),
        activeBodyPaint,
      );
    }

    // 3. 统一绘制等宽分割网格线（无重叠，严格 0.8px）
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // 外框矩形
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, totalHeight), linePaint);

    // 表头横向分割线
    canvas.drawLine(
      Offset(0, headerHeight),
      Offset(totalWidth, headerHeight),
      linePaint,
    );

    // 各节次横向分割线（自动跳过被跨节课程覆盖的列区间，彻底消除内部多余横线）
    for (var i = 1; i < periodCount; i++) {
      final y = headerHeight + i * rowHeight;
      // 左侧节次栏始终绘制分界线
      canvas.drawLine(Offset(0, y), Offset(labelWidth, y), linePaint);
      // 右侧 7 列：如果该列当前分界线被跨节课程覆盖，则跳过不画
      for (var col = 0; col < 7; col++) {
        if (!coveredDividers.contains((col, i))) {
          final startX = labelWidth + col * columnWidth;
          final endX = startX + columnWidth;
          canvas.drawLine(Offset(startX, y), Offset(endX, y), linePaint);
        }
      }
    }

    // 纵向节次栏分割线
    canvas.drawLine(
      Offset(labelWidth, 0),
      Offset(labelWidth, totalHeight),
      linePaint,
    );

    // 纵向各星期列分割线
    for (var c = 1; c < 7; c++) {
      final x = labelWidth + c * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, totalHeight), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimetableGridPainter oldDelegate) {
    return oldDelegate.labelWidth != labelWidth ||
        oldDelegate.columnWidth != columnWidth ||
        oldDelegate.headerHeight != headerHeight ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.periodCount != periodCount ||
        oldDelegate.activeDayIndex != activeDayIndex ||
        oldDelegate.coveredDividers != coveredDividers ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.headerBgColor != headerBgColor ||
        oldDelegate.activeDayBgColor != activeDayBgColor ||
        oldDelegate.activeHeaderBgColor != activeHeaderBgColor;
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
    if (!_hasPeriodSpan(data.periods, schedule)) continue;
    result.add(_CellValue(course: course, schedule: schedule));
  }
  return result;
}

bool _hasPeriodSpan(List<CoursePeriod> periods, CourseScheduleEntry schedule) {
  try {
    CoursePeriodSpan.fromMinutes(
      periods: periods,
      startMinutes: schedule.startMinutes,
      endMinutes: schedule.endMinutes,
    );
    return true;
  } on ArgumentError {
    return false;
  }
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
