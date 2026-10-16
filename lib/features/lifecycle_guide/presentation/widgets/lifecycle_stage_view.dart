import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/lifecycle_guide/application/family_checkup_service.dart';
import 'package:lifehub/features/lifecycle_guide/domain/family_profile_model.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_detail_sheet.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/safety_checklist_export_sheet.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class LifecycleStageView extends ConsumerStatefulWidget {
  const LifecycleStageView({
    super.key,
    required this.stages,
    this.checkupSchedule = const [],
    this.initialStageIndex = 0,
  });

  final List<LifecycleStage> stages;
  final List<CheckupScheduleItem> checkupSchedule;
  final int initialStageIndex;

  @override
  ConsumerState<LifecycleStageView> createState() => _LifecycleStageViewState();
}

class _LifecycleStageViewState extends ConsumerState<LifecycleStageView> {
  static const _kFamilyProfilesKey = 'lifecycle_family_profiles';

  late int _selectedIndex;
  final ScrollController _chipsScrollCtrl = ScrollController();
  List<FamilyMemberProfile> _members =
      List<FamilyMemberProfile>.from(FamilyMemberProfile.defaultProfiles);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialStageIndex;
    _loadFamilyProfiles();
  }

  @override
  void dispose() {
    _chipsScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFamilyProfilesKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = FamilyMemberProfile.decodeList(raw);
        if (mounted && decoded.isNotEmpty) {
          setState(() {
            _members = decoded;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFamilyProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kFamilyProfilesKey,
        FamilyMemberProfile.encodeList(_members),
      );
    } catch (_) {}
  }

  void _selectMember(FamilyMemberProfile member) {
    final targetIndex = member.stageIndex.clamp(0, widget.stages.length - 1);
    setState(() {
      _selectedIndex = targetIndex;
    });
    if (_chipsScrollCtrl.hasClients) {
      final targetOffset = (targetIndex * 78.0) - 40.0;
      _chipsScrollCtrl.animateTo(
        targetOffset.clamp(0.0, _chipsScrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showCheckupRoutes(
    BuildContext context,
    FamilyMemberProfile? member,
    LifecycleStage stage,
  ) {
    const service = FamilyCheckupService();
    final checkups = service.getRecommendedCheckups(
      stageIndex: _selectedIndex,
      memberName: member?.name ?? '',
      roleLabel: member?.roleLabel ?? stage.codeLabel,
      allCheckups: widget.checkupSchedule,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        final targetName = member?.name ?? stage.codeLabel;

        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Row(
                  children: [
                    Icon(Icons.medical_services_rounded,
                        color: colorScheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '「$targetName」专属体检与筛查路线图',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '结合国家指南匹配该人生阶段的核心癌症、慢病及器官功能必查项目',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                if (checkups.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无推荐项目'),
                    ),
                  )
                else
                  for (final c in checkups) ...[
                    Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.item,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    c.target,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.access_time_rounded,
                                    size: 13, color: colorScheme.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '建议频率：${c.frequency}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (c.notes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                c.notes,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.add_alert_outlined,
                                    size: 14),
                                label: const Text('一键加入待办提醒'),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _scheduleCheckupTask(
                                      context, targetName, c);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _scheduleCheckupTask(
    BuildContext context,
    String memberName,
    CheckupScheduleItem checkup,
  ) async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: '选择体检提醒日期',
      cancelText: '取消',
      confirmText: '确定创建',
    );
    if (picked != null) selectedDate = picked;

    try {
      final db = ref.read(databaseProvider);
      final taskRepo = TaskRepository(db);
      await const FamilyCheckupService().addCheckupToTasks(
        taskRepo: taskRepo,
        memberName: memberName,
        checkup: checkup,
        dueDate: selectedDate,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '已为「$memberName」成功添加待办提醒：「${checkup.item}」！'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建待办失败：$e')),
        );
      }
    }
  }

  void _exportChecklist(
    BuildContext context,
    FamilyMemberProfile? member,
    LifecycleStage stage,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafetyChecklistExportSheet(
          stage: stage,
          memberName: member?.name,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stages.isEmpty) {
      return const Center(child: Text('暂无阶段数据'));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentStage =
        widget.stages[_selectedIndex.clamp(0, widget.stages.length - 1)];
    final matchingMembers =
        _members.where((m) => m.stageIndex == _selectedIndex).toList();
    final activeMember =
        matchingMembers.isNotEmpty ? matchingMembers.first : null;

    return Column(
      children: [
        // Family Member Profiles Bar (One-click jump)
        _buildFamilyMemberBar(context, colorScheme, theme),

        // Stage Selector Chips (Fixed at top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              controller: _chipsScrollCtrl,
              key: const PageStorageKey('lifecycle_stage_chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.stages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return ChoiceChip(
                  label: Text(widget.stages[i].codeLabel),
                  selected: _selectedIndex == i,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedIndex = i);
                  },
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: ListView(
            key: PageStorageKey('lifecycle_stage_list_$_selectedIndex'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // Family member matched banner
              if (matchingMembers.isNotEmpty) ...[
                Card(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              child: Icon(matchingMembers.first.icon, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '已定位至家庭成员：${matchingMembers.map((m) => m.name).join(' / ')}',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '已为您呈现 ${currentStage.codeLabel} 核心生理特征、专属选品与避坑红线',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.medical_services_outlined,
                                    size: 15),
                                label: const Text('体检路线与待办'),
                                onPressed: () => _showCheckupRoutes(
                                    context, activeMember, currentStage),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.share_outlined, size: 15),
                                label: const Text('导出避坑清单'),
                                onPressed: () => _exportChecklist(
                                    context, activeMember, currentStage),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Stage Title Banner Card (when no member matched)
              if (matchingMembers.isEmpty) ...[
                Card(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.person_pin_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentStage.rawTitle,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '生命周期专属选品、生理特点与避坑红线',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.medical_services_outlined,
                                    size: 14),
                                label: const Text('推荐体检项目'),
                                onPressed: () => _showCheckupRoutes(
                                    context, null, currentStage),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.share_outlined, size: 14),
                                label: const Text('导出避坑清单'),
                                onPressed: () => _exportChecklist(
                                    context, null, currentStage),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Core Redlines
              if (currentStage.redlines.isNotEmpty) ...[
                Card(
                  color: colorScheme.errorContainer.withValues(alpha: 0.6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: colorScheme.error, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              '该阶段核心安全红线',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () => _exportChecklist(
                                  context, activeMember, currentStage),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy_all_outlined,
                                        size: 14, color: colorScheme.error),
                                    const SizedBox(width: 2),
                                    Text(
                                      '导出',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.error,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final r in currentStage.redlines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('• ',
                                    style: TextStyle(
                                        color: colorScheme.error,
                                        fontWeight: FontWeight.bold)),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Subsections
              for (final sub in currentStage.subsections) ...[
                _StageSectionCard(
                  key: ValueKey('stage_${currentStage.codeLabel}_${sub.title}'),
                  subsection: sub,
                  stageLabel: currentStage.codeLabel,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyMemberBar(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.family_restroom_rounded,
                  size: 17, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '家庭成员画像',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '一键直达',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '点击快速定位阶段',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.separated(
              key: const PageStorageKey('family_member_avatar_list'),
              scrollDirection: Axis.horizontal,
              itemCount: _members.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                if (idx == _members.length) {
                  return _buildAddMemberButton(context, colorScheme, theme);
                }
                final member = _members[idx];
                final isCurrent = _selectedIndex == member.stageIndex;
                return _buildMemberCard(
                    context, member, isCurrent, colorScheme, theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    FamilyMemberProfile member,
    bool isCurrent,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _selectMember(member),
      onLongPress: () => _showMemberOptionsDialog(context, member),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent
              ? colorScheme.primaryContainer.withValues(alpha: 0.85)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: isCurrent ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isCurrent
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              foregroundColor:
                  isCurrent ? colorScheme.onPrimary : colorScheme.primary,
              child: Icon(member.icon, size: 17),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.w600,
                        color: isCurrent
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle,
                          size: 13, color: colorScheme.primary),
                    ],
                  ],
                ),
                Text(
                  member.roleLabel.isNotEmpty
                      ? member.roleLabel
                      : member.stageCode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: isCurrent ? colorScheme.primary : colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMemberButton(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showAddMemberDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              foregroundColor: colorScheme.primary,
              child: const Icon(Icons.person_add_alt_1_outlined, size: 16),
            ),
            const SizedBox(width: 6),
            Text(
              '添加成员',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    int selectedStage = 0;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_add_rounded),
                  SizedBox(width: 8),
                  Text('添加家庭成员画像'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '成员称呼',
                        hintText: '如：妈妈、妻子、二宝、外公',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: roleCtrl,
                      decoration: const InputDecoration(
                        labelText: '角色 / 备注 (选填)',
                        hintText: '如：备孕中、高血压老人、学龄儿童',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '对应人生阶段',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: selectedStage,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: [
                        for (int i = 0; i < widget.stages.length; i++)
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(
                              widget.stages[i].codeLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedStage = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final role = roleCtrl.text.trim();
                    final newProfile = FamilyMemberProfile(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      stageIndex: selectedStage,
                      stageCode: widget.stages[selectedStage].codeLabel,
                      roleLabel: role.isNotEmpty
                          ? role
                          : widget.stages[selectedStage].codeLabel,
                    );
                    setState(() {
                      _members.add(newProfile);
                      _saveFamilyProfiles();
                      _selectMember(newProfile);
                    });
                    Navigator.pop(dialogCtx);
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMemberOptionsDialog(
      BuildContext context, FamilyMemberProfile member) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(member.icon)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${member.stageCode} (${member.roleLabel})',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: const Text('立即定位到该阶段'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectMember(member);
                  },
                ),
                if (!member.id.startsWith('default_')) ...[
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('删除此成员画像',
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      setState(() {
                        _members.removeWhere((m) => m.id == member.id);
                        _saveFamilyProfiles();
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StageSectionCard extends StatefulWidget {
  const _StageSectionCard({
    super.key,
    required this.subsection,
    required this.stageLabel,
  });

  final KnowledgeSubsection subsection;
  final String stageLabel;

  @override
  State<_StageSectionCard> createState() => _StageSectionCardState();
}

class _StageSectionCardState extends State<_StageSectionCard> {
  bool _isExpanded = false;

  void _openDetailSheet() {
    final subsection = widget.subsection;
    final details = [
      for (final b in subsection.bullets) '• $b',
      for (final tbl in subsection.tables)
        for (final r in tbl)
          r.entries.map((e) => '${e.key}：${e.value}').join(' | '),
    ].join('\n\n');
    showLifecycleDetailSheet(
      context,
      title: subsection.title,
      sourceBadge: '人生阶段 · ${widget.stageLabel}',
      details: details,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subsection = widget.subsection;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      subsection.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '查看与复制详情',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _openDetailSheet,
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              if (!_isExpanded && subsection.bullets.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subsection.bullets.first,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_isExpanded) ...[
                if (subsection.bullets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  for (final b in subsection.bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              b,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (subsection.tables.isNotEmpty) ...[
                  if (subsection.bullets.isEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                  ] else ...[
                    const SizedBox(height: 6),
                  ],
                  for (final tbl in subsection.tables) ...[
                    for (final row in tbl)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in row.entries)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        e.key,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colorScheme.outline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(height: 1.35),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
