import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/focus/application/focus_clock.dart';
import 'package:lifehub/features/focus/application/focus_controller.dart';
import 'package:lifehub/features/focus/application/white_noise_service.dart';
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
        await WhiteNoiseService.instance.pause();
        if (mounted) {
          _showBreakDialog();
        }
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
          final progress = isStopwatch
              ? ((elapsed.inSeconds % 60) / 60.0)
              : (session.plannedMinutes <= 0
                  ? 0.0
                  : (1.0 - (remaining.inSeconds / (session.plannedMinutes * 60)))
                      .clamp(0.0, 1.0));
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              const SizedBox(height: 12),
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            session.status == FocusStatus.paused
                                ? Colors.orange
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            session.status == FocusStatus.paused
                                ? Icons.pause_circle_outline
                                : (isStopwatch
                                    ? Icons.timer_outlined
                                    : Icons.hourglass_bottom_outlined),
                            size: 32,
                            color: session.status == FocusStatus.paused
                                ? Colors.orange
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _duration(display),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (session.status == FocusStatus.paused
                                      ? Colors.orange
                                      : Theme.of(context).colorScheme.primary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              session.status == FocusStatus.paused
                                  ? '已暂停'
                                  : (isStopwatch ? '正向计时中' : '专注进行中'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: session.status == FocusStatus.paused
                                    ? Colors.orange
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isStopwatch
                    ? '正向计时·已经过 ${_duration(elapsed)}'
                    : '专注倒计时·已专注 ${elapsed.inMinutes} 分钟',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              if (session.status == FocusStatus.paused)
                FilledButton.icon(
                  onPressed: () async {
                    await _controller.resume();
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
                    await _controller.pause();
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
              OutlinedButton.icon(
                icon: const Icon(Icons.fullscreen),
                label: const Text('全屏沉浸大时钟'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullscreenClockPage(
                        session: session,
                        repository: _repository,
                        controller: _controller,
                      ),
                    ),
                  );
                  _reload();
                },
              ),
              const SizedBox(height: 16),
              _WhiteNoiseCard(onStateChanged: () => setState(() {})),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await _repository.finish(session.id);
                  await _cancelFocusNotification();
                  await WhiteNoiseService.instance.stop();
                  _reload();
                },
                child: const Text('结束并保存'),
              ),
              TextButton(
                onPressed: () async {
                  await _repository.discard(session.id);
                  await _cancelFocusNotification();
                  await WhiteNoiseService.instance.stop();
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

  Widget _ready(FocusRepository repository) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(
          child: Icon(Icons.self_improvement_outlined, size: 48),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          showSelectedIcon: false,
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
        const SizedBox(height: 20),
        Text(
          selectedMode == FocusMode.stopwatch ? '从 00:00 开始计时' : '选择计划时长',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (selectedMode == FocusMode.countdown) ...[
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 25, label: Text('25分钟')),
              const ButtonSegment(value: 45, label: Text('45分钟')),
              const ButtonSegment(value: 60, label: Text('60分钟')),
              if (!const {25, 45, 60}.contains(selectedMinutes))
                ButtonSegment(
                  value: selectedMinutes,
                  label: Text('$selectedMinutes分钟'),
                ),
            ],
            selected: {selectedMinutes},
            onSelectionChanged: (value) =>
                setState(() => selectedMinutes = value.single),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _chooseCustomMinutes,
            icon: const Icon(Icons.tune),
            label: const Text('自定义专注时间'),
          ),
        ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          _WhiteNoiseCard(onStateChanged: () => setState(() {})),
          const SizedBox(height: 12),
          const Text(
            '专注和计时状态保存在本机。切到后台或重新打开应用后仍可继续。',
            textAlign: TextAlign.center,
          ),
        ],
      );
  }

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

  Future<void> _showBreakDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('专注完成！🎉'),
        content: const Text('太棒了，完成了一次专注！要开始一段小憩休息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('结束'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              Navigator.pop(context);
              await _startBreak(5);
            },
            child: const Text('5 分钟小憩'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _startBreak(15);
            },
            child: const Text('15 分钟长休'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBreak(int minutes) async {
    try {
      await _repository.start(
        FocusDraft(
          plannedMinutes: minutes,
          mode: FocusMode.countdown,
        ),
      );
      await _focusNotification(minutes, paused: false);
      _reload();
    } catch (_) {}
  }

  Future<void> _cancelFocusNotification() async {
    try {
      await NotificationService.instance.cancelFocus();
    } catch (_) {}
  }
}

class _WhiteNoiseCard extends StatelessWidget {
  const _WhiteNoiseCard({required this.onStateChanged});
  final VoidCallback onStateChanged;

  @override
  Widget build(BuildContext context) {
    final service = WhiteNoiseService.instance;
    final currentId = service.currentSoundId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq, size: 20),
                const SizedBox(width: 8),
                const Text('背景白噪音',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (currentId != null)
                  Text(
                    service.isPlaying ? '播放中' : '已暂停',
                    style: TextStyle(
                      fontSize: 12,
                      color: service.isPlaying ? Colors.green : Colors.grey,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    showCheckmark: false,
                    label: const Text('无声'),
                    selected: currentId == null,
                    onSelected: (selected) async {
                      if (selected) {
                        await service.stop();
                        onStateChanged();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  for (final item in WhiteNoiseService.available) ...[
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(
                        item.id == 'rain'
                            ? Icons.water_drop_outlined
                            : item.id == 'campfire'
                                ? Icons.local_fire_department_outlined
                                : item.id == 'waves'
                                    ? Icons.waves_outlined
                                    : Icons.forest_outlined,
                        size: 16,
                      ),
                      label: Text(item.name),
                      selected: currentId == item.id,
                      onSelected: (selected) async {
                        if (selected) {
                          await service.play(item.id);
                        } else {
                          await service.stop();
                        }
                        onStateChanged();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (service.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  service.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (currentId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_down, size: 16, color: Colors.grey),
                  Expanded(
                    child: Slider(
                      value: service.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) async {
                        await service.setVolume(v);
                        onStateChanged();
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 16, color: Colors.grey),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FullscreenClockPage extends StatefulWidget {
  const FullscreenClockPage({
    super.key,
    required this.session,
    required this.repository,
    required this.controller,
  });

  final FocusSessionEntry session;
  final FocusRepository repository;
  final FocusController controller;

  @override
  State<FullscreenClockPage> createState() => _FullscreenClockPageState();
}

class _FullscreenClockPageState extends State<FullscreenClockPage> {
  Timer? _ticker;
  late FocusSessionEntry _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final updated = await widget.repository.get(_session.id);
      if (mounted) setState(() => _session = updated);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = FocusClock.elapsed(_session, DateTime.now());
    final isStopwatch = _session.mode == FocusMode.stopwatch;
    final remaining = Duration(minutes: _session.plannedMinutes) - elapsed;
    final display = isStopwatch
        ? elapsed
        : (remaining.isNegative ? Duration.zero : remaining);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit,
                    color: Colors.white70, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _duration(display),
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                      letterSpacing: 2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isStopwatch
                        ? '正向计时中'
                        : (_session.status == FocusStatus.paused
                            ? '已暂停'
                            : '专注倒计时'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_session.status == FocusStatus.paused)
                        IconButton.filled(
                          iconSize: 32,
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () async {
                            final updated = await widget.controller.resume();
                            if (mounted) setState(() => _session = updated);
                          },
                        )
                      else if (_session.status == FocusStatus.running)
                        IconButton.filledTonal(
                          iconSize: 32,
                          icon: const Icon(Icons.pause),
                          onPressed: () async {
                            final updated = await widget.controller.pause();
                            if (mounted) setState(() => _session = updated);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
