import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/search/data/search_repository.dart';

class EntityDetailPage extends ConsumerWidget {
  const EntityDetailPage({super.key, required this.result});
  final SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(result.title)),
        body: FutureBuilder<List<(String, String)>>(
          future: _load(ref),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('该内容已删除或无法读取'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final field in snapshot.data!)
                  ListTile(
                    title: Text(field.$1),
                    subtitle: Text(field.$2),
                  ),
              ],
            );
          },
        ),
      );

  Future<List<(String, String)>> _load(WidgetRef ref) async {
    final database = ref.read(databaseProvider);
    String date(int? value) => value == null
        ? '未设置'
        : DateFormat('yyyy-MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal());
    switch (result.type) {
      case 'TASK':
        final value = await (database.select(database.tasks)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('标题', value.title),
          ('状态', value.status),
          ('分类', value.category),
          ('优先级', '${value.priority}'),
          ('截止时间', date(value.dueAt)),
        ];
      case 'EVENT':
        final value = await (database.select(database.events)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('标题', value.title),
          ('开始', value.allDay ? '全天' : date(value.startAt)),
          ('结束', value.allDay ? '全天' : date(value.endAt)),
          ('地点', value.location ?? '未设置'),
        ];
      case 'PROJECT':
        final value = await (database.select(database.projects)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('状态', value.status),
          ('说明', value.description ?? '无'),
        ];
      case 'LIST':
        final value = await (database.select(database.lists)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        final count = database.listItems.id.count();
        final row = await (database.selectOnly(database.listItems)
              ..addColumns([count])
              ..where(database.listItems.listId.equals(value.id) &
                  database.listItems.deletedAt.isNull()))
            .getSingle();
        return [('名称', value.title), ('项目数', '${row.read(count) ?? 0}')];
      case 'HABIT':
        final value = await (database.select(database.habits)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('频率', value.scheduleRule),
          ('目标', '${value.targetCount}${value.unit}'),
          ('提醒', value.reminderPolicy ?? '未设置'),
        ];
      case 'RELATIONSHIP':
        final value = await (database.select(database.relationshipProfiles)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('昵称', value.nickname ?? '未设置'),
          (
            '开始日期',
            value.startDate == null
                ? '未设置'
                : DateFormat('yyyy-MM-dd')
                    .format(DateKeys.fromLocalDateKey(value.startDate!)),
          ),
        ];
      case 'LIFE_EVENT':
        final value = await (database.select(database.lifeEvents)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        final minute = value.timeMinutes;
        return [
          ('标题', value.title),
          (
            '日期',
            DateFormat('yyyy-MM-dd')
                .format(DateKeys.fromLocalDateKey(value.localDate)),
          ),
          (
            '时间',
            minute == null
                ? '未设置'
                : '${(minute ~/ 60).toString().padLeft(2, '0')}:'
                    '${(minute % 60).toString().padLeft(2, '0')}',
          ),
          ('记录', value.note ?? '无'),
        ];
      case 'ANNIVERSARY':
        final value = await (database.select(database.anniversaries)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.title),
          (
            '日期',
            DateFormat('yyyy-MM-dd')
                .format(DateKeys.fromLocalDateKey(value.date)),
          ),
          ('重复', value.repeatYearly ? '每年' : '不重复'),
        ];
      case 'GOAL':
        final value = await (database.select(database.goals)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('状态', value.status),
          ('进度方式', value.progressMode)
        ];
      case 'SAVED_ITEM':
        final value = await (database.select(database.savedItems)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('标题', value.title),
          ('类型', value.itemType),
          ('内容', value.content ?? '无')
        ];
      case 'LOCATION':
        final value = await (database.select(database.locations)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('类型', value.locationType),
          ('地址', value.address ?? '未设置')
        ];
      case 'TRIP':
        final value = await (database.select(database.tripProfiles)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        final project = await (database.select(database.projects)
              ..where((row) => row.id.equals(value.projectId)))
            .getSingle();
        return [
          ('名称', project.name),
          (
            '开始',
            DateFormat('yyyy-MM-dd')
                .format(DateKeys.fromLocalDateKey(value.startDate))
          ),
          (
            '结束',
            DateFormat('yyyy-MM-dd')
                .format(DateKeys.fromLocalDateKey(value.endDate))
          ),
          ('状态', value.status),
        ];
      case 'HOUSEHOLD':
        final value = await (database.select(database.householdItems)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('品牌型号', value.brandModel ?? '未填写'),
          (
            '保修截止',
            value.warrantyEndDate == null
                ? '未设置'
                : DateFormat('yyyy-MM-dd').format(
                    DateKeys.fromLocalDateKey(value.warrantyEndDate!),
                  ),
          ),
        ];
      case 'MEDICATION':
        final value = await (database.select(database.medicationPlans)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          ('用户说明', value.instructions ?? '未填写'),
          ('提醒时间', value.reminderTimesJson),
          ('注意', '仅作记录与提醒，不提供诊断或剂量建议'),
        ];
      case 'FINANCE':
        final value = await (database.select(database.financeEntries)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('类型', value.direction == 'INCOME' ? '收入' : '支出'),
          (
            '金额',
            '${value.currency} ${(value.amountMinor / 100).toStringAsFixed(2)}'
          ),
          ('分类', value.category),
          ('说明', value.note ?? '未填写'),
        ];
      case 'SUBSCRIPTION':
        final value = await (database.select(database.subscriptions)
              ..where(
                  (row) => row.id.equals(result.id) & row.deletedAt.isNull()))
            .getSingle();
        return [
          ('名称', value.name),
          (
            '金额',
            '${value.currency} ${(value.amountMinor / 100).toStringAsFixed(2)}'
          ),
          ('续费周期', value.cycleUnit),
          (
            '下次续费',
            DateFormat('yyyy-MM-dd').format(
              DateKeys.fromLocalDateKey(value.nextRenewalDate),
            )
          ),
          ('状态', value.status),
        ];
      default:
        throw StateError('Unsupported search type: ${result.type}');
    }
  }
}
