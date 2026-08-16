import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/calendar/presentation/calendar_page.dart';
import 'package:lifehub/core/platform/course_shortcut_service.dart';
import 'package:lifehub/core/platform/share_capture_service.dart';
import 'package:lifehub/features/course/presentation/courses_page.dart';
import 'package:lifehub/features/data_hub/presentation/data_hub_page.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/settings/presentation/my_page.dart';
import 'package:lifehub/features/today/presentation/today_page.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    CourseShortcutService.setDestinationHandler(_openDestination);
    ShareCaptureService.setHandler(_captureShare);
    CourseShortcutService.consumeInitialDestination().then((destination) {
      if (destination != null) _openDestination(destination);
    });
    ShareCaptureService.consumeInitial().then((value) {
      if (value != null) _captureShare(value);
    });
  }

  @override
  void dispose() {
    CourseShortcutService.setDestinationHandler(null);
    ShareCaptureService.setHandler(null);
    super.dispose();
  }

  static const _pages = <Widget>[
    TodayPage(),
    CalendarPage(),
    DataHubPage(),
    MyPage(),
  ];

  int get _pageIndex =>
      _selectedIndex < 2 ? _selectedIndex : _selectedIndex - 1;

  void _openDestination(String destination) {
    if (destination != 'courses' || !mounted) return;
    setState(() => _selectedIndex = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CoursesPage()),
      );
    });
  }

  Future<void> _captureShare(String value) async {
    await InboxRepository(ref.read(databaseProvider)).capture(
      value,
      sourceType: 'ANDROID_SHARE',
    );
    ref.read(refreshProvider.notifier).state++;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存到 LifeHub 收件箱')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _pageIndex, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) async {
            if (index == 2) {
              await showQuickCreateSheet(context, ref);
              return;
            }
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: '今天',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '日程',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle, size: 32),
              label: '＋',
            ),
            NavigationDestination(
              icon: Icon(Icons.storage_outlined),
              selectedIcon: Icon(Icons.storage),
              label: '数据',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      );
}
