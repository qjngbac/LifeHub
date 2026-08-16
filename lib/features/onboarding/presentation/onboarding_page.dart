import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.onFinished, super.key});

  final Future<void> Function() onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final controller = PageController();
  var page = 0;
  var finishing = false;

  static const pages = <_OnboardingItem>[
    _OnboardingItem(
      icon: Icons.today_outlined,
      title: '先从今天开始',
      body: '首页集中显示今天的任务、日程和习惯。完成任务请点勾选框，点击卡片可以继续编辑。',
    ),
    _OnboardingItem(
      icon: Icons.calendar_month_outlined,
      title: '安排日程和课程',
      body: '日程适合按时间发生的事情；课程表独立展示，不会把每节课重复塞进日程列表。',
    ),
    _OnboardingItem(
      icon: Icons.storage_outlined,
      title: '按需要整理数据页',
      body: '数据页模块可以固定、排序或隐藏。隐藏只影响入口，不会删除任何本地数据。',
    ),
    _OnboardingItem(
      icon: Icons.shield_outlined,
      title: '提醒与备份都在本地',
      body: '通知、桌面组件和备份需要分别开启。建议先导出一次加密备份，并妥善保存密码。',
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    await widget.onFinished();
    if (mounted) setState(() => finishing = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: finishing ? null : finish,
                child: const Text('跳过引导'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, index) => _OnboardingCard(
                  item: pages[index],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(children: [
                Wrap(
                  spacing: 8,
                  children: List.generate(
                    pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: index == page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: finishing
                        ? null
                        : () async {
                            if (page == pages.length - 1) {
                              await finish();
                            } else {
                              await controller.nextPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                    child: Text(page == pages.length - 1 ? '开始使用' : '下一步'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.item});

  final _OnboardingItem item;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 320),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon,
                  size: 88, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 32),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              Text(
                item.body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
}

class _OnboardingItem {
  const _OnboardingItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
