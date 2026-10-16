import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';

class FoodNutritionProfile {
  const FoodNutritionProfile({
    required this.name,
    required this.category,
    required this.calories, // kcal / 100g
    required this.dietaryFiber, // g / 100g
    required this.vitaminC, // mg / 100g
    required this.potassium, // mg / 100g
    required this.gi, // GI score
    required this.dietTip,
  });

  final String name;
  final String category;
  final double calories;
  final double dietaryFiber;
  final double vitaminC;
  final double potassium;
  final int gi;
  final String dietTip;

  String get giLevel {
    if (gi < 55) return '低 GI (控糖友好)';
    if (gi <= 69) return '中 GI (适量食用)';
    return '高 GI (快升糖慎食)';
  }

  Color get giColor {
    if (gi < 55) return Colors.green.shade700;
    if (gi <= 69) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  static const List<FoodNutritionProfile> defaults = [
    FoodNutritionProfile(
      name: '苹果',
      category: '水果',
      calories: 52,
      dietaryFiber: 1.7,
      vitaminC: 4.0,
      potassium: 119,
      gi: 36,
      dietTip: '低GI富含果胶，饱腹感强，减脂与慢病控糖的经典首选。',
    ),
    FoodNutritionProfile(
      name: '西瓜',
      category: '水果',
      calories: 26,
      dietaryFiber: 0.4,
      vitaminC: 6.0,
      potassium: 87,
      gi: 72,
      dietTip: '热量极低但升糖指数高达72，糖友一次进食不宜超过100g。',
    ),
    FoodNutritionProfile(
      name: '香蕉',
      category: '水果',
      calories: 93,
      dietaryFiber: 1.2,
      vitaminC: 8.0,
      potassium: 256,
      gi: 52,
      dietTip: '高钾抗疲劳，但热量较蔬果偏高，运动后补糖补钾极佳。',
    ),
    FoodNutritionProfile(
      name: '猕猴桃/奇异果',
      category: '水果',
      calories: 61,
      dietaryFiber: 2.6,
      vitaminC: 62.0,
      potassium: 312,
      gi: 38,
      dietTip: '超高维C与高纤维，低GI平稳血糖，通便与抗氧化明星。',
    ),
    FoodNutritionProfile(
      name: '橙子/柑橘',
      category: '水果',
      calories: 48,
      dietaryFiber: 1.6,
      vitaminC: 33.0,
      potassium: 159,
      gi: 43,
      dietTip: '维C与黄酮丰富，低GI，完整果肉食用比鲜榨橙汁好得多。',
    ),
    FoodNutritionProfile(
      name: '草莓',
      category: '水果',
      calories: 32,
      dietaryFiber: 1.1,
      vitaminC: 47.0,
      potassium: 131,
      gi: 41,
      dietTip: '低热量高维C，色泽明艳抗氧化强，非常适合减脂期加餐。',
    ),
    FoodNutritionProfile(
      name: '蓝莓',
      category: '水果',
      calories: 57,
      dietaryFiber: 2.4,
      vitaminC: 9.7,
      potassium: 77,
      gi: 34,
      dietTip: '花青素含量冠军，视力保护与心血管抗炎，低GI控糖安心。',
    ),
    FoodNutritionProfile(
      name: '西柚/葡萄柚',
      category: '水果',
      calories: 42,
      dietaryFiber: 1.2,
      vitaminC: 38.0,
      potassium: 119,
      gi: 25,
      dietTip: '超低GI与胰岛素敏感度友好，但正在服用他汀/降压药者严禁食用！',
    ),
    FoodNutritionProfile(
      name: '冬枣',
      category: '水果',
      calories: 105,
      dietaryFiber: 2.2,
      vitaminC: 243.0,
      potassium: 375,
      gi: 50,
      dietTip: '维C天花板，但糖分高热量过百，每日宜控制在5-8颗以内。',
    ),
    FoodNutritionProfile(
      name: '梨',
      category: '水果',
      calories: 51,
      dietaryFiber: 2.1,
      vitaminC: 5.0,
      potassium: 115,
      gi: 38,
      dietTip: '富含不溶性膳食纤维石细胞，润燥通便，升糖温和。',
    ),
    FoodNutritionProfile(
      name: '菠菜',
      category: '蔬菜',
      calories: 28,
      dietaryFiber: 1.7,
      vitaminC: 32.0,
      potassium: 311,
      gi: 15,
      dietTip: '高钾高叶酸，极低GI，焯水后草酸大幅去除，减脂黄金蔬菜。',
    ),
    FoodNutritionProfile(
      name: '西蓝花',
      category: '蔬菜',
      calories: 36,
      dietaryFiber: 1.6,
      vitaminC: 56.0,
      potassium: 206,
      gi: 15,
      dietTip: '萝卜硫素抗癌活性极强，维C超高，减脂健身人群常备。',
    ),
    FoodNutritionProfile(
      name: '黄瓜',
      category: '蔬菜',
      calories: 16,
      dietaryFiber: 0.5,
      vitaminC: 9.0,
      potassium: 102,
      gi: 15,
      dietTip: '含水量高达96%，热量微乎其微，减脂期饥饿解馋神器。',
    ),
    FoodNutritionProfile(
      name: '番茄',
      category: '蔬菜',
      calories: 15,
      dietaryFiber: 1.2,
      vitaminC: 19.0,
      potassium: 179,
      gi: 15,
      dietTip: '熟吃番茄红素吸收翻倍，生吃维C保留完全，低糖低卡。',
    ),
    FoodNutritionProfile(
      name: '苦瓜',
      category: '蔬菜',
      calories: 22,
      dietaryFiber: 2.8,
      vitaminC: 56.0,
      potassium: 256,
      gi: 15,
      dietTip: '苦瓜多肽与皂苷有助胰岛素活性，超高纤维，慢病控糖极品。',
    ),
    FoodNutritionProfile(
      name: '芹菜',
      category: '蔬菜',
      calories: 16,
      dietaryFiber: 1.4,
      vitaminC: 8.0,
      potassium: 260,
      gi: 15,
      dietTip: '芹菜素与高钾协同利尿降钠，咀嚼耗能高，减脂必选。',
    ),
    FoodNutritionProfile(
      name: '胡萝卜',
      category: '蔬菜',
      calories: 39,
      dietaryFiber: 2.8,
      vitaminC: 13.0,
      potassium: 190,
      gi: 39,
      dietTip: 'β-胡萝卜素护眼护黏膜，少许油脂翻炒吸收率更上一层楼。',
    ),
    FoodNutritionProfile(
      name: '土豆/马铃薯',
      category: '蔬菜',
      calories: 81,
      dietaryFiber: 1.1,
      vitaminC: 14.0,
      potassium: 342,
      gi: 62,
      dietTip: '本质属高淀粉主食！替代部分白米饭可补充钾元素，切忌当菜吃。',
    ),
  ];

  static FoodNutritionProfile fromItem(dynamic item) {
    if (item is FruitItem) {
      final matched = defaults.where((p) => item.name.contains(p.name) || p.name.contains(item.name));
      if (matched.isNotEmpty) return matched.first;
      final calNum = double.tryParse(item.calories.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 50.0;
      return FoodNutritionProfile(
        name: item.name,
        category: '水果',
        calories: calNum,
        dietaryFiber: 1.5,
        vitaminC: 15.0,
        potassium: 130.0,
        gi: 40,
        dietTip: item.precautions.isNotEmpty ? item.precautions : '天然水果营养均衡，建议适量食用。',
      );
    } else if (item is VegetableItem) {
      final matched = defaults.where((p) => item.name.contains(p.name) || p.name.contains(item.name));
      if (matched.isNotEmpty) return matched.first;
      final calNum = double.tryParse(item.calories.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 25.0;
      return FoodNutritionProfile(
        name: item.name,
        category: '蔬菜',
        calories: calNum,
        dietaryFiber: 1.8,
        vitaminC: 25.0,
        potassium: 200.0,
        gi: 15,
        dietTip: item.cookingAdvice.isNotEmpty ? item.cookingAdvice : '深色蔬菜富含植化素，极低升糖，提倡天天多吃。',
      );
    }
    return defaults.first;
  }
}

class FoodNutritionComparisonSheet extends StatefulWidget {
  const FoodNutritionComparisonSheet({
    super.key,
    required this.initialA,
    this.initialB,
    required this.fruits,
    required this.vegetables,
  });

  final FoodNutritionProfile initialA;
  final FoodNutritionProfile? initialB;
  final List<FruitItem> fruits;
  final List<VegetableItem> vegetables;

  @override
  State<FoodNutritionComparisonSheet> createState() =>
      _FoodNutritionComparisonSheetState();
}

class _FoodNutritionComparisonSheetState
    extends State<FoodNutritionComparisonSheet> {
  late FoodNutritionProfile _itemA;
  late FoodNutritionProfile _itemB;
  late final List<FoodNutritionProfile> _allProfiles;

  @override
  void initState() {
    super.initState();
    _itemA = widget.initialA;

    final map = <String, FoodNutritionProfile>{};
    for (final p in FoodNutritionProfile.defaults) {
      map[p.name] = p;
    }
    for (final f in widget.fruits) {
      final p = FoodNutritionProfile.fromItem(f);
      map[p.name] = p;
    }
    for (final v in widget.vegetables) {
      final p = FoodNutritionProfile.fromItem(v);
      map[p.name] = p;
    }
    _allProfiles = map.values.toList();

    _itemB = widget.initialB ??
        (_itemA.name == '苹果'
            ? (_allProfiles.firstWhere((p) => p.name == '西瓜', orElse: () => _allProfiles[1]))
            : (_allProfiles.firstWhere((p) => p.name == '苹果', orElse: () => _allProfiles[0])));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final colorA = colorScheme.primary;
    final colorB = Colors.deepOrange.shade600;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.compare_arrows_rounded,
                    color: colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  '果蔬营养双栏对比与雷达',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              '针对减脂、控糖、高血压及服药人群的 5 大核心营养指标直观对比',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),

            // Selectors Row
            Row(
              children: [
                Expanded(
                  child: _buildFoodSelector(
                    label: '蔬果 A',
                    current: _itemA,
                    themeColor: colorA,
                    onSelected: (p) => setState(() => _itemA = p),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: colorScheme.outline,
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildFoodSelector(
                    label: '蔬果 B',
                    current: _itemB,
                    themeColor: colorB,
                    onSelected: (p) => setState(() => _itemB = p),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Radar Chart Visualization
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendIndicator(_itemA.name, colorA),
                        const SizedBox(width: 24),
                        _buildLegendIndicator(_itemB.name, colorB),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _NutritionRadarPainter(
                          profileA: _itemA,
                          profileB: _itemB,
                          colorA: colorA,
                          colorB: colorB,
                          textColor: colorScheme.onSurface,
                          outlineColor: colorScheme.outlineVariant,
                        ),
                        child: Container(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '注：雷达向外延展代表该维度越具优势（热量与GI越低越占优，纤维、维C、钾越高越占优）',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Comparative Metrics List
            _buildMetricComparisonCard(
              title: '热量 (kcal / 100g)',
              subtitle: '减脂期摄入热量越低越容易达成热量缺口',
              valA: '${_itemA.calories} kcal',
              valB: '${_itemB.calories} kcal',
              colorA: colorA,
              colorB: colorB,
              aWins: _itemA.calories < _itemB.calories,
              bWins: _itemB.calories < _itemA.calories,
              winNote: _itemA.calories < _itemB.calories
                  ? '${_itemA.name} 热量更低，更有利于减脂控卡'
                  : (_itemB.calories < _itemA.calories
                      ? '${_itemB.name} 热量更低，更有利于减脂控卡'
                      : '两者热量相当'),
            ),
            const SizedBox(height: 10),

            _buildMetricComparisonCard(
              title: '血糖生成指数 (GI)',
              subtitle: '<55为低GI升糖平稳；≥70为高GI升糖迅猛',
              valA: 'GI ${_itemA.gi} (${_itemA.giLevel})',
              valB: 'GI ${_itemB.gi} (${_itemB.giLevel})',
              colorA: _itemA.giColor,
              colorB: _itemB.giColor,
              aWins: _itemA.gi < _itemB.gi,
              bWins: _itemB.gi < _itemA.gi,
              winNote: _itemA.gi < _itemB.gi
                  ? '${_itemA.name} 升糖明显更平稳，控糖人群更优'
                  : (_itemB.gi < _itemA.gi
                      ? '${_itemB.name} 升糖明显更平稳，控糖人群更优'
                      : '两者升糖指数接近'),
            ),
            const SizedBox(height: 10),

            _buildMetricComparisonCard(
              title: '膳食纤维 (g / 100g)',
              subtitle: '增强饱腹感、促进肠道蠕动与延缓餐后血糖峰值',
              valA: '${_itemA.dietaryFiber} g',
              valB: '${_itemB.dietaryFiber} g',
              colorA: colorA,
              colorB: colorB,
              aWins: _itemA.dietaryFiber > _itemB.dietaryFiber,
              bWins: _itemB.dietaryFiber > _itemA.dietaryFiber,
              winNote: _itemA.dietaryFiber > _itemB.dietaryFiber
                  ? '${_itemA.name} 纤维更丰富，饱腹与通便更强'
                  : (_itemB.dietaryFiber > _itemA.dietaryFiber
                      ? '${_itemB.name} 纤维更丰富，饱腹与通便更强'
                      : '两者纤维含量接近'),
            ),
            const SizedBox(height: 10),

            _buildMetricComparisonCard(
              title: '维生素 C (mg / 100g)',
              subtitle: '抗氧化清除自由基、促进铁吸收与免疫力',
              valA: '${_itemA.vitaminC} mg',
              valB: '${_itemB.vitaminC} mg',
              colorA: colorA,
              colorB: colorB,
              aWins: _itemA.vitaminC > _itemB.vitaminC,
              bWins: _itemB.vitaminC > _itemA.vitaminC,
              winNote: _itemA.vitaminC > _itemB.vitaminC
                  ? '${_itemA.name} 维C大幅领先，抗氧化能力更强'
                  : (_itemB.vitaminC > _itemA.vitaminC
                      ? '${_itemB.name} 维C大幅领先，抗氧化能力更强'
                      : '两者维C含量接近'),
            ),
            const SizedBox(height: 10),

            _buildMetricComparisonCard(
              title: '钾含量 (mg / 100g)',
              subtitle: '排钠降压平衡电解质；肾病/保钾降压药人群须控量',
              valA: '${_itemA.potassium} mg',
              valB: '${_itemB.potassium} mg',
              colorA: colorA,
              colorB: colorB,
              aWins: _itemA.potassium > _itemB.potassium,
              bWins: _itemB.potassium > _itemA.potassium,
              winNote: _itemA.potassium > _itemB.potassium
                  ? '${_itemA.name} 钾含量更高，高血压排钠优选'
                  : (_itemB.potassium > _itemA.potassium
                      ? '${_itemB.name} 钾含量更高，高血压排钠优选'
                      : '两者钾含量接近'),
            ),
            const SizedBox(height: 16),

            // Summary Advice Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates_outlined,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '选购与食用建议',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('• 【${_itemA.name}】：${_itemA.dietTip}',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                  const SizedBox(height: 4),
                  Text('• 【${_itemB.name}】：${_itemB.dietTip}',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegendIndicator(String name, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildFoodSelector({
    required String label,
    required FoodNutritionProfile current,
    required Color themeColor,
    required ValueChanged<FoodNutritionProfile> onSelected,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPicker(current, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: themeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: themeColor.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: themeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    current.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openPicker(
    FoodNutritionProfile current,
    ValueChanged<FoodNutritionProfile> onSelected,
  ) {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? _allProfiles
                : _allProfiles.where((p) => p.name.toLowerCase().contains(query)).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollCtrl) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: '搜索果蔬名称（如：西瓜、苹果、菠菜）',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final p = filtered[i];
                          final isCurrent = p.name == current.name;
                          return ListTile(
                            title: Text(p.name,
                                style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text('热量：${p.calories}kcal | 纤维：${p.dietaryFiber}g | GI：${p.gi}'),
                            trailing: isCurrent ? const Icon(Icons.check, color: Colors.teal) : null,
                            onTap: () {
                              onSelected(p);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMetricComparisonCard({
    required String title,
    required String subtitle,
    required String valA,
    required String valB,
    required Color colorA,
    required Color colorB,
    required bool aWins,
    required bool bWins,
    required String winNote,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(subtitle,
                          style: TextStyle(color: colorScheme.outline, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorA.withValues(alpha: aWins ? 0.2 : 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: aWins ? colorA : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_itemA.name,
                                style: TextStyle(fontSize: 10, color: colorA, fontWeight: FontWeight.bold)),
                            if (aWins) ...[
                              const Spacer(),
                              const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            ],
                          ],
                        ),
                        Text(valA, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorB.withValues(alpha: bWins ? 0.2 : 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: bWins ? colorB : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_itemB.name,
                                style: TextStyle(fontSize: 10, color: colorB, fontWeight: FontWeight.bold)),
                            if (bWins) ...[
                              const Spacer(),
                              const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            ],
                          ],
                        ),
                        Text(valB, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '💡 $winNote',
              style: TextStyle(
                fontSize: 11,
                color: (aWins || bWins) ? colorScheme.primary : colorScheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionRadarPainter extends CustomPainter {
  _NutritionRadarPainter({
    required this.profileA,
    required this.profileB,
    required this.colorA,
    required this.colorB,
    required this.textColor,
    required this.outlineColor,
  });

  final FoodNutritionProfile profileA;
  final FoodNutritionProfile profileB;
  final Color colorA;
  final Color colorB;
  final Color textColor;
  final Color outlineColor;

  static const List<String> axisLabels = [
    '低热量优势',
    '膳食纤维',
    '维生素C',
    '钾元素',
    '低GI控糖度',
  ];

  List<double> _normalize(FoodNutritionProfile p) {
    final calScore = (1.0 - (p.calories / 110.0)).clamp(0.15, 1.0);
    final fiberScore = (p.dietaryFiber / 3.0).clamp(0.15, 1.0);
    final vcScore = (p.vitaminC / 60.0).clamp(0.15, 1.0);
    final potScore = (p.potassium / 350.0).clamp(0.15, 1.0);
    final giScore = (1.0 - (p.gi / 80.0)).clamp(0.15, 1.0);

    return [calScore, fiberScore, vcScore, potScore, giScore];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;

    final gridPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int step = 1; step <= 3; step++) {
      final r = radius * (step / 3.0);
      final path = Path();
      for (int i = 0; i < 5; i++) {
        final angle = (i * 2 * math.pi / 5) - (math.pi / 2);
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * math.pi / 5) - (math.pi / 2);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      canvas.drawLine(center, Offset(x, y), gridPaint);

      final lx = center.dx + (radius + 20) * math.cos(angle);
      final ly = center.dy + (radius + 16) * math.sin(angle);
      textPainter.text = TextSpan(
        text: axisLabels[i],
        style: TextStyle(
          color: textColor.withValues(alpha: 0.8),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(lx - textPainter.width / 2, ly - textPainter.height / 2),
      );
    }

    _drawDataPolygon(canvas, center, radius, _normalize(profileA), colorA);
    _drawDataPolygon(canvas, center, radius, _normalize(profileB), colorB);
  }

  void _drawDataPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    List<double> scores,
    Color color,
  ) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * math.pi / 5) - (math.pi / 2);
      final r = radius * scores[i];
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * math.pi / 5) - (math.pi / 2);
      final r = radius * scores[i];
      canvas.drawCircle(
        Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle)),
        3.5,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NutritionRadarPainter oldDelegate) {
    return oldDelegate.profileA != profileA || oldDelegate.profileB != profileB;
  }
}
