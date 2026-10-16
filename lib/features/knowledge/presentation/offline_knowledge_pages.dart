import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifehub/features/knowledge/data/offline_knowledge_repository.dart';
import 'package:lifehub/features/knowledge/domain/offline_knowledge_models.dart';
import 'package:lifehub/features/medication/presentation/medication_page.dart';

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
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final theme = Theme.of(context);
                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF2563EB), size: 22),
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.category,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.buyingTip,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
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
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final theme = Theme.of(context);
                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.medication_outlined, color: Color(0xFF059669), size: 22),
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.category,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                            if (item.useTags.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.useTags,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            tooltip: '复制选购要点',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '【${item.name}选购要点】\n⚡ 选购要点：${item.buyingTip}\n🔍 标准依据：${item.standards}\n⚠️ 避坑提醒：${item.misconception}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制“${item.name}”选购要点到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: _KnowledgeBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF2563EB), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _StyledCard(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFF16A34A),
              titleColor: const Color(0xFF15803D),
              bgColor: const Color(0xFFF0FDF4),
              borderColor: const Color(0xFFBBF7D0),
              title: '30 秒选购要点',
              body: item.buyingTip,
            ),
            _StyledCard(
              icon: Icons.verified_outlined,
              iconColor: const Color(0xFF0284C7),
              titleColor: const Color(0xFF0369A1),
              bgColor: const Color(0xFFF0F9FF),
              borderColor: const Color(0xFFBAE6FD),
              title: '执行标准与监管关键词',
              body: item.standards,
            ),
            _StyledCard(
              icon: Icons.warning_amber_rounded,
              iconColor: const Color(0xFFD97706),
              titleColor: const Color(0xFFB45309),
              bgColor: const Color(0xFFFFFBEB),
              borderColor: const Color(0xFFFDE68A),
              title: '避坑指南 · 常见误区',
              body: item.misconception,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('复制选购要点（网购下单对照）'),
              onPressed: () {
                Clipboard.setData(ClipboardData(
                  text: '【${item.name}选购要点】\n⚡ 选购要点：${item.buyingTip}\n🔍 标准依据：${item.standards}\n⚠️ 避坑提醒：${item.misconception}',
                ));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已复制“${item.name}”选购要点到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrugDetailPage extends StatelessWidget {
  const _DrugDetailPage({required this.item});
  final DrugInfoItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            tooltip: '复制药品信息',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '【药品信息】${item.name}（${item.category}）\n⚠️ 重点提醒：${item.riskSummary}\n用途标签：${item.useTags}',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制“${item.name}”药品信息到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: _KnowledgeBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _DrugNotice(inset: false),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.medication_outlined, color: Color(0xFF059669), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.category,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (item.useTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '用途检索标签：',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            item.useTags,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _StyledCard(
              icon: Icons.error_outline_rounded,
              iconColor: const Color(0xFFE11D48),
              titleColor: const Color(0xFFBE123C),
              bgColor: const Color(0xFFFFF1F2),
              borderColor: const Color(0xFFFECDD3),
              title: '重点用药安全提醒',
              body: item.riskSummary,
            ),
            const _StyledCard(
              icon: Icons.fact_check_outlined,
              iconColor: Color(0xFF2563EB),
              titleColor: Color(0xFF1D4ED8),
              bgColor: Color(0xFFEFF6FF),
              borderColor: Color(0xFFBFDBFE),
              title: '使用前核对标准',
              body: '具体剂型、规格、处方/OTC 属性、用法用量、禁忌和相互作用，必须以手中实际药品说明书及主治医生或执业药师意见为准。',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.alarm_add_outlined, size: 18),
                    label: const Text('打开用药提醒'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MedicationPage()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: '复制药品信息',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: '【药品信息】${item.name}（${item.category}）\n⚠️ 重点提醒：${item.riskSummary}\n用途标签：${item.useTags}',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已复制“${item.name}”药品信息到剪贴板'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeBackground extends StatelessWidget {
  const _KnowledgeBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  theme.colorScheme.surface,
                  theme.colorScheme.surfaceContainerLowest,
                ]
              : [
                  const Color(0xFFFAF9FD),
                  const Color(0xFFF2F6FC),
                ],
        ),
      ),
      child: child,
    );
  }
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
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          controller: controller,
          leading: const Icon(Icons.search, size: 20),
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
                icon: const Icon(Icons.close, size: 18),
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

  static const _palettes = [
    (Color(0xFFEEF2FF), Color(0xFF4F46E5)),
    (Color(0xFFF0FDF4), Color(0xFF16A34A)),
    (Color(0xFFEFF6FF), Color(0xFF2563EB)),
    (Color(0xFFFFF7ED), Color(0xFFEA580C)),
    (Color(0xFFFAF5FF), Color(0xFF9333EA)),
    (Color(0xFFFFF1F2), Color(0xFFE11D48)),
    (Color(0xFFF0FDFA), Color(0xFF0D9488)),
    (Color(0xFFFEFCE8), Color(0xFFCA8A04)),
  ];

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 132,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final (bgColor, accentColor) = _palettes[index % _palettes.length];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: accentColor.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              color: bgColor,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(category),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: accentColor, size: 20),
                      ),
                      const Spacer(),
                      Text(
                        category.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${category.count} 条',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ),
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
            : const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFECDD3),
              width: 0.8,
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFFE11D48)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '仅供离线药品信息查阅，不用于诊断、处方推荐或计算剂量。'
                  '实际用药请以药品实物说明书及医生、药师意见为准。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9F1239),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _StyledCard extends StatelessWidget {
  const _StyledCard({
    required this.icon,
    required this.iconColor,
    required this.titleColor,
    required this.bgColor,
    required this.borderColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final Color titleColor;
  final Color bgColor;
  final Color borderColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              body,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

