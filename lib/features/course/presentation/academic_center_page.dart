import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/shared/ui/actionable_empty_state.dart';

class AcademicCenterPage extends ConsumerStatefulWidget {
  const AcademicCenterPage({
    super.key,
    this.semesterId,
    this.initialCourseId,
  });

  final String? semesterId;
  final String? initialCourseId;

  @override
  ConsumerState<AcademicCenterPage> createState() => _AcademicCenterPageState();
}

class _AcademicCenterPageState extends ConsumerState<AcademicCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedCourseId;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _selectedCourseId = widget.initialCourseId;
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() => _revision++);
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF4F46E5);
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    } else if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return const Color(0xFF4F46E5);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final repository = AcademicRepository(db);

    return Scaffold(
      appBar: AppBar(
        title: const Text('学业中心'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.assignment_outlined), text: '作业'),
            Tab(icon: Icon(Icons.event_note_outlined), text: '考试'),
            Tab(icon: Icon(Icons.bookmarks_outlined), text: '资料'),
            Tab(icon: Icon(Icons.grade_outlined), text: '成绩'),
          ],
        ),
      ),
      body: FutureBuilder<GlobalAcademicOverview>(
        key: ValueKey(_revision),
        future: repository.globalOverview(semesterId: widget.semesterId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text('加载学业数据失败：${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final courses = data.courses;

          if (courses.isEmpty) {
            return ActionableEmptyState(
              icon: Icons.school_outlined,
              title: '暂无课程信息',
              message: '请先在课程表中添加本学期的课程，即可统一记录作业、考试、资料与成绩。',
              actionLabel: '返回课程表',
              onAction: () => Navigator.pop(context),
            );
          }

          // Filter by selected course
          final filteredAssignments = _selectedCourseId == null
              ? data.assignments
              : data.assignments
                  .where((a) => a.courseId == _selectedCourseId)
                  .toList();

          final filteredExams = _selectedCourseId == null
              ? data.exams
              : data.exams.where((e) => e.courseId == _selectedCourseId).toList();

          final filteredMaterials = _selectedCourseId == null
              ? data.materials
              : data.materials
                  .where((m) => m.courseId == _selectedCourseId)
                  .toList();

          final filteredGrades = _selectedCourseId == null
              ? data.grades
              : data.grades
                  .where((g) => g.courseId == _selectedCourseId)
                  .toList();

          final pendingAssignmentsCount = filteredAssignments.where((a) => !a.submitted).length;

          return Column(
            children: [
              // 0. Academic Overview Dashboard Card
              _buildAcademicOverviewCard(
                pendingAssignments: pendingAssignmentsCount,
                upcomingExams: filteredExams.length,
                materialCount: filteredMaterials.length,
                gradeCount: filteredGrades.length,
              ),

              // 1. Course Filter Chips Bar
              _buildCourseChips(courses),

              // 2. TabBarView for Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 0: Assignments
                    _buildAssignmentsTab(
                      repository,
                      filteredAssignments,
                      courses,
                    ),

                    // Tab 1: Exams
                    _buildExamsTab(
                      repository,
                      filteredExams,
                      courses,
                    ),

                    // Tab 2: Materials
                    _buildMaterialsTab(
                      repository,
                      filteredMaterials,
                      courses,
                    ),

                    // Tab 3: Grades
                    _buildGradesTab(
                      repository,
                      filteredGrades,
                      courses,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<GlobalAcademicOverview>(
        key: ValueKey('fab_$_revision'),
        future: repository.globalOverview(semesterId: widget.semesterId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.courses.isEmpty) {
            return const SizedBox.shrink();
          }
          final courses = snapshot.data!.courses;
          return _buildFabForCurrentTab(repository, courses);
        },
      ),
    );
  }

  Widget _buildAcademicOverviewCard({
    required int pendingAssignments,
    required int upcomingExams,
    required int materialCount,
    required int gradeCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            _buildStatItem(
              label: '待交作业',
              count: pendingAssignments,
              color: pendingAssignments > 0
                  ? Colors.orange.shade700
                  : colorScheme.onSurfaceVariant,
              icon: Icons.assignment_outlined,
              tabIndex: 0,
            ),
            _buildStatDivider(colorScheme),
            _buildStatItem(
              label: '即将考试',
              count: upcomingExams,
              color: upcomingExams > 0
                  ? Colors.red.shade700
                  : colorScheme.onSurfaceVariant,
              icon: Icons.event_note_outlined,
              tabIndex: 1,
            ),
            _buildStatDivider(colorScheme),
            _buildStatItem(
              label: '课件资料',
              count: materialCount,
              color: colorScheme.primary,
              icon: Icons.bookmarks_outlined,
              tabIndex: 2,
            ),
            _buildStatDivider(colorScheme),
            _buildStatItem(
              label: '成绩记录',
              count: gradeCount,
              color: Colors.green.shade700,
              icon: Icons.grade_outlined,
              tabIndex: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatDivider(ColorScheme colorScheme) {
    return Container(
      width: 0.8,
      height: 28,
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildStatItem({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required int tabIndex,
  }) {
    final isSelected = _tabController.index == tabIndex;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          _tabController.animateTo(tabIndex);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseChips(List<CourseEntry> courses) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              showCheckmark: false,
              label: Text('全部课程 (${courses.length})'),
              selected: _selectedCourseId == null,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCourseId = null);
                }
              },
            ),
            for (final c in courses) ...[
              const SizedBox(width: 8),
              FilterChip(
                showCheckmark: false,
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: _parseColor(c.color),
                ),
                label: Text(c.name),
                selected: _selectedCourseId == c.id,
                onSelected: (selected) {
                  setState(() {
                    _selectedCourseId = selected ? c.id : null;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ================= Tab 0: 作业 =================
  Widget _buildAssignmentsTab(
    AcademicRepository repo,
    List<GlobalAcademicAssignment> assignments,
    List<CourseEntry> courses,
  ) {
    if (assignments.isEmpty) {
      return ActionableEmptyState(
        icon: Icons.assignment_turned_in_outlined,
        title: _selectedCourseId == null ? '全部作业已完成' : '该课程暂无作业',
        message: '随手记录课后作业与实验报告，截止日期井然有序。',
        actionLabel: '添加作业',
        onAction: () => _showAddAssignmentDialog(repo, courses),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: assignments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = assignments[index];
        final now = DateTime.now();
        final isOverdue = item.dueAt != null &&
            item.dueAt!.isBefore(now) &&
            !item.submitted;

        return Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isOverdue
                  ? Colors.red.withValues(alpha: 0.4)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Checkbox(
              value: item.submitted,
              onChanged: (_) async {
                await repo.toggleAssignmentStatus(item.taskId);
                _refresh();
              },
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration:
                    item.submitted ? TextDecoration.lineThrough : null,
                color: item.submitted
                    ? Theme.of(context).hintColor
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _parseColor(item.courseColor)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.courseName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _parseColor(item.courseColor),
                        ),
                      ),
                    ),
                    if (item.submissionMethod != null)
                      Text(
                        '提交：${item.submissionMethod}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    if (item.deadlineLabel != null)
                      Text(
                        item.deadlineLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isOverdue ? Colors.red : Theme.of(context).hintColor,
                          fontWeight: isOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Theme.of(context).hintColor,
              onPressed: () => _confirmDelete(
                title: '删除作业',
                content: '确定要删除作业“${item.title}”吗？',
                onConfirm: () async {
                  await repo.deleteAssignment(item.taskId);
                  _refresh();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ================= Tab 1: 考试 =================
  Widget _buildExamsTab(
    AcademicRepository repo,
    List<GlobalAcademicExam> exams,
    List<CourseEntry> courses,
  ) {
    if (exams.isEmpty) {
      return ActionableEmptyState(
        icon: Icons.event_available_outlined,
        title: _selectedCourseId == null ? '近期没有考试' : '该课程暂无考试计划',
        message: '提前录入期中、期末与随堂测验，及时备考不慌乱。',
        actionLabel: '添加考试',
        onAction: () => _showAddExamDialog(repo, courses),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: exams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final exam = exams[index];
        final now = DateTime.now();
        final daysLeft = exam.start.difference(now).inDays;

        String countdownLabel;
        if (daysLeft < 0) {
          countdownLabel = '考试已结束';
        } else if (daysLeft == 0) {
          countdownLabel = '今天考试';
        } else {
          countdownLabel = '还有 $daysLeft 天';
        }

        return Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _parseColor(exam.courseColor)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        exam.courseName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _parseColor(exam.courseColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        exam.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: daysLeft <= 3 && daysLeft >= 0
                            ? Colors.red.withValues(alpha: 0.12)
                            : Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        countdownLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: daysLeft <= 3 && daysLeft >= 0
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 16, color: Theme.of(context).hintColor),
                    const SizedBox(width: 6),
                    Text(
                      exam.scheduleLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
                if (exam.location != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: Theme.of(context).hintColor),
                      const SizedBox(width: 6),
                      Text(
                        exam.location!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ],
                if (exam.notes != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '备注：${exam.notes}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                    onPressed: () => _confirmDelete(
                      title: '删除考试日程',
                      content: '确定要删除“${exam.title}”吗？',
                      onConfirm: () async {
                        await repo.deleteExam(exam.eventId);
                        _refresh();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= Tab 2: 资料 =================
  Widget _buildMaterialsTab(
    AcademicRepository repo,
    List<GlobalAcademicMaterial> materials,
    List<CourseEntry> courses,
  ) {
    if (materials.isEmpty) {
      return ActionableEmptyState(
        icon: Icons.menu_book_outlined,
        title: _selectedCourseId == null ? '暂无课程资料' : '该课程暂无学习资料',
        message: '沉淀各科讲义、复习大纲、参考资料与笔记，复习时一目了然。',
        actionLabel: '添加资料',
        onAction: () => _showAddMaterialDialog(repo, courses),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: materials.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final mat = materials[index];
        return Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showMaterialDetailDialog(mat, repo),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _parseColor(mat.courseColor)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          mat.courseName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _parseColor(mat.courseColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mat.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Theme.of(context).hintColor,
                        onPressed: () => _confirmDelete(
                          title: '删除课程资料',
                          content: '确定要删除“${mat.title}”吗？',
                          onConfirm: () async {
                            await repo.deleteMaterial(mat.materialId);
                            _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (mat.content != null && mat.content!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      mat.content!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).hintColor,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ================= Tab 3: 成绩 =================
  Widget _buildGradesTab(
    AcademicRepository repo,
    List<GlobalAcademicGrade> grades,
    List<CourseEntry> courses,
  ) {
    if (grades.isEmpty) {
      return ActionableEmptyState(
        icon: Icons.auto_graph_outlined,
        title: _selectedCourseId == null ? '暂无成绩记录' : '该课程暂无成绩记录',
        message: '录入平时作业、测验与期末成绩，随时了解自己的学业表现。',
        actionLabel: '录入成绩',
        onAction: () => _showAddGradeDialog(repo, courses),
      );
    }

    // Calculate summary statistics
    double totalWeightedScore = 0;
    double totalWeight = 0;
    for (final g in grades) {
      final percentage = (g.grade.score / g.grade.maximum) * 100;
      final weight = g.grade.weight ?? 1.0;
      totalWeightedScore += percentage * weight;
      totalWeight += weight;
    }
    final avgScore = totalWeight > 0 ? (totalWeightedScore / totalWeight) : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Summary Header Card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      avgScore.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '加权平均分',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 36,
                  width: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
                Column(
                  children: [
                    Text(
                      '${grades.length}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已录入项',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Grade items
        for (final item in grades) ...[
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
              ),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _parseColor(item.courseColor).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.courseName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _parseColor(item.courseColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.grade.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              subtitle: item.grade.notes != null && item.grade.notes!.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '备注：${item.grade.notes}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.grade.score}/${item.grade.maximum}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Theme.of(context).hintColor,
                    onPressed: () => _confirmDelete(
                      title: '删除成绩记录',
                      content: '确定要删除“${item.grade.title}”的成绩记录吗？',
                      onConfirm: () async {
                        await repo.deleteGrade(item.grade.id);
                        _refresh();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ================= Floating Action Button =================
  Widget _buildFabForCurrentTab(
    AcademicRepository repo,
    List<CourseEntry> courses,
  ) {
    final index = _tabController.index;
    return switch (index) {
      0 => FloatingActionButton.extended(
          onPressed: () => _showAddAssignmentDialog(repo, courses),
          icon: const Icon(Icons.add),
          label: const Text('添加作业'),
        ),
      1 => FloatingActionButton.extended(
          onPressed: () => _showAddExamDialog(repo, courses),
          icon: const Icon(Icons.add),
          label: const Text('添加考试'),
        ),
      2 => FloatingActionButton.extended(
          onPressed: () => _showAddMaterialDialog(repo, courses),
          icon: const Icon(Icons.add),
          label: const Text('添加资料'),
        ),
      3 => FloatingActionButton.extended(
          onPressed: () => _showAddGradeDialog(repo, courses),
          icon: const Icon(Icons.add),
          label: const Text('录入成绩'),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  // ================= Dialogs =================
  Future<void> _showAddAssignmentDialog(
    AcademicRepository repo,
    List<CourseEntry> courses,
  ) async {
    String selectedCourse = _selectedCourseId ?? courses.first.id;
    final titleController = TextEditingController();
    final methodController = TextEditingController();
    DateTime? dueDate;
    TimeOfDay? dueTime;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('添加作业'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCourse,
                    decoration: const InputDecoration(labelText: '所属课程'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCourse = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '作业名称',
                      hintText: '如：第4章课后练习、期中论文',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: methodController,
                    decoration: const InputDecoration(
                      labelText: '提交方式（可选）',
                      hintText: '如：雨课堂、邮箱、纸质递交',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('截止日期（可选）'),
                    subtitle: Text(
                      dueDate == null
                          ? '未设置'
                          : '${dueDate!.year}-${dueDate!.month}-${dueDate!.day} '
                              '${dueTime?.format(context) ?? ''}',
                    ),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? DateTime.now(),
                      );
                      if (pickedDate != null) {
                        if (!context.mounted) return;
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime:
                              dueTime ?? const TimeOfDay(hour: 23, minute: 59),
                        );
                        setDialogState(() {
                          dueDate = pickedDate;
                          dueTime = pickedTime;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      DateTime? dueAt;
      if (dueDate != null) {
        dueAt = DateTime(
          dueDate!.year,
          dueDate!.month,
          dueDate!.day,
          dueTime?.hour ?? 23,
          dueTime?.minute ?? 59,
        );
      }
      await repo.createAssignment(
        courseId: selectedCourse,
        title: titleController.text.trim(),
        submissionMethod: methodController.text.trim().isEmpty
            ? null
            : methodController.text.trim(),
        dueAt: dueAt,
      );
      _refresh();
    }
  }

  Future<void> _showAddExamDialog(
    AcademicRepository repo,
    List<CourseEntry> courses,
  ) async {
    String selectedCourse = _selectedCourseId ?? courses.first.id;
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    final notesController = TextEditingController();
    DateTime examDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('添加考试日程'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCourse,
                    decoration: const InputDecoration(labelText: '所属课程'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCourse = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '考试名称',
                      hintText: '如：期中考试、期末闭卷',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('考试日期'),
                    subtitle: Text(
                        '${examDate.year}-${examDate.month}-${examDate.day}'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: examDate,
                      );
                      if (picked != null) {
                        setDialogState(() => examDate = picked);
                      }
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('开始时间'),
                          subtitle: Text(startTime.format(context)),
                          onTap: () async {
                            final val = await showTimePicker(
                              context: context,
                              initialTime: startTime,
                            );
                            if (val != null) {
                              setDialogState(() => startTime = val);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('结束时间'),
                          subtitle: Text(endTime.format(context)),
                          onTap: () async {
                            final val = await showTimePicker(
                              context: context,
                              initialTime: endTime,
                            );
                            if (val != null) {
                              setDialogState(() => endTime = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: '考场地点（可选）',
                      hintText: '如：教三-301、第一阶梯教室',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      hintText: '如：携带计算器、闭卷',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final start = DateTime(examDate.year, examDate.month, examDate.day,
          startTime.hour, startTime.minute);
      final end = DateTime(examDate.year, examDate.month, examDate.day,
          endTime.hour, endTime.minute);
      await repo.createExam(
        courseId: selectedCourse,
        title: titleController.text.trim(),
        start: start,
        end: end,
        location: locationController.text.trim().isEmpty
            ? null
            : locationController.text.trim(),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
      _refresh();
    }
  }

  Future<void> _showAddMaterialDialog(
    AcademicRepository repo,
    List<CourseEntry> courses,
  ) async {
    String selectedCourse = _selectedCourseId ?? courses.first.id;
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('添加课程资料'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCourse,
                    decoration: const InputDecoration(labelText: '所属课程'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCourse = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '资料标题',
                      hintText: '如：第3章核心公式集、复习参考大纲',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '资料内容或摘录（可选）',
                      hintText: '粘贴知识点重点、参考链接或书目...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      await repo.createMaterial(
        courseId: selectedCourse,
        title: titleController.text.trim(),
        content: contentController.text.trim().isEmpty
            ? null
            : contentController.text.trim(),
      );
      _refresh();
    }
  }

  Future<void> _showAddGradeDialog(
    AcademicRepository repo,
    List<CourseEntry> courses,
  ) async {
    String selectedCourse = _selectedCourseId ?? courses.first.id;
    final titleController = TextEditingController(text: '平时测验');
    final scoreController = TextEditingController();
    final maxController = TextEditingController(text: '100');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('录入成绩'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCourse,
                    decoration: const InputDecoration(labelText: '所属课程'),
                    items: courses
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCourse = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '成绩项目名称',
                      hintText: '如：期中成绩、作业1、随堂小测',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: scoreController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '得分'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '满分'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final s = double.tryParse(scoreController.text.trim());
                  final m = double.tryParse(maxController.text.trim());
                  if (s == null || m == null || m <= 0) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final s = double.parse(scoreController.text.trim());
      final m = double.parse(maxController.text.trim());
      await repo.saveGrade(CourseGradeDraft(
        courseId: selectedCourse,
        title: titleController.text.trim().isEmpty
            ? '成绩记录'
            : titleController.text.trim(),
        score: s,
        maximum: m,
      ));
      _refresh();
    }
  }

  Future<void> _showMaterialDetailDialog(
    GlobalAcademicMaterial material,
    AcademicRepository repo,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _parseColor(material.courseColor)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      material.courseName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _parseColor(material.courseColor),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '复制内容',
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () {
                      final text = '${material.title}\n\n${material.content ?? ''}';
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制资料内容')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '删除资料',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red,
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmDelete(
                        title: '删除课程资料',
                        content: '确定要删除“${material.title}”吗？',
                        onConfirm: () async {
                          await repo.deleteMaterial(material.materialId);
                          _refresh();
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                material.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (material.content != null && material.content!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    material.content!,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                )
              else
                Text(
                  '（无正文内容）',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete({
    required String title,
    required String content,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await onConfirm();
    }
  }
}
