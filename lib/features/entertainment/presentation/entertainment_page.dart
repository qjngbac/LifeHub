import 'package:flutter/material.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:lifehub/features/entertainment/domain/entertainment_models.dart';

class EntertainmentPage extends StatefulWidget {
  const EntertainmentPage({super.key});

  @override
  State<EntertainmentPage> createState() => _EntertainmentPageState();
}

class _EntertainmentPageState extends State<EntertainmentPage> {
  final repository = EntertainmentRepository();
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('笑话与故事')),
        body: FutureBuilder<EntertainmentLibrary>(
          future: repository.load(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('内容库加载失败'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (query.trim().isNotEmpty) {
              return FutureBuilder<List<EntertainmentItem>>(
                future: repository.visibleItems(query: query),
                builder: (context, results) => results.hasData
                    ? EntertainmentItemList(
                        items: results.data!, repository: repository)
                    : const Center(child: CircularProgressIndicator()),
              );
            }
            final library = snapshot.data!;
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(children: [
                    SearchBar(
                      hintText: '搜索标题、正文或分类',
                      leading: const Icon(Icons.search),
                      onChanged: (value) => setState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.casino_outlined),
                          label: const Text('随机一个'),
                          onPressed: () => _random(),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.sentiment_very_satisfied),
                          label: const Text('逗我一下'),
                          onPressed: () => _random(group: 'joke'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.auto_stories_outlined),
                          label: const Text('随机故事'),
                          onPressed: () => _random(group: 'story'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.star_outline),
                          label: const Text('我的收藏'),
                          onPressed: _openFavorites,
                        ),
                      ],
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
                    childAspectRatio: 1.25,
                  ),
                  itemCount: library.categories.length,
                  itemBuilder: (context, index) {
                    final category = library.categories[index];
                    final count = library.items
                        .where((item) => item.categoryId == category.id)
                        .length;
                    return Card(
                      color: _categoryColor(category.group, index),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EntertainmentCategoryPage(
                              category: category,
                              repository: repository,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(_groupIcon(category.group)),
                              const Spacer(),
                              Text(category.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text('$count 条内容',
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

  Future<void> _random({String? group}) async {
    final items = await repository.randomSequence(group: group);
    if (items.isEmpty || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntertainmentItemPage(
          item: items.first,
          items: items,
          repository: repository,
        ),
      ),
    );
  }

  Future<void> _openFavorites() async {
    final items = await repository.visibleItems(favoritesOnly: true);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('我的收藏')),
          body: EntertainmentItemList(items: items, repository: repository),
        ),
      ),
    );
  }
}

class EntertainmentCategoryPage extends StatelessWidget {
  const EntertainmentCategoryPage({
    super.key,
    required this.category,
    required this.repository,
  });
  final EntertainmentCategory category;
  final EntertainmentRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(category.name)),
        body: FutureBuilder<List<EntertainmentItem>>(
          future: repository.visibleItems(categoryId: category.id),
          builder: (context, snapshot) => snapshot.hasData
              ? EntertainmentItemList(
                  items: snapshot.data!, repository: repository)
              : const Center(child: CircularProgressIndicator()),
        ),
      );
}

class EntertainmentItemList extends StatelessWidget {
  const EntertainmentItemList({
    super.key,
    required this.items,
    required this.repository,
  });
  final List<EntertainmentItem> items;
  final EntertainmentRepository repository;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('暂无内容'))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                title: Text(item.title),
                subtitle: Text(
                  '${item.category} · 约 ${item.estimatedReadSeconds} 秒',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntertainmentItemPage(
                      item: item,
                      items: items,
                      initialIndex: index,
                      repository: repository,
                    ),
                  ),
                ),
              ),
            );
          },
        );
}

class EntertainmentItemPage extends StatefulWidget {
  const EntertainmentItemPage({
    super.key,
    required this.item,
    required this.repository,
    this.items,
    this.initialIndex = 0,
  });
  final EntertainmentItem item;
  final EntertainmentRepository repository;
  final List<EntertainmentItem>? items;
  final int initialIndex;

  @override
  State<EntertainmentItemPage> createState() => _EntertainmentItemPageState();
}

class _EntertainmentItemPageState extends State<EntertainmentItemPage> {
  bool favorite = false;
  bool blocked = false;
  bool deferred = false;
  late final List<EntertainmentItem> items;
  late int index;

  EntertainmentItem get item => items[index];

  @override
  void initState() {
    super.initState();
    items = widget.items?.isNotEmpty == true
        ? List<EntertainmentItem>.of(widget.items!)
        : [widget.item];
    index = widget.initialIndex.clamp(0, items.length - 1);
    _loadState();
    widget.repository.recordViewed(item.id);
  }

  Future<void> _loadState() async {
    final values = await Future.wait([
      widget.repository.favorites(),
      widget.repository.blocked(),
      widget.repository.deferred(),
    ]);
    if (!mounted) return;
    setState(() {
      favorite = values[0].contains(item.id);
      blocked = values[1].contains(item.id);
      deferred = values[2].contains(item.id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(item.category)),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 18),
                    SelectableText(item.body,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(height: 1.65)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('下一条'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: favorite,
                  avatar: const Icon(Icons.star_outline),
                  label: const Text('收藏'),
                  onSelected: (_) async {
                    final value =
                        await widget.repository.toggleFavorite(item.id);
                    if (mounted) setState(() => favorite = value);
                  },
                ),
                FilterChip(
                  selected: deferred,
                  avatar: const Icon(Icons.vertical_align_bottom),
                  label: const Text('置为最后'),
                  onSelected: (_) async {
                    final value =
                        await widget.repository.toggleDeferred(item.id);
                    if (mounted) setState(() => deferred = value);
                  },
                ),
                FilterChip(
                  selected: blocked,
                  avatar: const Icon(Icons.block),
                  label: const Text('屏蔽'),
                  onSelected: (_) async {
                    final value =
                        await widget.repository.toggleBlocked(item.id);
                    if (mounted) setState(() => blocked = value);
                  },
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _next() async {
    if (index >= items.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这已经是最后一条了')),
      );
      return;
    }
    setState(() => index++);
    await widget.repository.recordViewed(item.id);
    await _loadState();
  }
}

IconData _groupIcon(String group) => switch (group) {
      'joke' => Icons.sentiment_very_satisfied,
      'atmosphere' => Icons.nights_stay_outlined,
      _ => Icons.auto_stories_outlined,
    };

Color _categoryColor(String group, int index) {
  final colors = switch (group) {
    'joke' => const [Color(0xFFFFE4C7), Color(0xFFFFE0E8)],
    'atmosphere' => const [Color(0xFFE3DFFF), Color(0xFFDCE8FA)],
    _ => const [Color(0xFFDDF0E8), Color(0xFFE8E2C6)],
  };
  return colors[index % colors.length];
}
