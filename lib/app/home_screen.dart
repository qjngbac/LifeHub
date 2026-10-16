import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/presentation/bill_import_preview_page.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  DateTime? _lastBackPressTime;

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
    // 1. Check if value is a local file path
    final maybeFile = File(value);
    if (await maybeFile.exists()) {
      final fileName = maybeFile.uri.pathSegments.isNotEmpty
          ? maybeFile.uri.pathSegments.last
          : maybeFile.path;
      try {
        final bytes = await maybeFile.readAsBytes();
        final billItems = BillCsvParser.parseBytes(bytes, fileName: fileName);
        if (billItems.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('检测到账单文件（共 ${billItems.length} 笔流水）'),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: '立即导入',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BillImportPreviewPage(rawItems: billItems),
                    ),
                  );
                },
              ),
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('Bill parse error: $e');
      }
    }

    // 2. Check if raw text is a bill
    final isBill =
        BillCsvParser.detectSourceType(value) != BillSourceType.unknown;
    if (isBill) {
      final items = BillCsvParser.parse(value);
      if (items.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检测到账单数据（共 ${items.length} 笔）'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: '立即导入',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BillImportPreviewPage(rawItems: items),
                  ),
                );
              },
            ),
          ),
        );
        return;
      }
    }

    // 3. Otherwise capture to inbox
    await InboxRepository(ref.read(databaseProvider)).capture(
      value,
      sourceType: 'ANDROID_SHARE',
    );
    ref.read(refreshProvider.notifier).state++;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存到 LifeHub 灵感库')),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final bg = isDark
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primaryContainer;
            final fg = isDark
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onPrimaryContainer;
            final border = theme.colorScheme.primary.withValues(alpha: 0.25);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.door_back_door_outlined,
                      size: 16,
                      color: fg.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '再按一次退出 LifeHub',
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                width: 220,
                shape: StadiumBorder(
                  side: BorderSide(color: border, width: 1),
                ),
                backgroundColor: bg,
                elevation: 4,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            );
            return;
          }
          SystemNavigator.pop();
        },
        child: Scaffold(
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
        ),
      );
}
