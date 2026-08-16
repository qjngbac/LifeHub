import 'package:flutter/material.dart';
import 'package:lifehub/features/knowledge/data/offline_knowledge_repository.dart';
import 'package:lifehub/features/knowledge/domain/offline_knowledge_models.dart';

class ConsumerGuidePage extends StatefulWidget {
  const ConsumerGuidePage({super.key});

  @override
  State<ConsumerGuidePage> createState() => _ConsumerGuidePageState();
}

class _ConsumerGuidePageState extends State<ConsumerGuidePage> {
  final repository = OfflineKnowledgeRepository();
  final search = TextEditingController();
  late final Future<ConsumerGuideLibrary> future =
      repository.loadConsumerGuide();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('日用品选购')),
        body: _KnowledgeBackground(
          child: FutureBuilder<ConsumerGuideLibrary>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('离线知识库读取失败'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final library = snapshot.data!;
              final results = library.search(search.text);
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _SearchBox(
                      controller: search,
                      hint: '搜索日用品、选购重点或标准关键词',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (search.text.trim().isEmpty)
                    _CategoryGrid(
                      categories: library.categories,
                      icon: Icons.shopping_basket_outlined,
                      onTap: (category) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ConsumerListPage(
                            category: category,
                            library: library,
                          ),
                        ),
                      ),
                    )
                  else
                    _ConsumerResults(items: results),
                ],
              );
            },
          ),
        ),
      );
}

class DrugInfoPage extends StatefulWidget {
  const DrugInfoPage({super.key});

  @override
  State<DrugInfoPage> createState() => _DrugInfoPageState();
}

class _DrugInfoPageState extends State<DrugInfoPage> {
  final repository = OfflineKnowledgeRepository();
  final search = TextEditingController();
  late final Future<DrugInfoLibrary> future = repository.loadDrugInfo();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('药品信息')),
        body: _KnowledgeBackground(
          child: FutureBuilder<DrugInfoLibrary>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('离线知识库读取失败'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final library = snapshot.data!;
              final results = library.search(search.text);
              return CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: _DrugNotice()),
                  SliverToBoxAdapter(
                    child: _SearchBox(
                      controller: search,
                      hint: '搜索药品通用名、类别或用途标签',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (search.text.trim().isEmpty)
                    _CategoryGrid(
                      categories: library.categories,
                      icon: Icons.medication_outlined,
                      onTap: (category) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _DrugListPage(
                            category: category,
                            library: library,
                          ),
                        ),
                      ),
                    )
                  else
                    _DrugResults(items: results),
                ],
              );
            },
          ),
        ),
      );
}

class _ConsumerListPage extends StatelessWidget {
  const _ConsumerListPage({required this.category, required this.library});
  final KnowledgeCategory category;
  final ConsumerGuideLibrary library;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(category.name)),
        body: _KnowledgeBackground(
          child: CustomScrollView(
            slivers: [
              _ConsumerResults(
                items: library.search('', categoryId: category.id),
              ),
            ],
          ),
        ),
      );
}

class _DrugListPage extends StatelessWidget {
  const _DrugListPage({required this.category, required this.library});
  final KnowledgeCategory category;
  final DrugInfoLibrary library;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(category.name)),
        body: _KnowledgeBackground(
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _DrugNotice()),
              _DrugResults(items: library.search('', categoryId: category.id)),
            ],
          ),
        ),
      );
}

class _ConsumerResults extends StatelessWidget {
  const _ConsumerResults({required this.items});
  final List<ConsumerGuideItem> items;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        sliver: items.isEmpty
            ? const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('没有匹配的日用品')),
                ),
              )
            : SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text(item.name),
                      subtitle: Text(
                        item.buyingTip,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ConsumerDetailPage(item: item),
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
}

class _DrugResults extends StatelessWidget {
  const _DrugResults({required this.items});
  final List<DrugInfoItem> items;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        sliver: items.isEmpty
            ? const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('没有匹配的药品通用名')),
                ),
              )
            : SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.medication_outlined),
                      title: Text(item.name),
                      subtitle: Text(
                        item.useTags,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _DrugDetailPage(item: item),
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
}

class _ConsumerDetailPage extends StatelessWidget {
  const _ConsumerDetailPage({required this.item});
  final ConsumerGuideItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(item.name)),
        body: _KnowledgeBackground(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DetailCard(title: '30 秒选购', body: item.buyingTip),
              _DetailCard(title: '标准与监管关键词', body: item.standards),
              _DetailCard(title: '常见误区', body: item.misconception),
              _DetailCard(title: '分类', body: item.category),
            ],
          ),
        ),
      );
}

class _DrugDetailPage extends StatelessWidget {
  const _DrugDetailPage({required this.item});
  final DrugInfoItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(item.name)),
        body: _KnowledgeBackground(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _DrugNotice(inset: false),
              _DetailCard(title: '通用名称', body: item.name),
              _DetailCard(title: '药品类别', body: item.category),
              _DetailCard(title: '用途标签（仅供检索）', body: item.useTags),
              _DetailCard(title: '重点提醒', body: item.riskSummary),
              const _DetailCard(
                title: '使用前核对',
                body: '具体剂型、规格、处方/OTC 属性、用法用量、禁忌和相互作用，'
                    '必须以手中药品说明书及医生或药师意见为准。',
              ),
            ],
          ),
        ),
      );
}

class _KnowledgeBackground extends StatelessWidget {
  const _KnowledgeBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFBF8FF), Color(0xFFF1F7FF)],
          ),
        ),
        child: child,
      );
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: SearchBar(
          controller: controller,
          leading: const Icon(Icons.search),
          hintText: hint,
          onChanged: onChanged,
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: '清空搜索',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.icon,
    required this.onTap,
  });
  final List<KnowledgeCategory> categories;
  final IconData icon;
  final ValueChanged<KnowledgeCategory> onTap;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 142,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final colors = const [
              Color(0xFFE9E0FF),
              Color(0xFFDCEBFF),
              Color(0xFFDAF0E7),
              Color(0xFFFFE6D5),
              Color(0xFFF9DEEA),
              Color(0xFFFFF0C9),
            ];
            return Card(
              color: colors[index % colors.length],
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(category),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon),
                      const Spacer(),
                      Text(
                        category.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${category.count} 条'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _DrugNotice extends StatelessWidget {
  const _DrugNotice({this.inset = true});
  final bool inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: inset
            ? const EdgeInsets.fromLTRB(14, 12, 14, 0)
            : const EdgeInsets.only(bottom: 4),
        child: const Card(
          color: Color(0xFFFFE1E6),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              '仅供药品信息查询，不用于诊断、推荐用药或计算剂量。'
              '请以具体药品说明书和医生、药师意见为准。',
            ),
          ),
        ),
      );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(body),
            ],
          ),
        ),
      );
}
