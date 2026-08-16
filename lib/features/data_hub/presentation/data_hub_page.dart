import 'package:flutter/material.dart';
import 'package:lifehub/features/archive/presentation/archive_page.dart';
import 'package:lifehub/features/course/presentation/courses_page.dart';
import 'package:lifehub/features/credentials/presentation/credentials_page.dart';
import 'package:lifehub/features/data_hub/application/data_hub_preferences.dart';
import 'package:lifehub/features/data_hub/application/module_usage_tracker.dart';
import 'package:lifehub/features/entertainment/presentation/entertainment_page.dart';
import 'package:lifehub/features/evening/presentation/evening_plan_page.dart';
import 'package:lifehub/features/finance/presentation/finance_page.dart';
import 'package:lifehub/features/first_aid/presentation/first_aid_page.dart';
import 'package:lifehub/features/focus/presentation/focus_page.dart';
import 'package:lifehub/features/goal/presentation/goals_page.dart';
import 'package:lifehub/features/habit/presentation/habits_page.dart';
import 'package:lifehub/features/household/presentation/household_page.dart';
import 'package:lifehub/features/inbox/presentation/inbox_page.dart';
import 'package:lifehub/features/knowledge/presentation/offline_knowledge_pages.dart';
import 'package:lifehub/features/library/presentation/library_page.dart';
import 'package:lifehub/features/life_records/presentation/anniversaries_page.dart';
import 'package:lifehub/features/life_records/presentation/mood_calendar_page.dart';
import 'package:lifehub/features/life_records/presentation/relationship_space_page.dart';
import 'package:lifehub/features/list/presentation/lists_page.dart';
import 'package:lifehub/features/location/presentation/locations_page.dart';
import 'package:lifehub/features/medication/presentation/medication_page.dart';
import 'package:lifehub/features/media/presentation/media_home_page.dart';
import 'package:lifehub/features/parcel/presentation/parcels_page.dart';
import 'package:lifehub/features/reading/presentation/reading_page.dart';
import 'package:lifehub/features/project/presentation/projects_page.dart';
import 'package:lifehub/features/relations/presentation/relation_center_page.dart';
import 'package:lifehub/features/review/presentation/reviews_page.dart';
import 'package:lifehub/features/search/presentation/search_page.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/features/trip/presentation/trips_page.dart';
import 'package:lifehub/features/weather/presentation/weather_locations_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DataHubPage extends StatefulWidget {
  const DataHubPage({super.key});
  @override
  State<DataHubPage> createState() => _DataHubPageState();
}

class _DataHubPageState extends State<DataHubPage> {
  DataHubLayout layout =
      DataHubLayout(order: _modules.map((value) => value.id).toList());
  Set<String> lowFrequencySuggestions = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<DataHubPreferences> _store() async =>
      DataHubPreferences(await SharedPreferences.getInstance());

  Future<void> _load() async {
    final store = await _store();
    final value =
        store.loadLayout(_modules.map((module) => module.id).toList());
    final tracker = ModuleUsageTracker(await SharedPreferences.getInstance());
    final ids = _modules.map((module) => module.id).toList();
    await tracker.observeModules(ids);
    final suggestions = tracker.lowFrequencySuggestions(
      ids,
      pinned: value.pinned,
    );
    if (mounted) {
      setState(() {
        layout = value;
        lowFrequencySuggestions = suggestions;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = [for (final id in layout.visibleOrder) _byId(id)];
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据'),
        actions: [
          IconButton(
              tooltip: '管理模块',
              icon: const Icon(Icons.tune),
              onPressed: _manage),
          IconButton(
              tooltip: '全局搜索',
              icon: const Icon(Icons.search),
              onPressed: () => _open(context, const SearchPage())),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFAF7FF), Color(0xFFF2F7FF)])),
        child: modules.isEmpty
            ? Center(
                child: FilledButton.icon(
                    onPressed: _manage,
                    icon: const Icon(Icons.tune),
                    label: const Text('恢复或显示模块')))
            : LayoutBuilder(builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
                // Two columns remain useful on phones, but accessibility text
                // wraps module subtitles aggressively. Grow rows instead of
                // clipping labels or silently switching the user's layout.
                final cardHeight = (164 + ((textScale - 1) * 110)).toDouble();
                return GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: cardHeight,
                  ),
                  itemCount: modules.length,
                  itemBuilder: (context, index) => _HubCard(
                    module: modules[index],
                    pinned: layout.pinned.contains(modules[index].id),
                    onTap: () => _openModule(modules[index]),
                  ),
                );
              }),
      ),
    );
  }

  Future<void> _manage() async {
    var draft = layout;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
                  child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .82,
                child: Column(children: [
                  ListTile(
                      title: const Text('管理数据模块'),
                      subtitle: const Text('固定模块优先显示；隐藏后数据不会删除'),
                      trailing: TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('完成'))),
                  Expanded(
                      child: ReorderableListView.builder(
                    itemCount: draft.order.length,
                    onReorderItem: (oldIndex, newIndex) => setSheetState(() {
                      final order = [...draft.order];
                      final id = order.removeAt(oldIndex);
                      order.insert(newIndex, id);
                      draft = draft.copyWith(order: order);
                    }),
                    itemBuilder: (context, index) {
                      final module = _byId(draft.order[index]);
                      final hidden = draft.hidden.contains(module.id);
                      final pinned = draft.pinned.contains(module.id);
                      final suggested =
                          lowFrequencySuggestions.contains(module.id);
                      return ListTile(
                        key: ValueKey(module.id),
                        leading: Icon(module.icon),
                        title: Text(module.title),
                        subtitle: Text(
                            hidden
                                ? '已隐藏'
                                : pinned
                                    ? '已固定'
                                    : suggested
                                        ? '低频，可考虑隐藏'
                                        : module.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: pinned ? '取消固定' : '固定',
                              icon: Icon(pinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined),
                              onPressed: hidden
                                  ? null
                                  : () => setSheetState(() {
                                        final values = {...draft.pinned};
                                        pinned
                                            ? values.remove(module.id)
                                            : values.add(module.id);
                                        draft = draft.copyWith(pinned: values);
                                      })),
                          IconButton(
                              tooltip: hidden ? '显示' : '隐藏',
                              icon: Icon(hidden
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setSheetState(() {
                                    final values = {...draft.hidden};
                                    if (hidden) {
                                      values.remove(module.id);
                                    } else if (draft.order
                                            .where((id) => !values.contains(id))
                                            .length >
                                        1) {
                                      values.add(module.id);
                                    }
                                    draft = draft.copyWith(hidden: values);
                                  })),
                          const Icon(Icons.drag_handle),
                        ]),
                      );
                    },
                  )),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                            onPressed: () async {
                              final preferences =
                                  await SharedPreferences.getInstance();
                              await DataHubPreferences(preferences).reset();
                              await ModuleUsageTracker(preferences).reset();
                              setSheetState(() {
                                draft = DataHubLayout(
                                  order: _modules.map((v) => v.id).toList(),
                                );
                                lowFrequencySuggestions = const {};
                              });
                            },
                            icon: const Icon(Icons.restore),
                            label: const Text('恢复默认')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消')),
                      ]),
                ]),
              ))),
    );
    if (saved != true) return;
    await (await _store()).saveLayout(draft);
    if (mounted) setState(() => layout = draft);
  }

  Future<void> _openModule(_HubModule module) async {
    final preferences = await SharedPreferences.getInstance();
    await ModuleUsageTracker(preferences).recordOpen(module.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => module.page),
    );
  }
}

void _open(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
_HubModule _byId(String id) => _modules.firstWhere((value) => value.id == id);

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.module,
    required this.pinned,
    required this.onTap,
  });
  final _HubModule module;
  final bool pinned;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                          backgroundColor: module.accent,
                          foregroundColor: const Color(0xFF514675),
                          child: Icon(module.icon)),
                      const Spacer(),
                      if (pinned) const Icon(Icons.push_pin, size: 18)
                    ]),
                    const Spacer(),
                    Text(module.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(module.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]))));
}

class _HubModule {
  const _HubModule(
      this.id, this.icon, this.accent, this.title, this.subtitle, this.page);
  final String id;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final Widget page;
}

const _modules = <_HubModule>[
  _HubModule('evening', Icons.nightlight_outlined, Color(0xFFE5D9FF), '晚间规划',
      '集中查看明日任务、日程、课程、天气与准备项', EveningPlanPage()),
  _HubModule('relations', Icons.hub_outlined, Color(0xFFD8EAF8), '关联中心',
      '查看任务、目标、项目、旅行、地点与资料的联系', RelationCenterPage()),
  _HubModule('weather', Icons.cloud_outlined, Color(0xFFD9ECFF), '天气地区',
      '一个默认地区与多个常用地区', WeatherLocationsPage()),
  _HubModule('household', Icons.inventory_2_outlined, Color(0xFFFFE5D5), '家庭物品',
      '购买记录、保修截止和附件', HouseholdPage()),
  _HubModule('medication', Icons.medication_outlined, Color(0xFFD9F0E7), '用药提醒',
      '只做用户记录、提醒与本地急救卡', MedicationPage()),
  _HubModule('finance', Icons.receipt_long_outlined, Color(0xFFFFE8C8), '轻量收支',
      '快速记录收入、支出与月度分类', FinancePage()),
  _HubModule('credentials', Icons.badge_outlined, Color(0xFFE8DFFF), '证件到期',
      '保存号码提示与到期提醒', CredentialsPage()),
  _HubModule('first_aid', Icons.medical_services_outlined, Color(0xFFF2D7E1),
      '急救知识', '按区域查找离线急救与野外求生步骤', FirstAidPage()),
  _HubModule('consumer_guide', Icons.shopping_basket_outlined,
      Color(0xFFFFE6D5), '日用品选购', '431 种常见用品的离线选购重点', ConsumerGuidePage()),
  _HubModule('drug_info', Icons.medication_liquid_outlined, Color(0xFFD9F0E7),
      '药品信息', '728 种药品通用名与安全提醒', DrugInfoPage()),
  _HubModule('entertainment', Icons.auto_stories_outlined, Color(0xFFE3DFFF),
      '笑话与故事', '随机浏览、收藏、屏蔽与睡前阅读', EntertainmentPage()),
  _HubModule('media', Icons.movie_filter_outlined, Color(0xFFDCE7FF), '影视进度',
      '记录看到哪里、下一集与下一部', MediaHomePage()),
  _HubModule('reading', Icons.menu_book_outlined, Color(0xFFE2EBD8), '阅读进度',
      '记录图书、小说、漫画和论文看到哪里', ReadingPage()),
  _HubModule('parcels', Icons.local_shipping_outlined, Color(0xFFFFE1CC),
      '快递取件', '集中查看运输中和待领取的快递', ParcelsPage()),
  _HubModule('inbox', Icons.inbox_outlined, Color(0xFFE7DFFF), '收件箱',
      '收集分享、速记并稍后转为行动', InboxPage()),
  _HubModule('library', Icons.bookmarks_outlined, Color(0xFFFFE2D3), '资料库',
      '便签、图片与文件附件', LibraryPage()),
  _HubModule('tasks', Icons.check_circle_outline, Color(0xFFDCD3FF), '任务',
      '管理所有待办与完成状态', TasksPage()),
  _HubModule('projects', Icons.folder_outlined, Color(0xFFD8E5FF), '项目',
      '把任务组织成长期项目', ProjectsPage()),
  _HubModule('lists', Icons.checklist, Color(0xFFD9F0E7), '清单', '购物、旅行装备和检查清单',
      ListsPage()),
  _HubModule('habits', Icons.repeat, Color(0xFFFFE6C9), '习惯', '每日打卡与周期目标',
      HabitsPage()),
  _HubModule('courses', Icons.school_outlined, Color(0xFFD8E8FA), '课程表',
      '学期、课程和每周时间', CoursesPage()),
  _HubModule('goals', Icons.flag_outlined, Color(0xFFE6DBFF), '目标',
      '长期方向、里程碑和关联进度', GoalsPage()),
  _HubModule('focus', Icons.timer_outlined, Color(0xFFD5F0EE), '专注与计时',
      '倒计时专注或正向记录实际投入', FocusPage()),
  _HubModule('reviews', Icons.insights_outlined, Color(0xFFFFE5D6), '复盘',
      '查看周月事实并整理下一步', ReviewsPage()),
  _HubModule('locations', Icons.place_outlined, Color(0xFFD7F0E7), '地点',
      '手动保存位置，无需后台定位', LocationsPage()),
  _HubModule('trips', Icons.luggage_outlined, Color(0xFFFFE0E8), '旅行',
      '聚合计划、行程、地点与花费', TripsPage()),
  _HubModule('moods', Icons.emoji_emotions_outlined, Color(0xFFFFE3B8), '心情日历',
      '用表情记录每天的感受', MoodCalendarPage()),
  _HubModule('relationship', Icons.favorite_outline, Color(0xFFFFDCE9), '关系空间',
      '共同心情、事件和生理期记录', RelationshipSpacePage()),
  _HubModule('anniversaries', Icons.celebration_outlined, Color(0xFFFFEDBF),
      '纪念日', '生日、周年与重要日期倒数', AnniversariesPage()),
  _HubModule('archive', Icons.archive_outlined, Color(0xFFE2DEE9), '归档',
      '查找、恢复或删除归档内容', ArchivePage()),
];
