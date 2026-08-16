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

class LocationsPage extends ConsumerWidget {
  const LocationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = LocationRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('地点')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, repository),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('添加地点'),
      ),
      body: FutureBuilder<List<LocationEntry>>(
        future: repository.list(),
        builder: (context, snapshot) {
          final values = snapshot.data ?? const <LocationEntry>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              const Card(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('手动保存地址或坐标，无需定位权限，不会后台追踪。'),
              )),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (values.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('暂无地点')),
                )
              else
                ...values.map((location) => Card(
                        child: ListTile(
                      leading:
                          const CircleAvatar(child: Icon(Icons.place_outlined)),
                      title: Text(location.name),
                      subtitle: Text(location.address ??
                          _typeLabel(location.locationType)),
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
                                              subtitle: Text(_typeLabel(
                                                  location.locationType))),
                                          if (location.address != null)
                                            ListTile(
                                                title: const Text('地址'),
                                                subtitle: SelectableText(
                                                    location.address!)),
                                          if (location.latitude != null)
                                            ListTile(
                                              title: const Text('坐标'),
                                              subtitle: SelectableText(
                                                  '${location.latitude}, ${location.longitude}'),
                                            ),
                                          if (location.notes != null)
                                            ListTile(
                                                title: const Text('备注'),
                                                subtitle:
                                                    Text(location.notes!)),
                                          EntityRelationsPanel(
                                            entity: EntityReference(
                                              type: 'LOCATION',
                                              id: location.id,
                                            ),
                                          ),
                                          AttachmentPanel(
                                              entityType: 'LOCATION',
                                              entityId: location.id),
                                        ]),
                                  ))),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'archive') {
                            await repository.archive(location.id);
                          }
                          if (value == 'delete') {
                            await repository.delete(location.id);
                          }
                          ref.read(refreshProvider.notifier).state++;
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'archive', child: Text('归档')),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text('删除',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ))),
            ],
          );
        },
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: sharedText,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '粘贴分享文本（可选）',
                      hintText: '例如地图或聊天中复制的地点名称和地址',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        var source = sharedText.text;
                        if (source.trim().isEmpty) {
                          source =
                              (await Clipboard.getData(Clipboard.kTextPlain))
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
                        if (name.text.trim().isEmpty) name.text = lines.first;
                        if (address.text.trim().isEmpty && lines.length > 1) {
                          address.text = lines.skip(1).join(' ');
                        }
                      },
                      icon: const Icon(Icons.content_paste_go_outlined),
                      label: const Text('从文本填充'),
                    ),
                  ),
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
