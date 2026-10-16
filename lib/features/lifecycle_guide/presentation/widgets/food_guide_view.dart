import 'package:flutter/material.dart';
import 'package:lifehub/features/lifecycle_guide/application/medication_food_interaction_service.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_detail_sheet.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/food_nutrition_comparison_sheet.dart';

class FoodGuideView extends StatefulWidget {
  const FoodGuideView({
    super.key,
    required this.fruits,
    required this.vegetables,
    required this.seasonCalendar,
    required this.topics,
    this.interactionService,
  });

  final List<FruitItem> fruits;
  final List<VegetableItem> vegetables;
  final List<SeasonCalendarItem> seasonCalendar;
  final List<KnowledgeTopic> topics;
  final MedicationFoodInteractionService? interactionService;

  @override
  State<FoodGuideView> createState() => _FoodGuideViewState();
}

class _FoodGuideViewState extends State<FoodGuideView> {
  String _selectedCategory = '全部';

  @override
  Widget build(BuildContext context) {
    final categories = [
      '全部',
      '水果图鉴 (${widget.fruits.length})',
      '蔬菜图鉴 (${widget.vegetables.length})',
      for (final t in widget.topics) t.category,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              key: const PageStorageKey('food_guide_filter_chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = categories[i];
                return FilterChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = cat);
                  },
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: PageStorageKey('food_guide_list_$_selectedCategory'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // Quick tools banner (Toolbox)
              if (_selectedCategory == '全部' ||
                  _selectedCategory.startsWith('水果图鉴') ||
                  _selectedCategory.startsWith('蔬菜图鉴')) ...[
                _QuickToolsBanner(
                  onOpenCalendar: () => _showSeasonCalendar(context),
                  onOpenInteractions: () => _showInteractionsQuickView(context),
                  onOpenComparison: () => _openComparisonSheet(context, null),
                ),
                const SizedBox(height: 12),
                _InSeasonHighlightBanner(
                  seasonCalendar: widget.seasonCalendar,
                  fruits: widget.fruits,
                  vegetables: widget.vegetables,
                  onOpenCalendar: () => _showSeasonCalendar(context),
                ),
                const SizedBox(height: 14),
              ],

              // Fruits section
              if (_selectedCategory == '全部' ||
                  _selectedCategory.startsWith('水果图鉴')) ...[
                _SectionHeader(
                  title: '常见水果图鉴 (${widget.fruits.length} 种)',
                  subtitle: '营养参考、特色成分、应季月份与食用注意事项',
                ),
                const SizedBox(height: 8),
                for (final fruit in widget.fruits) ...[
                  _FruitCard(
                    fruit: fruit,
                    interactionService: widget.interactionService,
                    onCompare: () => _openComparisonSheet(context, fruit),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
              ],

              // Vegetables section
              if (_selectedCategory == '全部' ||
                  _selectedCategory.startsWith('蔬菜图鉴')) ...[
                _SectionHeader(
                  title: '常见蔬菜图鉴 (${widget.vegetables.length} 种)',
                  subtitle: '特色植化素、草酸/嘌呤/钾提示与烹饪建议',
                ),
                const SizedBox(height: 8),
                for (final veg in widget.vegetables) ...[
                  _VegetableCard(
                    veg: veg,
                    interactionService: widget.interactionService,
                    onCompare: () => _openComparisonSheet(context, veg),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
              ],

              // Food Topics
              for (final topic in widget.topics) ...[
                if (_selectedCategory == '全部' ||
                    _selectedCategory == topic.category) ...[
                  _SectionHeader(
                    title: topic.title,
                    subtitle: topic.category == '主食谷薯'
                        ? '全谷杂粮、升糖指数GI控制与健康主食搭配'
                        : topic.category == '优质蛋白质'
                            ? '肉蛋奶水产、优质蛋白摄入与痛风嘌呤安全'
                            : topic.category == '食用油脂'
                                ? '烹饪用油烟点、脂肪酸比例与健康用油指南'
                                : '食材安全存储、食品添加剂与膳食指南',
                  ),
                  const SizedBox(height: 8),
                  _TopicCard(key: ValueKey('food_topic_${topic.id}'), topic: topic),
                  const SizedBox(height: 16),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openComparisonSheet(BuildContext context, dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FoodNutritionComparisonSheet(
          initialA: item != null
              ? FoodNutritionProfile.fromItem(item)
              : FoodNutritionProfile.defaults.first,
          fruits: widget.fruits,
          vegetables: widget.vegetables,
        );
      },
    );
  }

  void _showSeasonCalendar(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text(
                      '中国大陆主产区 · 应季水果月历',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '自然成熟应季果实风味最佳、价格最实惠、农残关注度更低',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                for (final item in widget.seasonCalendar) ...[
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Theme.of(ctx)
                        .colorScheme
                        .secondaryContainer
                        .withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.month,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final f in item.fruits)
                                Chip(
                                  label: Text(f),
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  void _showInteractionsQuickView(BuildContext context) {
    final dangerFruits =
        widget.fruits.where((f) => f.alertLevel != 'none').toList();
    final dangerVegs =
        widget.vegetables.where((v) => v.alertLevel != 'none').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colorScheme = theme.colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Text(
                      '果蔬用药禁忌与注意事项速查',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '【水果注意事项与药物相互作用】',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                for (final f in dangerFruits)
                  Card(
                    color: f.alertLevel == 'danger'
                        ? colorScheme.errorContainer.withValues(alpha: 0.6)
                        : colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      title: Text(
                        f.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(f.precautions),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  '【蔬菜注意事项与草酸焯水提示】',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                for (final v in dangerVegs)
                  Card(
                    color: v.alertLevel == 'danger'
                        ? colorScheme.errorContainer.withValues(alpha: 0.6)
                        : colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      title: Text(
                        v.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${v.oxalatePurinePotassium.isNotEmpty ? '【${v.oxalatePurinePotassium}】' : ''} ${v.precautions}',
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _FruitCard extends StatelessWidget {
  const _FruitCard({
    required this.fruit,
    this.interactionService,
    this.onCompare,
  });

  final FruitItem fruit;
  final MedicationFoodInteractionService? interactionService;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final drugAlert = interactionService?.checkFoodAlert(fruit.name, fruit.tags);
    final isDanger = drugAlert?.isDanger ?? (fruit.alertLevel == 'danger');
    final isWarning = (drugAlert != null && !drugAlert.isDanger) || (fruit.alertLevel == 'warning');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: drugAlert != null
              ? colorScheme.error
              : isDanger
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: drugAlert != null ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final alertPrefix = drugAlert != null
              ? '【🚨 个人用药安全强提醒】\n您当前正在服用「${drugAlert.userDrugName}」，${drugAlert.riskDescription}\n\n'
              : '';
          showLifecycleDetailSheet(
            context,
            title: fruit.name,
            sourceBadge: drugAlert != null
                ? '用药强提醒 · ${fruit.category}'
                : '水果图鉴 · ${fruit.category}',
            subtitle: '应季：${fruit.season} | 热量：${fruit.calories}',
            warningText: drugAlert != null
                ? '🚨 正在服用「${drugAlert.userDrugName}」：${drugAlert.riskDescription}'
                : fruit.precautions,
            alertLevel: drugAlert != null ? (drugAlert.isDanger ? 'danger' : 'warning') : fruit.alertLevel,
            tags: [
              if (drugAlert != null) '🚨服药禁忌: ${drugAlert.userDrugName}',
              ...fruit.tags,
            ],
            details: alertPrefix +
                [
                  if (fruit.season.isNotEmpty) '【应季时期】${fruit.season}',
                  if (fruit.calories.isNotEmpty) '【热量参考】${fruit.calories}',
                  if (fruit.nutrition.isNotEmpty) '【主要营养】${fruit.nutrition}',
                  if (fruit.specialComponent.isNotEmpty)
                    '【特色成分】${fruit.specialComponent}',
                  if (fruit.tips.isNotEmpty) '【吃法与建议】${fruit.tips}',
                  if (fruit.precautions.isNotEmpty) '【注意事项】${fruit.precautions}',
                ].join('\n\n'),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (drugAlert != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded,
                          size: 16, color: colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '您正在服用「${drugAlert.userDrugName}」，有相互作用禁忌！',
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            fruit.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            fruit.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (fruit.calories.isNotEmpty)
                    Text(
                      fruit.calories,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (fruit.season.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '应季：${fruit.season}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Text(
                '营养：${fruit.nutrition}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (fruit.precautions.trim().isNotEmpty &&
                  fruit.precautions.trim() != '-' &&
                  fruit.precautions.trim() != '—' &&
                  (isDanger || isWarning)) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDanger
                        ? colorScheme.errorContainer.withValues(alpha: 0.5)
                        : colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDanger
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: isDanger
                            ? colorScheme.error
                            : colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fruit.precautions,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDanger
                                ? colorScheme.onErrorContainer
                                : colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VegetableCard extends StatelessWidget {
  const _VegetableCard({
    required this.veg,
    this.interactionService,
    this.onCompare,
  });

  final VegetableItem veg;
  final MedicationFoodInteractionService? interactionService;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final drugAlert = interactionService?.checkFoodAlert(veg.name, veg.tags);
    final isDanger = drugAlert?.isDanger ?? (veg.alertLevel == 'danger');
    final isWarning = (drugAlert != null && !drugAlert.isDanger) || (veg.alertLevel == 'warning');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: drugAlert != null
              ? colorScheme.error
              : isDanger
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: drugAlert != null ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final alertPrefix = drugAlert != null
              ? '【🚨 个人用药安全强提醒】\n您当前正在服用「${drugAlert.userDrugName}」，${drugAlert.riskDescription}\n\n'
              : '';
          showLifecycleDetailSheet(
            context,
            title: veg.name,
            sourceBadge: drugAlert != null
                ? '用药强提醒 · ${veg.category}'
                : '蔬菜图鉴 · ${veg.category}',
            subtitle: '主要营养：${veg.nutrition}',
            warningText: drugAlert != null
                ? '🚨 正在服用「${drugAlert.userDrugName}」：${drugAlert.riskDescription}'
                : veg.precautions,
            alertLevel: drugAlert != null ? (drugAlert.isDanger ? 'danger' : 'warning') : veg.alertLevel,
            tags: [
              if (drugAlert != null) '🚨服药禁忌: ${drugAlert.userDrugName}',
              ...veg.tags,
            ],
            details: alertPrefix +
                [
                  if (veg.calories.isNotEmpty) '【热量参考】${veg.calories}',
                  if (veg.nutrition.isNotEmpty) '【主要营养】${veg.nutrition}',
                  if (veg.specialPhyto.isNotEmpty)
                    '【特色植化素】${veg.specialPhyto}',
                  if (veg.oxalatePurinePotassium.isNotEmpty)
                    '【草酸/嘌呤/钾】${veg.oxalatePurinePotassium}',
                  if (veg.cookingAdvice.isNotEmpty)
                    '【烹饪建议】${veg.cookingAdvice}',
                  if (veg.precautions.isNotEmpty) '【注意事项】${veg.precautions}',
                ].join('\n\n'),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (drugAlert != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded,
                          size: 16, color: colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '您正在服用「${drugAlert.userDrugName}」，有相互作用禁忌！',
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            veg.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            veg.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (veg.calories.isNotEmpty)
                    Text(
                      veg.calories,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '营养：${veg.nutrition}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (veg.cookingAdvice.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '烹饪：${veg.cookingAdvice}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (veg.precautions.trim().isNotEmpty &&
                  veg.precautions.trim() != '-' &&
                  veg.precautions.trim() != '—' &&
                  (isDanger || isWarning)) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDanger
                        ? colorScheme.errorContainer.withValues(alpha: 0.5)
                        : colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDanger
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: isDanger
                            ? colorScheme.error
                            : colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          veg.precautions,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDanger
                                ? colorScheme.onErrorContainer
                                : colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickToolsBanner extends StatelessWidget {
  const _QuickToolsBanner({
    required this.onOpenCalendar,
    required this.onOpenInteractions,
    required this.onOpenComparison,
  });

  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenInteractions;
  final VoidCallback onOpenComparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _QuickToolButton(
            icon: Icons.calendar_month_rounded,
            iconColor: Colors.teal,
            title: '应季月历',
            subtitle: '当季成熟速查',
            onTap: onOpenCalendar,
          ),
          Container(
            height: 28,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _QuickToolButton(
            icon: Icons.medication_liquid_rounded,
            iconColor: Colors.deepOrange,
            title: '药物禁忌',
            subtitle: '果蔬冲突警示',
            onTap: onOpenInteractions,
          ),
          Container(
            height: 28,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _QuickToolButton(
            icon: Icons.compare_arrows_rounded,
            iconColor: Colors.indigo,
            title: '营养对比',
            subtitle: '控糖热量PK',
            onTap: onOpenComparison,
          ),
        ],
      ),
    );
  }
}

class _QuickToolButton extends StatelessWidget {
  const _QuickToolButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatefulWidget {
  const _TopicCard({
    super.key,
    required this.topic,
  });

  final KnowledgeTopic topic;

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _isExpanded = false;

  void _openDetailSheet() {
    final topic = widget.topic;
    final details = topic.subsections
        .map((s) {
          final lines = <String>['【${s.title}】'];
          for (final b in s.bullets) {
            lines.add('• $b');
          }
          for (final tbl in s.tables) {
            for (final r in tbl) {
              lines.add(r.entries.map((e) => '${e.key}：${e.value}').join(' | '));
            }
          }
          return lines.join('\n');
        })
        .join('\n\n');
    showLifecycleDetailSheet(
      context,
      title: topic.title,
      sourceBadge: '食物指南 · ${topic.category}',
      details: details,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topic = widget.topic;

    final firstBullet = topic.subsections.isNotEmpty &&
            topic.subsections.first.bullets.isNotEmpty
        ? topic.subsections.first.bullets.first
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      topic.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '查看与复制详情',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _openDetailSheet,
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              if (!_isExpanded && firstBullet != null) ...[
                const SizedBox(height: 6),
                Text(
                  firstBullet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                for (final sub in topic.subsections) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (sub.bullets.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final b in sub.bullets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('• ',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      )),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (sub.tables.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final tbl in sub.tables) ...[
                            for (final row in tbl)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    for (final e in row.entries)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 76,
                                              child: Text(
                                                e.key,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: colorScheme.outline,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                e.value,
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  if (sub != topic.subsections.last)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InSeasonHighlightBanner extends StatelessWidget {
  const _InSeasonHighlightBanner({
    required this.seasonCalendar,
    required this.fruits,
    required this.vegetables,
    required this.onOpenCalendar,
  });

  final List<SeasonCalendarItem> seasonCalendar;
  final List<FruitItem> fruits;
  final List<VegetableItem> vegetables;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentMonth = DateTime.now().month;
    final monthStr = '$currentMonth月';

    // Find priority fruits for this month
    final calItem = seasonCalendar.firstWhere(
      (c) => c.month.contains('$currentMonth'),
      orElse: () => seasonCalendar.isNotEmpty
          ? seasonCalendar.first
          : const SeasonCalendarItem(month: '', fruits: []),
    );

    // Collect matching fruits and vegetables
    final highlightedFruits = fruits.where((f) {
      return calItem.fruits.any((name) => f.name.contains(name) || name.contains(f.name)) ||
          f.season.contains(monthStr) ||
          f.season.contains('全年');
    }).toList();

    final highlightedVegs = vegetables.where((v) {
      return v.season.contains(monthStr) || v.season.contains('全年');
    }).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.45),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🌿 $currentMonth月正当季 · 最值吃的时令鲜果与蔬菜',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '依据《附录 E 时令月历》，当季成熟、营养巅峰、农残最低',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onOpenCalendar,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '月历',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 14, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in highlightedFruits.take(8)) ...[
                  _InSeasonMiniCard(
                    title: f.name,
                    category: f.category,
                    calories: f.calories,
                    badge: f.tags.isNotEmpty ? f.tags.first : '当季优选',
                    isFruit: true,
                    onTap: () {
                      showLifecycleDetailSheet(
                        context,
                        title: f.name,
                        sourceBadge: '应季优选 · ${f.category}',
                        subtitle: '应季：${f.season} | 热量：${f.calories}',
                        warningText: f.precautions,
                        alertLevel: f.alertLevel,
                        tags: f.tags,
                        details: [
                          if (f.season.isNotEmpty) '【应季时期】${f.season}',
                          if (f.calories.isNotEmpty) '【热量参考】${f.calories}',
                          if (f.nutrition.isNotEmpty) '【主要营养】${f.nutrition}',
                          if (f.specialComponent.isNotEmpty)
                            '【特色成分】${f.specialComponent}',
                          if (f.tips.isNotEmpty) '【吃法与建议】${f.tips}',
                          if (f.precautions.isNotEmpty) '【注意事项】${f.precautions}',
                        ].join('\n\n'),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                for (final v in highlightedVegs.take(6)) ...[
                  _InSeasonMiniCard(
                    title: v.name,
                    category: v.category,
                    calories: v.calories,
                    badge: v.tags.isNotEmpty ? v.tags.first : '时令蔬菜',
                    isFruit: false,
                    onTap: () {
                      showLifecycleDetailSheet(
                        context,
                        title: v.name,
                        sourceBadge: '时令蔬菜 · ${v.category}',
                        subtitle: '主要营养：${v.nutrition}',
                        warningText: v.precautions,
                        alertLevel: v.alertLevel,
                        tags: v.tags,
                        details: [
                          if (v.calories.isNotEmpty) '【热量参考】${v.calories}',
                          if (v.nutrition.isNotEmpty) '【主要营养】${v.nutrition}',
                          if (v.specialPhyto.isNotEmpty)
                            '【特色植化素】${v.specialPhyto}',
                          if (v.oxalatePurinePotassium.isNotEmpty)
                            '【草酸/嘌呤/钾】${v.oxalatePurinePotassium}',
                          if (v.cookingAdvice.isNotEmpty)
                            '【烹饪建议】${v.cookingAdvice}',
                          if (v.precautions.isNotEmpty) '【注意事项】${v.precautions}',
                        ].join('\n\n'),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InSeasonMiniCard extends StatelessWidget {
  const _InSeasonMiniCard({
    required this.title,
    required this.category,
    required this.calories,
    required this.badge,
    required this.isFruit,
    required this.onTap,
  });

  final String title;
  final String category;
  final String calories;
  final String badge;
  final bool isFruit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 130,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isFruit ? Icons.apple_outlined : Icons.grass_outlined,
                    size: 14,
                    color: isFruit ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isFruit
                      ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                      : colorScheme.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isFruit
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                calories.replaceAll(' (可食部)', ''),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
