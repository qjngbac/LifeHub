import 'package:flutter/material.dart';
import 'package:lifehub/features/first_aid/data/first_aid_repository.dart';
import 'package:lifehub/features/first_aid/domain/first_aid_models.dart';

class FirstAidPage extends StatefulWidget {
  const FirstAidPage({super.key});

  @override
  State<FirstAidPage> createState() => _FirstAidPageState();
}

class _FirstAidPageState extends State<FirstAidPage> {
  final repository = FirstAidRepository();
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('急救知识')),
        body: FutureBuilder<FirstAidKnowledge>(
          future: repository.load(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('知识库加载失败'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final knowledge = snapshot.data!;
            final matches =
                knowledge.items.where((item) => item.matches(query)).toList();
            if (query.trim().isNotEmpty) {
              return _SearchResults(items: matches);
            }
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(children: [
                    SearchBar(
                      hintText: '搜索症状、环境或处理方法',
                      leading: const Icon(Icons.search),
                      onChanged: (value) => setState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFFFF3E0),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 10),
                            Expanded(child: Text(knowledge.notice)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.08,
                  ),
                  itemCount: knowledge.scenes.length,
                  itemBuilder: (context, index) {
                    final scene = knowledge.scenes[index];
                    final count = knowledge.items
                        .where((item) => item.sceneId == scene.id)
                        .length;
                    return Card(
                      color: scene.color,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FirstAidScenePage(
                              scene: scene,
                              items: knowledge.items
                                  .where((item) => item.sceneId == scene.id)
                                  .toList(),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(firstAidIcon(scene.icon), size: 30),
                              const Spacer(),
                              Text(scene.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text('$count 条 · ${scene.subEnvironments}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.items});
  final List<FirstAidItem> items;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('没有找到相关急救内容'))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) => FirstAidItemTile(item: items[index]),
        );
}

class FirstAidScenePage extends StatelessWidget {
  const FirstAidScenePage({
    super.key,
    required this.scene,
    required this.items,
  });
  final FirstAidScene scene;
  final List<FirstAidItem> items;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(scene.name)),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (scene.subEnvironments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('适用环境：${scene.subEnvironments}'),
              ),
            for (final item in items) FirstAidItemTile(item: item),
          ],
        ),
      );
}

class FirstAidItemTile extends StatelessWidget {
  const FirstAidItemTile({super.key, required this.item});
  final FirstAidItem item;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(item.question),
          subtitle:
              Text(item.answer, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Chip(
            label: Text(item.risk.label),
            labelStyle: TextStyle(color: item.risk.color),
            side: BorderSide(color: item.risk.color),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FirstAidItemPage(item: item)),
          ),
        ),
      );
}

class FirstAidItemPage extends StatelessWidget {
  const FirstAidItemPage({super.key, required this.item});
  final FirstAidItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('急救知识详情')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(item.question,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar:
                    Icon(Icons.warning_amber_rounded, color: item.risk.color),
                label: Text('紧急等级：${item.risk.label}'),
                side: BorderSide(color: item.risk.color),
              ),
            ),
            _Section(title: '答案', value: item.answer),
            _Section(title: '操作步骤', value: item.steps),
            _Section(title: '少工具方案', value: item.fallback),
            _Section(
              title: '禁忌',
              value: item.prohibitions,
              color: const Color(0xFFFFE8E6),
            ),
            const Card(
              color: Color(0xFFFFF3E0),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('现场不安全时先撤离；危及生命时立即联系当地急救或救援。'),
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.value, this.color});
  final String title;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(value),
            ],
          ),
        ),
      );
}
