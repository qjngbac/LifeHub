import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/parcel/presentation/parcels_page.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class ParcelDetailPage extends ConsumerStatefulWidget {
  const ParcelDetailPage({super.key, required this.parcelId});
  final String parcelId;
  @override
  ConsumerState<ParcelDetailPage> createState() => _ParcelDetailPageState();
}

class _ParcelDetailPageState extends ConsumerState<ParcelDetailPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = ParcelRepository(ref.read(databaseProvider));
    return FutureBuilder<ParcelEntry>(
      key: ValueKey(revision),
      future: repository.get(widget.parcelId),
      builder: (context, snapshot) {
        final parcel = snapshot.data;
        if (parcel == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(title: Text(parcel.title), actions: [
            PopupMenuButton<String>(
              onSelected: (value) => _action(repository, parcel, value),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('删除',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              ],
            )
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                child: Column(children: [
              ListTile(
                  title: const Text('状态'),
                  subtitle: Text(parcelStatusLabel(parcel.status))),
              if (parcel.notes != null)
                ListTile(
                    title: const Text('物品信息'), subtitle: Text(parcel.notes!)),
              if (parcel.pickupCode != null)
                ListTile(
                    title: const Text('取件码'),
                    subtitle: Text(parcel.pickupCode!)),
              if (parcel.pickupDeadline != null)
                ListTile(
                    title: const Text('取件截止'),
                    subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(
                        DateTime.fromMillisecondsSinceEpoch(
                            parcel.pickupDeadline!)))),
              if (parcel.status == ParcelStatus.inTransit.dbValue ||
                  parcel.status == ParcelStatus.ready.dbValue)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.tonal(
                        onPressed: () async {
                          await repository.advance(parcel.id);
                          await NotificationService.instance
                              .rebuildFuture(ref.read(databaseProvider));
                          if (mounted) setState(() => revision++);
                        },
                        child: Text(
                            parcel.status == ParcelStatus.inTransit.dbValue
                                ? '到达取件点'
                                : '标记已取件'))),
            ])),
            EntityRelationsPanel(
                entity: EntityReference(type: 'PARCEL', id: parcel.id)),
          ]),
        );
      },
    );
  }

  Future<void> _action(
      ParcelRepository repository, ParcelEntry parcel, String action) async {
    if (action == 'edit') {
      final draft = await showParcelForm(context, current: parcel);
      if (draft != null) {
        await repository.update(parcel.id, draft);
        await NotificationService.instance
            .rebuildFuture(ref.read(databaseProvider));
        if (mounted) setState(() => revision++);
      }
      return;
    }
    final yes = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                AlertDialog(title: const Text('删除这条快递记录？'), actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ])) ??
        false;
    if (!yes) return;
    await repository.delete(parcel.id);
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
    if (mounted) Navigator.pop(context);
  }
}
