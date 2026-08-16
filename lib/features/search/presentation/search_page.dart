import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/search/data/search_repository.dart';
import 'package:lifehub/features/search/presentation/entity_detail_page.dart';
import 'package:lifehub/features/first_aid/data/first_aid_repository.dart';
import 'package:lifehub/features/first_aid/presentation/first_aid_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('全局搜索')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              autoFocus: true,
              hintText: '搜索任务、目标、资料、地点和旅行',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const Center(child: Text('输入关键词开始搜索'))
                : FutureBuilder<List<SearchResult>>(
                    future: SearchRepository(
                      ref.read(databaseProvider),
                      firstAid: FirstAidRepository(),
                    ).search(query),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(child: Text('搜索失败'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.data!.isEmpty) {
                        return const Center(child: Text('没有找到相关内容'));
                      }
                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: snapshot.data!
                            .map((result) => Card(
                                  child: ListTile(
                                    leading: Icon(_icon(result.type)),
                                    title: Text(result.title),
                                    subtitle: Text(_label(result.type)),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openResult(context, result),
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
          ),
        ]),
      );
}

Future<void> _openResult(BuildContext context, SearchResult result) async {
  if (result.type == 'FIRST_AID') {
    final item = await FirstAidRepository().find(result.id);
    if (item == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FirstAidItemPage(item: item)),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EntityDetailPage(result: result)),
  );
}

IconData _icon(String type) => switch (type) {
      'TASK' => Icons.check_circle_outline,
      'EVENT' => Icons.event_outlined,
      'PROJECT' => Icons.folder_outlined,
      'LIST' => Icons.checklist,
      'HABIT' => Icons.repeat,
      'GOAL' => Icons.flag_outlined,
      'SAVED_ITEM' => Icons.bookmark_outline,
      'LOCATION' => Icons.place_outlined,
      'TRIP' => Icons.luggage_outlined,
      'FIRST_AID' => Icons.medical_services_outlined,
      'HOUSEHOLD' => Icons.inventory_2_outlined,
      'MEDICATION' => Icons.medication_outlined,
      'FINANCE' => Icons.receipt_long_outlined,
      'SUBSCRIPTION' => Icons.autorenew,
      _ => Icons.description_outlined,
    };
String _label(String type) => switch (type) {
      'TASK' => '任务',
      'EVENT' => '日程',
      'PROJECT' => '项目',
      'LIST' => '清单',
      'HABIT' => '习惯',
      'GOAL' => '目标',
      'SAVED_ITEM' => '资料',
      'LOCATION' => '地点',
      'TRIP' => '旅行',
      'FIRST_AID' => '急救知识',
      'HOUSEHOLD' => '家庭物品',
      'MEDICATION' => '用药提醒',
      'FINANCE' => '轻量收支',
      'SUBSCRIPTION' => '订阅与续费',
      _ => type,
    };
