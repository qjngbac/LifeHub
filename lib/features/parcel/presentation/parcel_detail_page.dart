import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/parcel/presentation/parcel_form_style.dart';
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
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                (parcel == null || parcel.deletedAt != null))) {
          return Scaffold(
            appBar: AppBar(title: const Text('快递详情')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.hasError
                      ? '加载失败，记录可能不存在或已删除'
                      : '记录不存在或已删除'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => revision++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (parcel == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final theme = Theme.of(context);
        final now = DateTime.now();
        final hint = pickupDeadlineHint(
          status: parcel.status,
          pickupDeadline: parcel.pickupDeadline,
          arrivedAt: parcel.arrivedAt,
          now: now,
        );
        final canAdvance = parcel.status == ParcelStatus.inTransit.dbValue ||
            parcel.status == ParcelStatus.ready.dbValue;

        return Scaffold(
          appBar: AppBar(
            title: Text(parcel.title),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) => _action(repository, parcel, value),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  if (parcel.status != ParcelStatus.returned.dbValue)
                    const PopupMenuItem(value: 'return', child: Text('标记退回')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ① 状态 + 倒计时 + 主操作
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            parcel.status == ParcelStatus.ready.dbValue
                                ? Icons.markunread_mailbox_outlined
                                : parcel.status ==
                                        ParcelStatus.collected.dbValue
                                    ? Icons.check_circle_outline
                                    : parcel.status ==
                                            ParcelStatus.returned.dbValue
                                        ? Icons.undo_outlined
                                        : Icons.local_shipping_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            parcelStatusLabel(parcel.status),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (hint != null)
                            ParcelStatusBadge(text: hint.text, tone: hint.tone),
                        ],
                      ),
                      if (canAdvance) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              await repository.advance(parcel.id);
                              await NotificationService.instance.rebuildFuture(
                                ref.read(databaseProvider),
                              );
                              if (mounted) setState(() => revision++);
                            },
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(
                              parcel.status ==
                                      ParcelStatus.inTransit.dbValue
                                  ? '到达取件点'
                                  : '标记已取件',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ② 明细：取件码与单号都能一键复制
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '取件信息',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (parcel.pickupCode?.isNotEmpty == true)
                        _CopyRow(
                          icon: Icons.qr_code_2,
                          label: '取件码',
                          value: parcel.pickupCode!,
                          emphasize: true,
                        ),
                      if (parcel.trackingNumber?.isNotEmpty == true)
                        _CopyRow(
                          icon: Icons.confirmation_number_outlined,
                          label: '快递单号',
                          value: parcel.trackingNumber!,
                        ),
                      if (parcel.carrier?.isNotEmpty == true)
                        _InfoRow(
                          icon: Icons.local_shipping_outlined,
                          label: '快递公司',
                          value: parcel.carrier!,
                        ),
                      if (parcel.notes?.isNotEmpty == true)
                        _InfoRow(
                          icon: Icons.notes_outlined,
                          label: '物品信息',
                          value: parcel.notes!,
                        ),
                      if (parcel.pickupDeadline != null)
                        _InfoRow(
                          icon: Icons.event_outlined,
                          label: '取件截止',
                          value: DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(
                              parcel.pickupDeadline!,
                            ),
                          ),
                        ),
                      if (parcel.arrivedAt != null)
                        _InfoRow(
                          icon: Icons.login_outlined,
                          label: '到达时间',
                          value: DateFormat('yyyy-MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(
                              parcel.arrivedAt!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              EntityRelationsPanel(
                entity: EntityReference(type: 'PARCEL', id: parcel.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _action(
    ParcelRepository repository,
    ParcelEntry parcel,
    String action,
  ) async {
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
    if (action == 'return') {
      await repository.markReturned(parcel.id);
      await NotificationService.instance
          .rebuildFuture(ref.read(databaseProvider));
      if (mounted) setState(() => revision++);
      return;
    }
    final yes = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('删除这条快递记录？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes) return;
    await repository.delete(parcel.id);
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
    if (mounted) Navigator.pop(context);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// 可一键复制的关键信息（取件码 / 单号）。
class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 17,
              color: emphasize ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.bold : null,
                letterSpacing: emphasize ? 0.6 : null,
              ),
            ),
          ),
          IconButton(
            tooltip: '复制$label',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('已复制$label')));
            },
          ),
        ],
      ),
    );
  }
}
