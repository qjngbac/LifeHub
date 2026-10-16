import 'package:flutter/material.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:lifehub/features/entertainment/domain/entertainment_models.dart';

/// 分组中文名：数据里的 group 只有英文标识，直接铺在界面上没人看得懂。
const List<String> _groupOrder = ['joke', 'story', 'atmosphere'];
const Map<String, String> _groupLabel = {
  'joke': '笑话与段子',
  'story': '故事会',
  'atmosphere': '睡前 · 治愈 · 悬疑',
};
const Map<String, String> _groupEmoji = {
  'joke': '😄',
  'story': '📚',
  'atmosphere': '🌙',
};
const Map<String, String> _groupHint = {
  'joke': '一句话就能笑',
  'story': '2 分钟读完一篇',
  'atmosphere': '睡前、治愈与悬疑短篇',
};

/// 分类专属 emoji：32 个分类此前只用 3 套配色 ×3 个图标，
/// 13 个笑话类卡片长得一模一样，只能靠文字辨认。
const Map<String, String> _categoryEmoji = {
  '普通笑话': '😄',
  '冷笑话': '🧊',
  '谐音梗': '🔤',
  '脑筋急转弯': '🤔',
  '反转笑话': '🔄',
  '程序员笑话': '💻',
  '校园笑话': '🎒',
  '职场笑话': '💼',
  '生活趣事': '🛒',
  '恋爱笑话': '💌',
  '儿童笑话': '🧒',
  '动物笑话': '🐾',
  '情侣笑话': '💞',
  '寓言故事': '🦊',
  '成语故事': '📜',
  '历史故事': '🏛️',
  '民间故事': '🧺',
  '神话故事': '🐉',
  '哲理故事': '🪷',
  '励志故事': '🌱',
  '爱情故事': '🌹',
  '友情故事': '🤝',
  '亲情故事': '🏡',
  '科幻故事': '🚀',
  '冒险故事': '🧭',
  '童话故事': '🏰',
  '名人小故事': '🎩',
  '一分钟历史': '⏳',
  '睡前故事': '🌙',
  '治愈故事': '🍵',
  '悬疑故事': '🔍',
  '微小说': '📖',
};

String _emojiFor(EntertainmentCategory category) =>
    _categoryEmoji[category.name] ??
    _groupEmoji[category.group] ??
    '🎈';

/// 长度标签：替换原来几乎恒为"约 8-9 秒"的无信息量徽章。
String _lengthLabel(EntertainmentItem item) {
  if (item.contentType == 'riddle') return '考考你';
  final length = item.body.replaceAll(RegExp(r'\s+'), '').length;
  if (length <= 40) return '一句话';
  if (length <= 200) return '1 分钟';
  final minutes = (length / 260).ceil().clamp(2, 30);
  return '$minutes 分钟';
}

/// 脑筋急转弯的正文形如"答案：球门"，抽出来才能做到"先想再揭晓"。
String? _riddleAnswer(EntertainmentItem item) {
  if (item.contentType != 'riddle') return null;
  final body = item.body.trim();
  for (final prefix in const ['答案：', '答案:']) {
    if (body.startsWith(prefix)) {
      return body.substring(prefix.length).trim();
    }
  }
  return null;
}

class EntertainmentPage extends StatefulWidget {
  const EntertainmentPage({super.key});

  @override
  State<EntertainmentPage> createState() => _EntertainmentPageState();
}

class _EntertainmentPageState extends State<EntertainmentPage> {
  final repository = EntertainmentRepository();
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笑话与故事'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'favorites') {
                _openList(
                  title: '我的收藏',
                  load: () => repository.visibleItems(favoritesOnly: true),
                  emptyHint: '还没有收藏\n在内容页点「收藏」就会出现在这里',
                );
              } else {
                _openList(
                  title: '屏蔽管理',
                  load: repository.blockedItems,
                  emptyHint: '没有被屏蔽的内容\n误触「屏蔽」后可在这里恢复',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'favorites', child: Text('我的收藏')),
              PopupMenuItem(value: 'blocked', child: Text('屏蔽管理')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _query,
              hintText: '搜索标题、正文或分类',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_query.clear),
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: FutureBuilder<EntertainmentLibrary>(
              future: repository.load(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('内容库加载失败'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_query.text.trim().isNotEmpty) {
                  return FutureBuilder<List<EntertainmentItem>>(
                    future: repository.visibleItems(query: _query.text),
                    builder: (context, results) => results.hasData
                        ? EntertainmentItemList(
                            items: results.data!,
                            repository: repository,
                            emptyHint: '没有找到与「${_query.text.trim()}」相关的内容',
                          )
                        : const Center(child: CircularProgressIndicator()),
                  );
                }
                return _buildSections(context, snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSections(BuildContext context, EntertainmentLibrary library) {
    final theme = Theme.of(context);
    final byGroup = <String, List<EntertainmentCategory>>{};
    for (final category in library.categories) {
      (byGroup[category.group] ??= []).add(category);
    }
    final countByCategory = <String, int>{};
    for (final item in library.items) {
      countByCategory[item.categoryId] =
          (countByCategory[item.categoryId] ?? 0) + 1;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(context)),
        for (final group in _groupOrder)
          if ((byGroup[group] ?? const []).isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _groupEmoji[group] ?? '🎈',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _groupLabel[group] ?? group,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _groupHint[group] ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: byGroup[group]!.length,
                itemBuilder: (context, index) {
                  final category = byGroup[group]![index];
                  return _CategoryCard(
                    emoji: _emojiFor(category),
                    name: category.name,
                    count: countByCategory[category.id] ?? 0,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EntertainmentCategoryPage(
                            category: category,
                            repository: repository,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  /// 顶部入口卡。
  ///
  /// 原来有三个按钮：「来一条（全库随机）/ 逗我一下（笑话+脑筋急转弯）/
  /// 听个故事（故事类）」。因为"笑话+脑筋急转弯"与"故事"正好把 793 条
  /// 内容切成两半，「来一条」只是这两个的并集，属于冗余；
  /// 三个按钮还会挤到第二行。现在只留两个语义互补的入口，一行排开。
  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final start = isDark
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : const Color(0xFFF0E9FF);
    final end = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFFFF1E4);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [start, end]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天来点什么？',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      _random(contentTypes: const {'joke', 'riddle'}),
                  icon: const Icon(Icons.sentiment_very_satisfied, size: 18),
                  // 窄屏时优先缩小字号，避免折成两行
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('逗我一下'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _random(contentTypes: const {'story'}),
                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('听个故事'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _random({Set<String>? contentTypes}) async {
    final items = await repository.randomSequence(contentTypes: contentTypes);
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

  Future<void> _openList({
    required String title,
    required Future<List<EntertainmentItem>> Function() load,
    required String emptyHint,
  }) async {
    final items = await load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: EntertainmentItemList(
            items: items,
            repository: repository,
            emptyHint: emptyHint,
          ),
        ),
      ),
    );
  }
}

/// 分类小卡：emoji + 名称 + 条数。比 32 张同款大卡好扫得多。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.emoji,
    required this.name,
    required this.count,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isDark
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const Spacer(),
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$count 条',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
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
    appBar: AppBar(
      title: Text('${_emojiFor(category)} ${category.name}'),
    ),
    body: FutureBuilder<List<EntertainmentItem>>(
      future: repository.visibleItems(categoryId: category.id),
      builder: (context, snapshot) => snapshot.hasData
          ? EntertainmentItemList(
              items: snapshot.data!,
              repository: repository,
              emptyHint: '这个分类暂时没有内容',
            )
          : const Center(child: CircularProgressIndicator()),
    ),
  );
}

/// 内容列表：带正文摘要、长度标签、收藏与已读标记。
class EntertainmentItemList extends StatefulWidget {
  const EntertainmentItemList({
    super.key,
    required this.items,
    required this.repository,
    this.emptyHint = '暂无内容',
  });

  final List<EntertainmentItem> items;
  final EntertainmentRepository repository;
  final String emptyHint;

  @override
  State<EntertainmentItemList> createState() => _EntertainmentItemListState();
}

class _EntertainmentItemListState extends State<EntertainmentItemList> {
  Set<String> _favorites = const {};
  Set<String> _history = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final favorites = await widget.repository.favorites();
    final history = await widget.repository.history();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _history = history.toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.emptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final answer = _riddleAnswer(item);
        final isRead = _history.contains(item.id);
        // 脑筋急转弯正文就是答案，列表里不能直接剧透
        final preview = answer != null
            ? '点击揭晓答案'
            : item.body.replaceAll('\n', ' ').trim();

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EntertainmentItemPage(
                    item: item,
                    items: widget.items,
                    initialIndex: index,
                    repository: widget.repository,
                  ),
                ),
              );
              // 回来后刷新"已读 / 收藏"标记
              if (mounted) await _load();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_favorites.contains(item.id)) ...[
                              Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isRead
                                      ? theme.colorScheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.9),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _MiniTag(text: _lengthLabel(item)),
                            const SizedBox(width: 6),
                            if (isRead) const _MiniTag(text: '已读'),
                            if (isRead) const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                item.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
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
  bool revealed = false;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = _riddleAnswer(item);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.category),
        actions: [
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${index + 1}/${items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        // 左右滑切换上一条 / 下一条
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) {
            _next();
          } else if (velocity > 120) {
            _previous();
          }
        },
        behavior: HitTestBehavior.deferToChild,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _MiniTag(text: _lengthLabel(item)),
                        const Spacer(),
                        if (favorite)
                          Icon(
                            Icons.star,
                            size: 18,
                            color: Colors.amber.shade700,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (answer == null)
                      SelectableText(
                        item.body,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.75),
                      )
                    else if (revealed)
                      SelectableText(
                        answer,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          height: 1.6,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: FilledButton.tonalIcon(
                            onPressed: () => setState(() => revealed = true),
                            icon: const Icon(Icons.lightbulb_outline),
                            label: const Text('点击揭晓答案'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: index == 0 ? null : _previous,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('上一条'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('下一条'),
                    ),
                  ),
                ),
              ],
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
                    if (!context.mounted) return;
                    setState(() => blocked = value);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            value ? '已屏蔽，可在「屏蔽管理」里恢复' : '已取消屏蔽',
                          ),
                        ),
                      );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '左右滑动也可以切换上一条 / 下一条',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previous() async {
    if (index == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这已经是第一条了')));
      return;
    }
    setState(() => index--);
    await widget.repository.recordViewed(item.id);
    await _loadState();
  }

  Future<void> _next() async {
    if (index >= items.length - 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这已经是最后一条了')));
      return;
    }
    setState(() => index++);
    await widget.repository.recordViewed(item.id);
    await _loadState();
  }
}
