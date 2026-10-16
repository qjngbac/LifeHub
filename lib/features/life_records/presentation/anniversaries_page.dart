import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/lunar_date_helper.dart';
import 'package:lifehub/features/life_records/presentation/life_record_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnniversariesPage extends ConsumerStatefulWidget {
  const AnniversariesPage({super.key});

  @override
  ConsumerState<AnniversariesPage> createState() => _AnniversariesPageState();
}

class _AnniversariesPageState extends ConsumerState<AnniversariesPage> {
  static const String _pinnedPrefKey = 'pinned_anniversary_id';

  int revision = 0;
  String? _pinnedId;
  bool _pinnedLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPinnedId();
  }

  Future<void> _loadPinnedId() async {
    final prefs = ref.read(sharedPreferencesProvider) ??
        await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pinnedId = prefs.getString(_pinnedPrefKey);
        _pinnedLoaded = true;
      });
    }
  }

  Future<void> _togglePin(String id) async {
    final prefs = ref.read(sharedPreferencesProvider) ??
        await SharedPreferences.getInstance();
    final newId = _pinnedId == id ? null : id;
    if (newId == null) {
      await prefs.remove(_pinnedPrefKey);
    } else {
      await prefs.setString(_pinnedPrefKey, newId);
    }
    if (mounted) {
      setState(() {
        _pinnedId = newId;
        revision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = AnniversaryRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('纪念日与倒数日'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repository, null),
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
      body: FutureBuilder<List<AnniversaryEntry>>(
        key: ValueKey(revision),
        future: repository.listAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData || !_pinnedLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawList = snapshot.data!;
          if (rawList.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.celebration_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      '记录生日、考研、纪念日和重要节点',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '支持未来目标倒数与珍贵回忆累计',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _edit(repository, null),
                      icon: const Icon(Icons.add),
                      label: const Text('添加第一个纪念日'),
                    ),
                  ],
                ),
              ),
            );
          }

          final now = DateTime.now();

          // 排序逻辑：
          // 1. 未来倒数（days >= 0）按天数从小到大（最近的在前）
          // 2. 过去累计（days < 0）按天数从小到大（最近刚过的在前）
          final countdowns = rawList
              .where((item) => repository.daysUntil(item, now) >= 0)
              .toList()
            ..sort((a, b) => repository
                .daysUntil(a, now)
                .compareTo(repository.daysUntil(b, now)));

          final countups = rawList
              .where((item) => repository.daysUntil(item, now) < 0)
              .toList()
            ..sort((a, b) => repository
                .daysUntil(b, now)
                .compareTo(repository.daysUntil(a, now)));

          final sortedList = [...countdowns, ...countups];

          // 寻找 Hero 推荐展示项：
          // 优先手动置顶项；若无置顶项，展示最近的倒数项；若无倒数项，展示最近的累计项
          AnniversaryEntry? heroItem;
          if (_pinnedId != null) {
            heroItem = rawList.where((it) => it.id == _pinnedId).firstOrNull;
          }
          heroItem ??= countdowns.isNotEmpty
              ? countdowns.first
              : (countups.isNotEmpty ? countups.first : rawList.first);

          final heroDays = repository.daysUntil(heroItem, now);
          final isHeroPinned = heroItem.id == _pinnedId;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
            children: [
              _HeroBannerCard(
                item: heroItem,
                days: heroDays,
                isPinned: isHeroPinned,
                onTap: () => _edit(repository, heroItem),
                onTogglePin: () => _togglePin(heroItem!.id),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '全部事项 (${sortedList.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '轻触编辑 · 长按设为置顶',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...sortedList.map((entry) {
                final days = repository.daysUntil(entry, now);
                final isPinned = entry.id == _pinnedId;
                return _AnniversaryListCard(
                  key: ValueKey(entry.id),
                  entry: entry,
                  days: days,
                  isPinned: isPinned,
                  onTap: () => _edit(repository, entry),
                  onLongPress: () => _showActionsSheet(repository, entry, isPinned),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _showActionsSheet(
    AnniversaryRepository repository,
    AnniversaryEntry entry,
    bool isPinned,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: isPinned ? null : Theme.of(context).colorScheme.primary,
              ),
              title: Text(isPinned ? '取消置顶看板' : '设为顶部看板置顶'),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _togglePin(entry.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改事件'),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _edit(repository, entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除事件', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _delete(repository, entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    AnniversaryRepository repository,
    AnniversaryEntry? current,
  ) async {
    final draft = await showAnniversaryDialog(context, current: current);
    if (draft == null) return;
    if (current == null) {
      await repository.create(draft);
    } else {
      await repository.update(current.id, draft);
    }
    if (mounted) setState(() => revision++);
  }

  Future<void> _delete(
    AnniversaryRepository repository,
    AnniversaryEntry value,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('删除“${value.title}”？'),
            content: const Text('删除后该倒数日/纪念日记录将不再显示。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (_pinnedId == value.id) {
      await _togglePin(value.id);
    }
    await repository.delete(value.id);
    if (mounted) setState(() => revision++);
  }
}

/// 顶部焦点 Hero 大看板
class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({
    required this.item,
    required this.days,
    required this.isPinned,
    required this.onTap,
    required this.onTogglePin,
  });

  final AnniversaryEntry item;
  final int days;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetDate = DateKeys.fromLocalDateKey(item.date);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[targetDate.weekday - 1];

    final isFuture = days > 0;
    final isToday = days == 0;
    final displayDays = days >= 0 ? days : -days;

    final categoryMeta = _resolveCategory(item);
    final lunarInfo = LunarInfo.fromMetadata(item.metadata);

    // 渐变色彩定义：根据事项分类动态呈现丰富色系；当天则使用庆典金色
    final gradientColors = isToday
        ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
        : categoryMeta.gradient;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPinned
                                      ? Icons.push_pin
                                      : isToday
                                          ? Icons.celebration
                                          : isFuture
                                              ? Icons.timelapse
                                              : Icons.favorite,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isPinned
                                      ? '置顶看板'
                                      : isToday
                                          ? '今日到来'
                                          : isFuture
                                              ? '焦点倒数'
                                              : '珍贵累计',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              categoryMeta.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (lunarInfo.isLunar) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '🌙 农历',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.title} ${isToday ? "就在今天 🎉" : isFuture ? "还有" : "已经"}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lunarInfo.isLunar
                            ? '${lunarInfo.fullLunarString}\n对应公历 ${targetDate.year}年${targetDate.month}月${targetDate.day}日 星期$weekday${item.repeatYearly ? ' · 每年重复' : ''}'
                            : '${targetDate.year}年${targetDate.month}月${targetDate.day}日 星期$weekday${item.repeatYearly ? ' · 每年' : ''}\n农历 ${LunarDateHelper.getLunarSummary(targetDate)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // 右侧大数字色块核心区
                Container(
                  constraints: const BoxConstraints(minWidth: 84),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isToday ? '今天' : '$displayDays',
                        style: TextStyle(
                          fontSize: isToday ? 26 : 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.05,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isToday
                            ? '🎉 TODAY'
                            : isFuture
                                ? 'DAYS 天后'
                                : 'DAYS 已过',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表卡片：包含左侧优雅分类图标 + 完整信息，右侧现代双格大数字色块
class _AnniversaryListCard extends StatelessWidget {
  const _AnniversaryListCard({
    super.key,
    required this.entry,
    required this.days,
    required this.isPinned,
    required this.onTap,
    required this.onLongPress,
  });

  final AnniversaryEntry entry;
  final int days;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetDate = DateKeys.fromLocalDateKey(entry.date);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[targetDate.weekday - 1];

    final isFuture = days > 0;
    final isToday = days == 0;
    final displayDays = days >= 0 ? days : -days;

    final categoryMeta = _resolveCategory(entry);
    final lunarInfo = LunarInfo.fromMetadata(entry.metadata);

    // 右侧大数字色块配置：根据事项分类呈现专属高辨识度色彩，当天使用庆典金
    final blockColor = isToday
        ? const Color(0xFFD97706)
        : categoryMeta.blockColor;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 左侧：分类图标圆徽章
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: categoryMeta.badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  categoryMeta.icon,
                  size: 24,
                  color: categoryMeta.iconColor,
                ),
              ),
              const SizedBox(width: 12),
              // 中间：标题与完整日期（无单字折行风险）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPinned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.push_pin,
                              size: 11,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                        if (lunarInfo.isLunar) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '农历',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isToday
                                ? const Color(0xFFFEF3C7)
                                : categoryMeta.tagBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isToday
                                ? '今天'
                                : isFuture
                                    ? '还有'
                                    : '已经',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isToday
                                  ? const Color(0xFFB45309)
                                  : categoryMeta.tagTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lunarInfo.isLunar
                          ? '${lunarInfo.fullLunarString} · ${entry.repeatYearly ? '每年重复' : '单次'}'
                          : '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} $weekday · ${entry.repeatYearly ? '每年重复' : '单次'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lunarInfo.isLunar
                          ? '公历 ${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')} $weekday'
                          : '农历 ${LunarDateHelper.getLunarSummary(targetDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 右侧：经典双格大数字色块 (Number Block)
              Container(
                width: 90,
                height: 48,
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: blockColor.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 左格：大数字
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: Text(
                          isToday ? '今天' : '$displayDays',
                          style: TextStyle(
                            fontSize: isToday
                                ? 16
                                : displayDays >= 10000
                                    ? 14
                                    : displayDays >= 1000
                                        ? 16
                                        : 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    // 中间细分割线
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    // 右格：单位
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: Text(
                          isToday ? '🎉' : '天',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryMeta {
  const _CategoryMeta({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.badgeBg,
    required this.blockColor,
    required this.tagBg,
    required this.tagTextColor,
    required this.gradient,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final Color badgeBg;
  final Color blockColor;
  final Color tagBg;
  final Color tagTextColor;
  final List<Color> gradient;
}

_CategoryMeta _resolveCategory(AnniversaryEntry entry) {
  final cat = entry.category.toUpperCase().trim();
  final title = entry.title;

  // 1. 恋爱与浪漫纪念
  if (entry.relationshipId != null ||
      cat == 'RELATIONSHIP' ||
      title.contains('恋') ||
      title.contains('爱') ||
      title.contains('相识') ||
      title.contains('结婚') ||
      title.contains('牵手') ||
      title.contains('告白') ||
      title.contains('表白') ||
      title.contains('求婚') ||
      title.contains('约会') ||
      title.contains('情侣') ||
      title.contains('纪念')) {
    return const _CategoryMeta(
      label: '恋爱',
      icon: Icons.favorite_rounded,
      iconColor: Color(0xFFE11D48),
      badgeBg: Color(0xFFFFE4E6),
      blockColor: Color(0xFFE11D48),
      tagBg: Color(0xFFFFE4E6),
      tagTextColor: Color(0xFFBE123C),
      gradient: [Color(0xFFF43F5E), Color(0xFFE11D48)],
    );
  }

  // 2. 生日与诞辰
  if (cat == 'BIRTHDAY' ||
      title.contains('生日') ||
      title.contains('诞') ||
      title.contains('岁')) {
    return const _CategoryMeta(
      label: '生日',
      icon: Icons.cake_rounded,
      iconColor: Color(0xFFD97706),
      badgeBg: Color(0xFFFEF3C7),
      blockColor: Color(0xFFD97706),
      tagBg: Color(0xFFFEF3C7),
      tagTextColor: Color(0xFFB45309),
      gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
    );
  }

  // 3. 答辩、毕业与重要学术节点（华丽尊贵紫）
  if (title.contains('答辩') ||
      title.contains('毕业') ||
      title.contains('论文') ||
      title.contains('学位') ||
      title.contains('开学') ||
      title.contains('结业')) {
    return const _CategoryMeta(
      label: '答辩',
      icon: Icons.school_rounded,
      iconColor: Color(0xFF7C3AED),
      badgeBg: Color(0xFFF3E8FF),
      blockColor: Color(0xFF7C3AED),
      tagBg: Color(0xFFF3E8FF),
      tagTextColor: Color(0xFF6D28D9),
      gradient: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    );
  }

  // 4. 考试与学业研考（睿智深邃靛蓝）
  if (cat == 'EXAM' ||
      title.contains('考') ||
      title.contains('研') ||
      title.contains('试') ||
      title.contains('毕') ||
      title.contains('学') ||
      title.contains('雅思') ||
      title.contains('托福') ||
      title.contains('软考')) {
    return const _CategoryMeta(
      label: '学业',
      icon: Icons.auto_stories_rounded,
      iconColor: Color(0xFF4F46E5),
      badgeBg: Color(0xFFEEF2FF),
      blockColor: Color(0xFF4F46E5),
      tagBg: Color(0xFFEEF2FF),
      tagTextColor: Color(0xFF4338CA),
      gradient: [Color(0xFF6366F1), Color(0xFF4338CA)],
    );
  }

  // 5. 工作与事业（现代商务天蓝）
  if (cat == 'WORK' ||
      title.contains('工') ||
      title.contains('入职') ||
      title.contains('项目') ||
      title.contains('发布') ||
      title.contains('转正') ||
      title.contains('成立') ||
      title.contains('上线') ||
      title.contains('述职') ||
      title.contains('晋升') ||
      title.contains('面试')) {
    return const _CategoryMeta(
      label: '工作',
      icon: Icons.work_rounded,
      iconColor: Color(0xFF0284C7),
      badgeBg: Color(0xFFE0F2FE),
      blockColor: Color(0xFF0284C7),
      tagBg: Color(0xFFE0F2FE),
      tagTextColor: Color(0xFF0369A1),
      gradient: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
    );
  }

  // 6. 旅行与探索出游（清新松石青）
  if (cat == 'TRAVEL' ||
      title.contains('旅') ||
      title.contains('游') ||
      title.contains('度假') ||
      title.contains('出游') ||
      title.contains('机票') ||
      title.contains('自驾') ||
      title.contains('露营')) {
    return const _CategoryMeta(
      label: '旅行',
      icon: Icons.flight_takeoff_rounded,
      iconColor: Color(0xFF0D9488),
      badgeBg: Color(0xFFCCFBF1),
      blockColor: Color(0xFF0D9488),
      tagBg: Color(0xFFCCFBF1),
      tagTextColor: Color(0xFF0F766E),
      gradient: [Color(0xFF14B8A6), Color(0xFF0D9488)],
    );
  }

  // 7. 节庆与假日（热烈庆典落日橙）
  if (cat == 'HOLIDAY' ||
      title.contains('节') ||
      title.contains('假') ||
      title.contains('年') ||
      title.contains('春') ||
      title.contains('中秋') ||
      title.contains('国庆') ||
      title.contains('元旦') ||
      title.contains('除夕')) {
    return const _CategoryMeta(
      label: '节庆',
      icon: Icons.celebration_rounded,
      iconColor: Color(0xFFEA580C),
      badgeBg: Color(0xFFFFEDD5),
      blockColor: Color(0xFFEA580C),
      tagBg: Color(0xFFFFEDD5),
      tagTextColor: Color(0xFFC2410C),
      gradient: [Color(0xFFF97316), Color(0xFFEA580C)],
    );
  }

  // 8. 默认生活日常（自然翡翠绿）
  return const _CategoryMeta(
    label: '生活',
    icon: Icons.event_note_rounded,
    iconColor: Color(0xFF059669),
    badgeBg: Color(0xFFD1FAE5),
    blockColor: Color(0xFF059669),
    tagBg: Color(0xFFD1FAE5),
    tagTextColor: Color(0xFF047857),
    gradient: [Color(0xFF10B981), Color(0xFF059669)],
  );
}
