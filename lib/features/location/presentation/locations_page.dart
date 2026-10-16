import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/location/data/location_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class LocationsPage extends ConsumerStatefulWidget {
  const LocationsPage({super.key});

  @override
  ConsumerState<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends ConsumerState<LocationsPage> {
  String _filterType = 'ALL';

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = LocationRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('地点')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, repository),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('添加地点'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                for (final type in ['ALL', ...LocationType.values]) ...[
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(type == 'ALL' ? '全部' : _typeLabel(type)),
                    selected: _filterType == type,
                    onSelected: (selected) {
                      if (selected) setState(() => _filterType = type);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LocationEntry>>(
              future: repository.list(),
              builder: (context, snapshot) {
                final allValues = snapshot.data ?? const <LocationEntry>[];
                final values = _filterType == 'ALL'
                    ? allValues
                    : allValues
                        .where((loc) => loc.locationType == _filterType)
                        .toList();

                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (values.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filterType == 'ALL' ? '暂无地点' : '该分类下暂无地点',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点击右下角按钮添加，支持剪贴板智能识别',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                  children: [
                    ...values.map(
                      (location) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _typeColor(location.locationType)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _typeIcon(location.locationType),
                              color: _typeColor(location.locationType),
                              size: 22,
                            ),
                          ),
                          title: Text(
                            location.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (location.address != null &&
                                  location.address!.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.place_outlined,
                                        size: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        location.address!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _typeColor(location.locationType)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _typeLabel(location.locationType),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            _typeColor(location.locationType),
                                      ),
                                    ),
                                  ),
                                  if (location.notes != null &&
                                      location.notes!.trim().isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        location.notes!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: Text(location.name)),
                                body: ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    ListTile(
                                      title: const Text('类型'),
                                      subtitle: Text(
                                          _typeLabel(location.locationType)),
                                    ),
                                    if (location.address != null)
                                      ListTile(
                                        title: const Text('地址'),
                                        subtitle: SelectableText(
                                            location.address!),
                                      ),
                                    if (location.latitude != null)
                                      ListTile(
                                        title: const Text('坐标'),
                                        subtitle: SelectableText(
                                            '${location.latitude}, ${location.longitude}'),
                                      ),
                                    if (location.notes != null)
                                      ListTile(
                                        title: const Text('备注'),
                                        subtitle: Text(location.notes!),
                                      ),
                                    EntityRelationsPanel(
                                      entity: EntityReference(
                                        type: 'LOCATION',
                                        id: location.id,
                                      ),
                                    ),
                                    AttachmentPanel(
                                      entityType: 'LOCATION',
                                      entityId: location.id,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (location.address != null &&
                                  location.address!.trim().isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined,
                                      size: 18),
                                  tooltip: '复制地址',
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: location.address!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('地址已复制到剪贴板')),
                                    );
                                  },
                                ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await _edit(
                                        context, ref, repository, location);
                                  } else if (value == 'archive') {
                                    await repository.archive(location.id);
                                  } else if (value == 'delete') {
                                    await repository.delete(location.id);
                                  }
                                  ref.read(refreshProvider.notifier).state++;
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('编辑')),
                                  PopupMenuItem(
                                      value: 'archive', child: Text('归档')),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref,
      LocationRepository repository) async {
    final name = TextEditingController();
    final address = TextEditingController();
    final notes = TextEditingController();
    final sharedText = TextEditingController();
    var type = LocationType.place;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => KeyboardSafeFormDialog(
                title: const Text('添加地点'),
                body: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '智能文本识别',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () async {
                                var source = sharedText.text;
                                if (source.trim().isEmpty) {
                                  source = (await Clipboard.getData(
                                              Clipboard.kTextPlain))
                                          ?.text ??
                                      '';
                                  if (source.trim().isNotEmpty) {
                                    sharedText.text = source;
                                  }
                                }
                                final lines = source
                                    .split(RegExp(r'[\r\n]+'))
                                    .map((value) => value.trim())
                                    .where((value) => value.isNotEmpty)
                                    .toList();
                                if (lines.isEmpty) return;
                                setLocal(() {
                                  if (name.text.trim().isEmpty) {
                                    name.text = lines.first;
                                  }
                                  if (address.text.trim().isEmpty &&
                                      lines.length > 1) {
                                    address.text = lines.skip(1).join(' ');
                                  }
                                });
                              },
                              icon: const Icon(
                                  Icons.content_paste_go_outlined,
                                  size: 16),
                              label: const Text('从文本填充',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        TextField(
                          controller: sharedText,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: '粘贴分享文本（可选）',
                            hintText: '例如地图或聊天中复制的地点名称和地址',
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '名称')),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: LocationType.values
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text(_typeLabel(value))))
                        .toList(),
                    onChanged: (value) => setLocal(() => type = value!),
                  ),
                  TextField(
                      controller: address,
                      decoration: const InputDecoration(labelText: '地址')),
                  TextField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: '备注')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('保存')),
                ],
              )),
    );
    final draft = accepted == true && name.text.trim().isNotEmpty
        ? LocationDraft(
            name: name.text,
            locationType: type,
            address: address.text,
            notes: notes.text,
          )
        : null;
    name.dispose();
    address.dispose();
    notes.dispose();
    sharedText.dispose();
    if (draft == null) return;
    await repository.create(draft);
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LocationRepository repository,
    LocationEntry location,
  ) async {
    final name = TextEditingController(text: location.name);
    final address = TextEditingController(text: location.address ?? '');
    final notes = TextEditingController(text: location.notes ?? '');
    var type = location.locationType;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => KeyboardSafeFormDialog(
          title: const Text('编辑地点'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '类型'),
                items: LocationType.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_typeLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => setLocal(() => type = value!),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: '地址'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || name.text.trim().isEmpty) return;
    final draft = LocationDraft(
      name: name.text.trim(),
      locationType: type,
      address: address.text.trim().isEmpty ? null : address.text.trim(),
      latitude: location.latitude,
      longitude: location.longitude,
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    );
    await repository.update(location.id, draft);
    ref.read(refreshProvider.notifier).state++;
  }
}

String _typeLabel(String value) => switch (value) {
      LocationType.home => '住所',
      LocationType.school => '学校',
      LocationType.work => '工作地',
      LocationType.scenic => '景点',
      LocationType.restaurant => '餐厅',
      LocationType.transport => '交通',
      _ => '地点',
    };

IconData _typeIcon(String value) => switch (value) {
      LocationType.home => Icons.home_outlined,
      LocationType.school => Icons.school_outlined,
      LocationType.work => Icons.work_outline,
      LocationType.scenic => Icons.landscape_outlined,
      LocationType.restaurant => Icons.restaurant_outlined,
      LocationType.transport => Icons.directions_subway_outlined,
      _ => Icons.place_outlined,
    };

Color _typeColor(String value) => switch (value) {
      LocationType.home => Colors.deepOrange,
      LocationType.school => Colors.blue,
      LocationType.work => Colors.indigo,
      LocationType.scenic => Colors.teal,
      LocationType.restaurant => Colors.amber.shade800,
      LocationType.transport => Colors.cyan.shade700,
      _ => Colors.blueGrey,
    };
