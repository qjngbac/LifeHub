import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/list/presentation/lists_page.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = ProjectRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('项目')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'project_add',
        onPressed: () => createProjectDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<ProjectEntry>>(
        future: repository.list(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('项目加载失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('还没有项目，创建一个目标吧'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: snapshot.data!
                .map((project) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.folder_outlined)),
                        title: Text(project.name),
                        subtitle: FutureBuilder<double>(
                          future: repository.progress(project.id),
                          builder: (context, value) =>
                              LinearProgressIndicator(value: value.data ?? 0),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'edit') {
                              final name = await promptText(
                                context,
                                title: '编辑项目',
                                label: '项目名称',
                                initial: project.name,
                              );
                              if (name != null) {
                                await repository.update(
                                  project.id,
                                  ProjectDraft(
                                    name: name,
                                    description: project.description,
                                    color: project.color,
                                  ),
                                );
                              }
                            } else if (action == 'archive') {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => AlertDialog(
                                      title: const Text('归档项目？'),
                                      content: const Text(
                                          '项目将从普通列表隐藏，关联任务、日程和清单都会保留。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('归档')),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (confirmed) {
                                await repository.archive(project.id);
                              }
                            } else {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除项目？'),
                                      content: const Text(
                                          '项目删除后不会出现在搜索或归档中；关联内容仍会保留。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消')),
                                        FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .error),
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('删除')),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (confirmed) {
                                await repository.delete(project.id);
                              }
                            }
                            ref.read(refreshProvider.notifier).state++;
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'archive', child: Text('归档')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ProjectDetailPage(project: project))),
                      ),
                    ))
                .toList(),
          );
        },
      ),
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
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('项目任务'),
                  subtitle: const Text('查看、筛选和添加关联任务'),
                  trailing: const Icon(Icons.chevron_right),
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
              ),
              EntityRelationsPanel(
                entity: EntityReference(type: 'PROJECT', id: project.id),
              ),
              _ProjectSection(
                title: '关联日程',
                onAdd: () =>
                    createEventDialog(context, ref, projectId: project.id),
                children: events
                    .map((event) => ListTile(
                          leading: const Icon(Icons.event_outlined),
                          title: Text(event.title),
                        ))
                    .toList(),
              ),
              _ProjectSection(
                title: '关联清单',
                onAdd: () =>
                    createListDialog(context, ref, projectId: project.id),
                children: lists
                    .map((list) => ListTile(
                          leading: const Icon(Icons.checklist),
                          title: Text(list.title),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListDetailPage(list: list),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection(
      {required this.title, required this.onAdd, required this.children});
  final String title;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(children: [
            ListTile(
              title:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
              trailing: IconButton(
                tooltip: '添加',
                onPressed: onAdd,
                icon: const Icon(Icons.add),
              ),
            ),
            if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('暂无关联内容'),
              )
            else
              ...children,
          ]),
        ),
      );
}
