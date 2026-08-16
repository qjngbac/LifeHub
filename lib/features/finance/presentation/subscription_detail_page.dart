import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class SubscriptionDetailPage extends StatelessWidget {
  const SubscriptionDetailPage({super.key, required this.subscription});

  final SubscriptionEntry subscription;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(subscription.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('周期费用'),
                    subtitle: Text(
                      '${subscription.currency} ${(subscription.amountMinor / 100).toStringAsFixed(2)}',
                    ),
                  ),
                  ListTile(
                    title: const Text('下次续费'),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(
                      DateKeys.fromLocalDateKey(subscription.nextRenewalDate),
                    )),
                  ),
                  ListTile(
                    title: const Text('状态'),
                    subtitle: Text(subscription.status),
                  ),
                  if (subscription.notes != null)
                    ListTile(
                      title: const Text('备注'),
                      subtitle: Text(subscription.notes!),
                    ),
                ],
              ),
            ),
            EntityRelationsPanel(
              entity: EntityReference(
                type: 'SUBSCRIPTION',
                id: subscription.id,
              ),
            ),
          ],
        ),
      );
}
