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
  FirstAidRisk? riskFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('急救知识')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: '搜索症状、环境或处理方法',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: FutureBuilder<FirstAidKnowledge>(
              future: repository.load(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('知识库加载失败'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final knowledge = snapshot.data!;
                final counts = knowledge.riskCounts;
                final items = FirstAidRepository.filter(
                  knowledge,
                  query: query,
                  risk: riskFilter,
                );
                return Column(
                  children: [
                    _RiskFilterBar(
                      total: knowledge.items.length,
                      counts: counts,
                      selected: riskFilter,
                      onSelected: (risk) => setState(() => riskFilter = risk),
                    ),
                    Expanded(
                      child: _buildBody(knowledge, items),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 默认是场景网格；一旦搜索或按等级筛选，切换成列表视图。
  Widget _buildBody(FirstAidKnowledge knowledge, List<FirstAidItem> items) {
    final filtering = query.trim().isNotEmpty || riskFilter != null;
    final theme = Theme.of(context);
    if (!filtering) {
      final goldenEntries = [
        (id: 'q2', label: '心肺复苏 CPR', sub: '胸外按压与AED', icon: Icons.favorite),
        (id: 'q6', label: '气道梗阻', sub: '海姆立克急救法', icon: Icons.airline_seat_recline_extra_outlined),
        (id: 'q3', label: '严重大出血', sub: '直接持续压迫止血', icon: Icons.water_drop_outlined),
        (id: 'q10', label: '烧伤烫伤', sub: '流动冷水冲洗降温', icon: Icons.local_fire_department_outlined),
        (id: 'q11', label: '突发抽搐', sub: '防撞伤保护头部', icon: Icons.bolt_outlined),
        (id: 'q14', label: '疑似中风', sub: 'FAST原则识别呼救', icon: Icons.medical_information_outlined),
      ];
      final emergencyShortcuts = <({FirstAidItem item, String label, String sub, IconData icon})>[];
      for (final entry in goldenEntries) {
        FirstAidItem? found;
        for (final it in knowledge.items) {
          if (it.id == entry.id) {
            found = it;
            break;
          }
        }
        if (found != null) {
          emergencyShortcuts.add((item: found, label: entry.label, sub: entry.sub, icon: entry.icon));
        }
      }

      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _NoticeCard(notice: knowledge.notice),
            ),
          ),
          if (emergencyShortcuts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flash_on, size: 15, color: Colors.red),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '黄金急救直达',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '生死急救快速指南',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: emergencyShortcuts.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final entry = emergencyShortcuts[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FirstAidItemPage(item: entry.item),
                              ),
                            ),
                            child: Container(
                              width: 154,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.22),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Icon(entry.icon, size: 16, color: Colors.red),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          entry.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.red,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.sub,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.15,
              ),
              itemCount: knowledge.scenes.length,
              itemBuilder: (context, index) {
                final scene = knowledge.scenes[index];
                final count = knowledge.items
                    .where((item) => item.sceneId == scene.id)
                    .length;
                final accent = _getSceneAccent(scene);
                final isDark = theme.brightness == Brightness.dark;
                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: accent.withValues(alpha: isDark ? 0.40 : 0.28),
                      width: 1.2,
                    ),
                  ),
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.05),
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
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: isDark ? 0.25 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  firstAidIcon(scene.icon),
                                  size: 20,
                                  color: accent,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: isDark ? 0.22 : 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count 条',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            scene.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            scene.subEnvironments.isEmpty ? '基础急救操作与处置' : scene.subEnvironments,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('没有找到相关急救内容，换个词或清除筛选试试'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: items.length,
      itemBuilder: (context, index) => FirstAidItemTile(
        item: items[index],
        sceneName: knowledge.sceneById(items[index].sceneId)?.name ?? '',
      ),
    );
  }
}

Color _getSceneAccent(FirstAidScene scene) {
  final lum = scene.color.computeLuminance();
  if (lum > 0.6) {
    final hsl = HSLColor.fromColor(scene.color);
    return hsl
        .withSaturation((hsl.saturation * 2.5).clamp(0.55, 0.85))
        .withLightness(0.42)
        .toColor();
  }
  return scene.color;
}

/// 紧急等级筛选：109 条紧急内容此前只能靠场景网格一层层点进去。
class _RiskFilterBar extends StatelessWidget {
  const _RiskFilterBar({
    required this.total,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final int total;
  final Map<FirstAidRisk, int> counts;
  final FirstAidRisk? selected;
  final ValueChanged<FirstAidRisk?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              showCheckmark: false,
              label: Text('全部 $total'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
            for (final entry in const [
              (FirstAidRisk.emergency, '紧急'),
              (FirstAidRisk.high, '高风险'),
              (FirstAidRisk.routine, '常规'),
            ]) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                showCheckmark: false,
                label: Text('${entry.$2} ${counts[entry.$1] ?? 0}'),
                selected: selected == entry.$1,
                avatar: Icon(Icons.circle, size: 10, color: entry.$1.color),
                onSelected: (_) => onSelected(entry.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 顶部免责说明：默认折叠成两行，不再占掉首屏。
class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.notice});
  final String notice;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: InkWell(
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.notice,
                  maxLines: expanded ? null : 2,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              '适用环境：${scene.subEnvironments}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.5,
                  ),
            ),
          ),
        for (final item in items)
          FirstAidItemTile(item: item, sceneName: scene.name),
      ],
    ),
  );
}

class FirstAidItemTile extends StatelessWidget {
  const FirstAidItemTile({
    super.key,
    required this.item,
    this.sceneName = '',
  });
  final FirstAidItem item;
  final String sceneName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final risk = item.risk;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FirstAidItemPage(item: item)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 等级用"底色圆 + 文字标签"双通道表达，不只靠颜色
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: risk.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  risk == FirstAidRisk.routine
                      ? Icons.healing_outlined
                      : Icons.priority_high,
                  size: 18,
                  color: risk.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _RiskTag(risk: risk),
                        if (sceneName.isNotEmpty) _MiniTag(text: sceneName),
                        _MiniTag(text: '编号 ${item.number}'),
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
  }
}

class _RiskTag extends StatelessWidget {
  const _RiskTag({required this.risk});
  final FirstAidRisk risk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: risk.color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          risk.label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
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

/// 把 "①…；②…" 或 "1. …；2. …" 拆成有序步骤，紧急场景下一屏能看清先后顺序。
///
/// 数据里两种编号都存在（261 条中约 227 条用 ①②③、34 条用 `1. 2. 3.`），
/// 只认圆圈序号会让那 34 条退化成一大段。
List<String> splitCircledSteps(String steps) {
  final text = steps.trim();
  if (text.isEmpty) return const [];
  final circled = _splitByMarks(text, RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩]'));
  if (circled != null) return circled;
  final arabic = _splitByMarks(text, RegExp(r'\d{1,2}[\.、\)]'));
  if (arabic != null) return arabic;
  return [text];
}

/// 按 [mark] 切分；序号少于两个时返回 null 表示"这种格式不适用"。
List<String>? _splitByMarks(String text, RegExp mark) {
  final marks = <RegExpMatch>[];
  for (final match in mark.allMatches(text)) {
    final index = match.start;
    if (index == 0) {
      marks.add(match);
      continue;
    }
    final previous = text[index - 1];
    // 只认"段首"的序号，避免把"深约5cm"里的数字当成编号
    if (previous == ' ' ||
        previous == '\t' ||
        previous == '；' ||
        previous == ';') {
      marks.add(match);
    }
  }
  if (marks.length < 2) return null;

  final result = <String>[];
  for (var i = 0; i < marks.length; i++) {
    final start = marks[i].end;
    final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
    final part = text
        .substring(start, end)
        .replaceAll('；', ' ')
        .replaceAll(';', ' ')
        .trim();
    if (part.isNotEmpty) result.add(part);
  }
  return result.length >= 2 ? result : null;
}

/// 把"；"分隔的禁忌拆成条目。
List<String> splitSemicolons(String value) {
  final parts = value
      .split(RegExp('[；;]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.length >= 2 ? parts : [value.trim()];
}

class FirstAidItemPage extends StatefulWidget {
  const FirstAidItemPage({super.key, required this.item});
  final FirstAidItem item;

  @override
  State<FirstAidItemPage> createState() => _FirstAidItemPageState();
}

class _FirstAidItemPageState extends State<FirstAidItemPage> {
  final _repository = FirstAidRepository();
  // 只加载一次：放在 build 里会每次重建都换一个新 Future，导致反复重建
  late final _knowledge = _repository.load();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final steps = splitCircledSteps(item.steps);
    final prohibitions = splitSemicolons(item.prohibitions);

    return Scaffold(
      appBar: AppBar(title: const Text('处置要点')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.question,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _RiskTag(risk: item.risk),
                      _MiniTag(text: '紧急等级：${item.risk.label}'),
                      _MiniTag(text: '编号 ${item.number}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 操作步骤提前：紧急场景下"先做什么"比"为什么"重要
          _DetailSection(
            title: '操作步骤',
            icon: Icons.playlist_add_check,
            accent: theme.colorScheme.primary,
            child: steps.isEmpty
                ? const Text('暂无')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  steps[i],
                                  style: const TextStyle(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          _DetailSection(
            title: '答案',
            icon: Icons.lightbulb_outline,
            child: Text(item.answer, style: const TextStyle(height: 1.6)),
          ),
          _DetailSection(
            title: '少工具方案',
            icon: Icons.handyman_outlined,
            child: Text(item.fallback, style: const TextStyle(height: 1.6)),
          ),
          _DetailSection(
            title: '禁忌',
            icon: Icons.block,
            accent: theme.colorScheme.error,
            background: theme.colorScheme.errorContainer
                .withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in prohibitions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(line, style: const TextStyle(height: 1.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 内容来源与审核时间：急救知识必须能让用户判断"能不能信"
          FutureBuilder<FirstAidKnowledge>(
            future: _knowledge,
            builder: (context, snapshot) {
              final sources = snapshot.data?.sources ?? const [];
              final reviewedAt = snapshot.data?.reviewedAt ?? '—';
              return Card(
                margin: const EdgeInsets.only(top: 12),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '内容审核于 $reviewedAt',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (sources.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '参考来源：${sources.map((source) => source.title).join('、')}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '现场不安全时先撤离；危及生命时立即联系当地急救或救援。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
    this.accent,
    this.background,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color? accent;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
