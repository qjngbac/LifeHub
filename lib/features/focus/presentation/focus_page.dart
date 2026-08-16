import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/focus/application/focus_clock.dart';
import 'package:lifehub/features/focus/application/focus_controller.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  int selectedMinutes = 45;
  String selectedMode = FocusMode.countdown;
  String? selectedEntityType;
  String? selectedEntityId;
  String? selectedEntityTitle;
  bool _starting = false;
  Timer? _ticker;
  late final FocusRepository _repository;
  late final FocusController _controller;
  late Future<FocusSessionEntry?> _activeFuture;
  bool _checkingDue = false;

  @override
  void initState() {
    super.initState();
    _repository = FocusRepository(ref.read(databaseProvider));
    _controller = FocusController(
      _repository,
      onCompleted: (session) async {
        try {
          await NotificationService.instance.cancelFocus();
          await NotificationService.instance.showFocusCompleted(
            plannedMinutes: session.plannedMinutes,
          );
        } catch (_) {}
      },
    );
    _activeFuture = _controller.load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _onTick() async {
    if (!mounted || _checkingDue) return;
    _checkingDue = true;
    try {
      final completed = await _controller.tick(DateTime.now());
      if (!mounted) return;
      if (completed) {
        setState(() => _activeFuture = Future.value(null));
        ref.read(refreshProvider.notifier).state++;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本次专注已按计划自动完成')),
        );
      } else {
        setState(() {});
      }
    } finally {
      _checkingDue = false;
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _activeFuture = _controller.load();
    });
    ref.read(refreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('专注与计时'),
        actions: [
          IconButton(
            tooltip: '刷新计时',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _activeFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return _ready(_repository);
          }
          final session = snapshot.data!;
          final elapsed = FocusClock.elapsed(session, DateTime.now());
          final isStopwatch = session.mode == FocusMode.stopwatch;
          final remaining = Duration(minutes: session.plannedMinutes) - elapsed;
          final display = isStopwatch
              ? elapsed
              : (remaining.isNegative ? Duration.zero : remaining);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(
                session.status == FocusStatus.paused
                    ? Icons.pause_circle_outline
                    : Icons.timer_outlined,
                size: 72,
              ),
              const SizedBox(height: 20),
              Text(
                _duration(display),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isStopwatch
                    ? '正向计时·已经过 ${_duration(elapsed)}'
                    : '专注倒计时·已专注 ${elapsed.inMinutes} 分钟',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (session.status == FocusStatus.paused)
                FilledButton.icon(
                  onPressed: () async {
                    await _repository.resume(session.id);
                    if (!isStopwatch) {
                      await _focusNotification(
                        session.plannedMinutes,
                        paused: false,
                      );
                    }
                    _reload();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('继续'),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    await _repository.pause(session.id);
                    if (!isStopwatch) {
                      await _focusNotification(
                        session.plannedMinutes,
                        paused: true,
                      );
                    }
                    _reload();
                  },
                  icon: const Icon(Icons.pause),
                  label: const Text('暂停'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await _repository.finish(session.id);
                  await _cancelFocusNotification();
                  _reload();
                },
                child: const Text('结束并保存'),
              ),
              TextButton(
                onPressed: () async {
                  await _repository.discard(session.id);
                  await _cancelFocusNotification();
                  _reload();
                },
                child: const Text('放弃记录', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ready(FocusRepository repository) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
        children: [
          const Icon(Icons.self_improvement_outlined, size: 72),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: FocusMode.countdown,
                icon: Icon(Icons.hourglass_bottom_outlined),
                label: Text('专注倒计时'),
              ),
              ButtonSegment(
                value: FocusMode.stopwatch,
                icon: Icon(Icons.timer_outlined),
                label: Text('正向计时'),
              ),
            ],
            selected: {selectedMode},
            onSelectionChanged: (value) =>
                setState(() => selectedMode = value.single),
          ),
          const SizedBox(height: 28),
          Text(
            selectedMode == FocusMode.stopwatch ? '从 00:00 开始计时' : '选择计划时长',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          if (selectedMode == FocusMode.countdown) ...[
            SegmentedButton<int>(
              segments: [
                const ButtonSegment(value: 25, label: Text('25 分钟')),
                const ButtonSegment(value: 45, label: Text('45 分钟')),
                const ButtonSegment(value: 60, label: Text('60 分钟')),
                if (!const {25, 45, 60}.contains(selectedMinutes))
                  ButtonSegment(
                    value: selectedMinutes,
                    label: Text('$selectedMinutes 分钟'),
                  ),
              ],
              selected: {selectedMinutes},
              onSelectionChanged: (value) =>
                  setState(() => selectedMinutes = value.single),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _chooseCustomMinutes,
              icon: const Icon(Icons.tune),
              label: const Text('自定义专注时间'),
            ),
          ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('适合不确定结束时间的学习或工作，可暂停、继续并保存实际时长。'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _chooseEntity,
            icon: const Icon(Icons.link),
            label: Text(selectedEntityTitle == null
                ? '关联任务或目标（可选）'
                : '已关联：$selectedEntityTitle'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _starting
                ? null
                : () async {
                    setState(() => _starting = true);
                    try {
                      await repository.start(
                        FocusDraft(
                          plannedMinutes: selectedMode == FocusMode.stopwatch
                              ? 0
                              : selectedMinutes,
                          mode: selectedMode,
                          entityType: selectedEntityType,
                          entityId: selectedEntityId,
                        ),
                      );
                      if (selectedMode == FocusMode.countdown) {
                        await _focusNotification(
                          selectedMinutes,
                          paused: false,
                        );
                      }
                      _reload();
                    } finally {
                      if (mounted) setState(() => _starting = false);
                    }
                  },
            icon: const Icon(Icons.play_arrow),
            label: Text(selectedMode == FocusMode.stopwatch ? '开始计时' : '开始专注'),
          ),
          const SizedBox(height: 12),
          const Text(
            '专注和计时状态保存在本机。切到后台或重新打开应用后仍可继续。',
            textAlign: TextAlign.center,
          ),
        ],
      );

  Future<void> _chooseCustomMinutes() async {
    final controller = TextEditingController(text: '$selectedMinutes');
    final value = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('自定义专注时间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟',
            helperText: '1–1440 分钟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              if (minutes != null && minutes >= 1 && minutes <= 1440) {
                Navigator.pop(context, minutes);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) setState(() => selectedMinutes = value);
  }

  Future<void> _chooseEntity() async {
    final database = ref.read(databaseProvider);
    final tasks = await (database.select(database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.isNotIn(['DONE', 'CANCELED', 'ARCHIVED'])))
        .get();
    final goals = await (database.select(database.goals)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ACTIVE')))
        .get();
    if (!mounted) return;
    final choice = await showModalBottomSheet<(String?, String?, String?)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('不关联'),
              onTap: () => Navigator.pop(context, (null, null, null)),
            ),
            ...tasks.map((task) => ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(task.title),
                  subtitle: const Text('任务'),
                  onTap: () =>
                      Navigator.pop(context, ('TASK', task.id, task.title)),
                )),
            ...goals.map((goal) => ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(goal.name),
                  subtitle: const Text('目标'),
                  onTap: () =>
                      Navigator.pop(context, ('GOAL', goal.id, goal.name)),
                )),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      selectedEntityType = choice.$1;
      selectedEntityId = choice.$2;
      selectedEntityTitle = choice.$3;
    });
  }

  Future<void> _focusNotification(int minutes, {required bool paused}) async {
    try {
      await NotificationService.instance
          .showFocus(plannedMinutes: minutes, paused: paused);
    } catch (_) {}
  }

  Future<void> _cancelFocusNotification() async {
    try {
      await NotificationService.instance.cancelFocus();
    } catch (_) {}
  }
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
