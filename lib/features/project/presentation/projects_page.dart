import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/list/presentation/lists_page.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/project/presentation/project_form.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = ProjectRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目'),
        actions: [
          IconButton(
            tooltip: '已归档项目',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => _showArchivedProjects(context, repository, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'project_add',
        onPressed: () => createProjectDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建项目'),
      ),
      body: FutureBuilder<List<ProjectEntry>>(
        future: repository.list(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('项目加载失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snapshot.data!;
          if (projects.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有项目，创建一个目标吧\n将复杂的计划分解为任务、清单与日程',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => createProjectDialog(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('立即创建项目'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // 顶部项目总览概览横幅
              _ProjectsOverviewBanner(projects: projects, repository: repository),
              const SizedBox(height: 12),
              // 项目列表
              ...projects.map((project) {
                final color = parseProjectColor(project.color);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectDetailPage(project: project),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 左侧主题色立面色条
                          Container(
                            width: 5,
                            color: color,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 项目圆角图标
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.folder_rounded,
                                          color: color,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              project.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                height: 1.3,
                                              ),
                                            ),
                                            if (project.description?.isNotEmpty ==
                                                true) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                project.description!,
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // 右侧更多菜单
                                      PopupMenuButton<String>(
                                        tooltip: '项目操作',
                                        icon: const Icon(
                                            Icons.more_vert_rounded,
                                            size: 20),
                                        onSelected: (action) async {
                                          if (action == 'edit') {
                                            final draft = await showProjectForm(
                                              context,
                                              current: project,
                                            );
                                            if (draft != null) {
                                              await repository.update(
                                                  project.id, draft);
                                              ref
                                                  .read(refreshProvider.notifier)
                                                  .state++;
                                            }
                                          } else if (action == 'archive') {
                                            final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  barrierDismissible: false,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                    title: const Text('归档项目？'),
                                                    content: const Text(
                                                        '项目将从普通列表隐藏，关联任务、日程和清单都会保留。'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  false),
                                                          child:
                                                              const Text('取消')),
                                                      FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  true),
                                                          child:
                                                              const Text('归档')),
                                                    ],
                                                  ),
                                                ) ??
                                                false;
                                            if (confirmed) {
                                              await repository
                                                  .archive(project.id);
                                              ref
                                                  .read(refreshProvider.notifier)
                                                  .state++;
                                            }
                                          } else {
                                            final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  barrierDismissible: false,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                    title: const Text('删除项目？'),
                                                    content: Text(
                                                        '确定删除项目《${project.name}》吗？项目删除后不会出现在搜索或归档中，关联内容仍会保留。'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  false),
                                                          child:
                                                              const Text('取消')),
                                                      FilledButton(
                                                          style: FilledButton
                                                              .styleFrom(
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  true),
                                                          child:
                                                              const Text('删除')),
                                                    ],
                                                  ),
                                                ) ??
                                                false;
                                            if (confirmed) {
                                              await repository
                                                  .delete(project.id);
                                              ref
                                                  .read(refreshProvider.notifier)
                                                  .state++;
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined,
                                                    size: 18),
                                                SizedBox(width: 8),
                                                Text('编辑项目'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'archive',
                                            child: Row(
                                              children: [
                                                Icon(Icons.archive_outlined,
                                                    size: 18),
                                                SizedBox(width: 8),
                                                Text('归档项目'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuDivider(),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline,
                                                    size: 18,
                                                    color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('删除项目',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // 任务进度条
                                  FutureBuilder<
                                      ({
                                        int total,
                                        int completed,
                                        double progress
                                      })>(
                                    future: repository.taskStats(project.id),
                                    builder: (context, statsSnap) {
                                      final stats = statsSnap.data;
                                      if (stats == null || stats.total == 0) {
                                        return Text(
                                          '暂无关联任务',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.outline,
                                          ),
                                        );
                                      }
                                      final percent =
                                          (stats.progress * 100).round();
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: stats.progress,
                                              minHeight: 6,
                                              color: color,
                                              backgroundColor: colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: 0.25),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '任务：${stats.completed} / ${stats.total} 完成',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                '$percent%',
                                                style: theme.textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: color,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showArchivedProjects(
    BuildContext context,
    ProjectRepository repository,
    WidgetRef ref,
  ) async {
    final archived = await repository.list(includeArchived: true);
    final onlyArchived =
        archived.where((p) => p.status == 'ARCHIVED').toList();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text('已归档项目',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (onlyArchived.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无已归档的项目')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: onlyArchived.length,
                  itemBuilder: (context, index) {
                    final item = onlyArchived[index];
                    return ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: Text(item.name),
                      trailing: FilledButton.tonal(
                        child: const Text('恢复'),
                        onPressed: () async {
                          await repository.unarchive(item.id);
                          ref.read(refreshProvider.notifier).state++;
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsOverviewBanner extends StatelessWidget {
  const _ProjectsOverviewBanner({
    required this.projects,
    required this.repository,
  });

  final List<ProjectEntry> projects;
  final ProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            label: '进行中项目',
            value: '${projects.length}',
            color: colorScheme.primary,
          ),
          Container(
            height: 28,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          _StatColumn(
            label: '规划分类',
            value: '已整合',
            color: colorScheme.secondary,
          ),
          Container(
            height: 28,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          _StatColumn(
            label: '协同体系',
            value: '任务/清单/日程',
            color: colorScheme.tertiary,
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class ProjectDetailPage extends ConsumerWidget {
  const ProjectDetailPage({super.key, required this.project});
  final ProjectEntry project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final database = ref.read(databaseProvider);
    final repository = ProjectRepository(database);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = parseProjectColor(project.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: '编辑项目',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final draft = await showProjectForm(context, current: project);
              if (draft != null) {
                await repository.update(project.id, draft);
                ref.read(refreshProvider.notifier).state++;
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<(List<EventEntry>, List<ListEntry>)>(
        future: () async {
          final events = await (database.select(database.events)
                ..where((row) =>
                    row.projectId.equals(project.id) & row.deletedAt.isNull()))
              .get();
          final lists = await (database.select(database.lists)
                ..where((row) =>
                    row.projectId.equals(project.id) &
                    row.deletedAt.isNull() &
                    row.archived.equals(false)))
              .get();
          return (events, lists);
        }(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data!.$1;
          final lists = snapshot.data!.$2;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // 头部主题 Banner
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: color.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.12),
                        color.withValues(alpha: 0.04),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.folder_rounded,
                                color: color, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (project.description?.isNotEmpty ==
                                    true) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    project.description!,
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 进度看板
                      FutureBuilder<
                          ({
                            int total,
                            int completed,
                            double progress
                          })>(
                        future: repository.taskStats(project.id),
                        builder: (context, statsSnap) {
                          final stats = statsSnap.data;
                          if (stats == null || stats.total == 0) {
                            return Text(
                              '暂未添加关联任务',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            );
                          }
                          final percent = (stats.progress * 100).round();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '任务整体完成度',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                  Text(
                                    '${stats.completed}/${stats.total} ($percent%)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: stats.progress,
                                  minHeight: 8,
                                  color: color,
                                  backgroundColor: colorScheme.outlineVariant
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 关联任务板块
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.check_circle_outline_rounded,
                            color: color),
                        title: const Text('项目任务'),
                        subtitle: const Text('查看全部关联任务与完成度'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add_rounded),
                              tooltip: '新建任务',
                              onPressed: () async {
                                await createTaskDialog(context, ref);
                                ref.read(refreshProvider.notifier).state++;
                              },
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TasksPage(
                              projectId: project.id,
                              title: project.name,
                            ),
                          ),
                        ),
                      ),
                      FutureBuilder<List<TaskEntry>>(
                        future: TaskRepository(database)
                            .list(projectId: project.id),
                        builder: (context, taskSnapshot) {
                          final tasks = taskSnapshot.data ?? [];
                          final pendingTasks = tasks
                              .where((t) =>
                                  t.status != 'DONE' && t.status != 'CANCELED')
                              .take(5)
                              .toList();
                          if (pendingTasks.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Text(
                                '暂无待办任务，所有任务均已完成或尚未添加',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              const Divider(height: 1),
                              for (final task in pendingTasks)
                                CheckboxListTile(
                                  dense: true,
                                  value: false,
                                  title: Text(task.title,
                                      style: const TextStyle(fontSize: 14)),
                                  onChanged: (val) async {
                                    if (val == true) {
                                      HapticFeedback.lightImpact();
                                      await TaskRepository(database)
                                          .setStatus(task.id, TaskStatus.done);
                                      ref
                                          .read(refreshProvider.notifier)
                                          .state++;
                                    }
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _ProjectSection(
                title: '关联日程',
                icon: Icons.event_outlined,
                onAdd: () =>
                    createEventDialog(context, ref, projectId: project.id),
                children: events
                    .map((event) => ListTile(
                          leading: const Icon(Icons.event_note_rounded),
                          title: Text(event.title),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),

              _ProjectSection(
                title: '关联清单',
                icon: Icons.checklist_rounded,
                onAdd: () =>
                    createListDialog(context, ref, projectId: project.id),
                children: lists
                    .map((list) => ListTile(
                          leading: const Icon(Icons.checklist_rounded),
                          title: Text(list.title),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListDetailPage(list: list),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),

              EntityRelationsPanel(
                entity: EntityReference(type: 'PROJECT', id: project.id),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.title,
    required this.icon,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final IconData icon;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            ListTile(
              leading: Icon(icon, color: colorScheme.primary),
              title: Text(title, style: theme.textTheme.titleMedium),
              trailing: IconButton(
                tooltip: '添加',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '暂无关联内容',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}
