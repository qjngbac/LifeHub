import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/lifecycle_guide/application/medication_food_interaction_service.dart';
import 'package:lifehub/features/lifecycle_guide/data/lifecycle_repository.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/environment_guide_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/food_guide_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_detail_sheet.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_stage_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/safety_pitfalls_view.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';

class LifecycleGuidePage extends ConsumerStatefulWidget {
  const LifecycleGuidePage({
    super.key,
    this.repository,
    this.interactionService,
  });

  final LifecycleRepository? repository;
  final MedicationFoodInteractionService? interactionService;

  @override
  ConsumerState<LifecycleGuidePage> createState() => _LifecycleGuidePageState();
}

class _LifecycleGuidePageState extends ConsumerState<LifecycleGuidePage>
    with SingleTickerProviderStateMixin {
  late final _repository = widget.repository ?? LifecycleRepository();
  final _searchCtrl = TextEditingController();
  late final Future<LifecycleCatalog> _catalogFuture =
      _repository.loadCatalog();
  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  MedicationFoodInteractionService? _interactionService;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initInteractionService();
  }

  Future<void> _initInteractionService() async {
    if (widget.interactionService != null) {
      if (mounted) {
        setState(() {
          _interactionService = widget.interactionService;
        });
      }
      return;
    }
    try {
      final db = ref.read(databaseProvider);
      final repo = MedicationRepository(db);
      final service =
          await MedicationFoodInteractionService.fromRepository(repo);
      if (mounted) {
        setState(() {
          _interactionService = service;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _interactionService = const MedicationFoodInteractionService();
        });
      }
    }
  }

  static const _hotKeywords = [
    '西柚',
    '甲醛',
    'A类',
    '菠菜',
    '老人防跌倒',
    '优质蛋白',
    '低GI主食',
    '防晒衣',
    '枕头高度',
    '辟谣',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('生命选品'),
        actions: [
          IconButton(
            tooltip: '模块使用说明',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showModuleInfo(context),
          ),
        ],
      ),
      body: FutureBuilder<LifecycleCatalog>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('知识库加载失败：${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final catalog = snapshot.data!;
          final isSearching = _searchQuery.trim().isNotEmpty;
          final searchResults = isSearching ? catalog.search(_searchQuery) : const <LifecycleSearchResult>[];

          return Column(
            children: [
              // Dedicated Search Bar (Scoped strictly to this module)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索水果、蔬菜、日用品、人生阶段、禁忌避坑...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),

              // Hot Search Keyword Chips (when not searching or to quickly fill search)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (final kw in _hotKeywords) ...[
                      ActionChip(
                        label: Text(kw),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 11),
                        onPressed: () {
                          // Clean keyword query for better search matches
                          final cleanKw = kw
                              .replaceAll('药物禁忌', '西柚')
                              .replaceAll('月历', '应季')
                              .replaceAll('防晒衣UPF', '防晒')
                              .replaceAll('婴幼儿 A类', 'A类');
                          _searchCtrl.text = cleanKw;
                          setState(() => _searchQuery = cleanKw);
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),

              // Main content: either search results or 4-tab views
              Expanded(
                child: isSearching
                    ? _buildSearchResultsView(context, searchResults)
                    : Column(
                        children: [
                          TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              Tab(text: '人生阶段 (${catalog.stages.length})'),
                              Tab(
                                  text:
                                      '食物与水果 (${catalog.fruits.length + catalog.vegetables.length})'),
                              Tab(text: '日用环境 (${catalog.envTopics.length})'),
                              Tab(
                                  text:
                                      '避坑与图谱 (${catalog.drugInteractions.length + catalog.rumors.length + catalog.checkupSchedule.length + catalog.exercisePrescriptions.length})'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                LifecycleStageView(stages: catalog.stages, checkupSchedule: catalog.checkupSchedule),
                                FoodGuideView(
                                  fruits: catalog.fruits,
                                  vegetables: catalog.vegetables,
                                  seasonCalendar: catalog.seasonCalendar,
                                  topics: catalog.foodTopics,
                                  interactionService: _interactionService,
                                ),
                                EnvironmentGuideView(
                                  topics: catalog.envTopics,
                                  replacementSchedule:
                                      catalog.replacementSchedule,
                                ),
                                SafetyPitfallsView(
                                  drugInteractions: catalog.drugInteractions,
                                  rumors: catalog.rumors,
                                  checkups: catalog.checkupSchedule,
                                  exerciseTopics:
                                      catalog.exercisePrescriptions,
                                  commonPitfalls: catalog.commonPitfalls,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchResultsView(
    BuildContext context,
    List<LifecycleSearchResult> results,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                '未在生命选品库中找到与“$_searchQuery”相关的条目',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '提示：可尝试缩短搜索词，如搜索“西柚”、“甲醛”、“A类”、“蛋白”等',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        final isDanger = item.alertLevel == 'danger';
        final isWarning = item.alertLevel == 'warning';

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDanger
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              showLifecycleDetailSheet(
                context,
                title: item.title,
                sourceBadge: item.sourceBadge,
                subtitle: item.subtitle,
                details: item.details,
                warningText: item.warningText,
                alertLevel: item.alertLevel,
                tags: item.tags,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.sourceBadge,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isDanger || isWarning)
                        Icon(
                          isDanger
                              ? Icons.error_outline
                              : Icons.warning_amber_rounded,
                          size: 16,
                          color: isDanger
                              ? colorScheme.error
                              : colorScheme.tertiary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.summary,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showModuleInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('生命选品知识库说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '【模块定位】\n本库覆盖人生 8 大阶段与 3 大专项日用品、50+ 种水果与蔬菜图鉴、优质蛋白、全谷主食、居家与日化环境安全指南及药物食物相互作用。\n',
                style: TextStyle(height: 1.4),
              ),
              Text(
                '【边界声明】\n本库为日常选品与生活参考，不是医疗诊断与处方建议；涉及疾病治疗请遵循专业医师医嘱。\n',
                style: TextStyle(height: 1.4),
              ),
              Text(
                '【纯离线搜索】\n所有资料已离线打包在本地应用中，在顶部搜索栏输入即可享受 sub-3ms 毫秒级极速检索。',
                style: TextStyle(height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}
