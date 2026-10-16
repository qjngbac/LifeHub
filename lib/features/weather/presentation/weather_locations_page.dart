import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/weather/data/device_location_service.dart';
import 'package:lifehub/features/weather/data/weather_repository.dart';

class WeatherLocationsPage extends ConsumerStatefulWidget {
  const WeatherLocationsPage({super.key});

  @override
  ConsumerState<WeatherLocationsPage> createState() =>
      _WeatherLocationsPageState();
}

class _WeatherLocationsPageState extends ConsumerState<WeatherLocationsPage> {
  final locationService = DeviceLocationService();
  int revision = 0;
  bool locating = false;
  String? message;

  @override
  Widget build(BuildContext context) {
    final repository = WeatherRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 22),
            SizedBox(width: 8),
            Text('天气'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '添加备用地区',
            onPressed: () => _search(repository),
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
          if (locating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: '定位并刷新当前天气',
              onPressed: () => _locate(repository),
              icon: const Icon(Icons.my_location),
            ),
        ],
      ),
      body: FutureBuilder<List<WeatherLocationEntry>>(
        key: ValueKey(revision),
        future: repository.locations(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = snapshot.data!;
          final defaultLocation = values.isEmpty
              ? null
              : values.firstWhere(
                  (row) => row.isDefault,
                  orElse: () => values.first,
                );

          return RefreshIndicator(
            onRefresh: () => _locate(repository),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (values.isEmpty)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 36),
                      child: Column(
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂未添加天气地区',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '开启定位可自动获取当前城市天气，或手动搜索添加全国 3000+ 区县城市。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    locating ? null : () => _locate(repository),
                                icon: locating
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.my_location, size: 18),
                                label: Text(locating ? '定位中...' : '定位当前城市'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _search(repository),
                                icon: const Icon(Icons.search, size: 18),
                                label: const Text('手动搜索地区'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _WeatherHeroCard(
                    repository: repository,
                    location: defaultLocation!,
                    statusMessage: message,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '地区管理 (${values.length})',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: () => _search(repository),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加地区'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (values.length == 1)
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '当前仅关注了 1 个地区，可点击右上角「添加地区」添加备用城市天气。',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final value in values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: value.isDefault
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.4)
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.4),
                            width: value.isDefault ? 1.4 : 0.8,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () =>
                              _showLocationWeatherDialog(repository, value),
                          onLongPress: () =>
                              _confirmDeleteLocation(repository, value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: value.isDefault
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    value.isDefault
                                        ? Icons.home_rounded
                                        : Icons.location_city_rounded,
                                    color: value.isDefault
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                value.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (value.isDefault) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '当前主城',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Builder(
                                        builder: (context) {
                                          final hierarchy =
                                              formatLocationHierarchy(value);
                                          if (hierarchy.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              hierarchy,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (value.isDefault)
                                  _WeatherTileSummary(
                                    repository: repository,
                                    location: value,
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _WeatherTileSummary(
                                        repository: repository,
                                        location: value,
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.tonal(
                                        onPressed: () async {
                                          await repository.setDefault(value.id);
                                          if (mounted) {
                                            setState(() => revision++);
                                          }
                                        },
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 0),
                                          textStyle: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        child: const Text('设为主城'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _locate(WeatherRepository repository) async {
    setState(() {
      locating = true;
      message = null;
    });
    try {
      final coordinates = await locationService.current();
      final draft = await repository.locationFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
        name: coordinates.name,
        country: coordinates.country,
        admin1: coordinates.admin1,
        admin2: coordinates.admin2,
        admin3: coordinates.admin3,
        admin4: coordinates.admin4,
      );
      final existing = await repository.locations();
      WeatherLocationEntry location;
      if (existing.any((row) =>
          (row.latitude - coordinates.latitude).abs() < 0.001 &&
          (row.longitude - coordinates.longitude).abs() < 0.001)) {
        location = existing.firstWhere((row) =>
            (row.latitude - coordinates.latitude).abs() < 0.001 &&
            (row.longitude - coordinates.longitude).abs() < 0.001);
        await repository.setDefault(location.id);
      } else {
        location = await repository.saveLocation(draft, makeDefault: true);
      }
      await repository.current(location);
      if (!mounted) return;
      setState(() {
        locating = false;
        message = '已按当前位置刷新天气';
        revision++;
      });
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      final value = switch (error.failure) {
        DeviceLocationFailure.serviceDisabled => '请先开启手机定位服务',
        DeviceLocationFailure.denied => '未获得定位权限，可重新授权或使用备用地区',
        DeviceLocationFailure.deniedForever => '定位权限已被永久拒绝，请到系统设置中开启',
      };
      setState(() {
        locating = false;
        message = value;
      });
      if (error.failure == DeviceLocationFailure.deniedForever) {
        await _showSettings();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        locating = false;
        message = '当前无法刷新；如已有缓存，仍会显示上次天气';
        revision++;
      });
    }
  }

  Future<void> _showSettings() async {
    final open = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('开启定位权限'),
            content: const Text('天气需要“使用期间位置”权限。可前往系统设置开启，不需要后台定位。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('去设置')),
            ],
          ),
        ) ??
        false;
    if (open) await locationService.openSettings();
  }

  Future<void> _search(WeatherRepository repository) async {
    final controller = TextEditingController();
    var results = const <WeatherLocationDraft>[];
    var loading = false;
    String? error;
    Timer? debounceTimer;

    final selected = await showDialog<WeatherLocationDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void doSearch(String query) {
            final val = query.trim();
            if (val.length < 2) {
              setDialogState(() {
                results = const [];
                error = null;
                loading = false;
              });
              return;
            }
            setDialogState(() {
              loading = true;
              error = null;
            });
            repository.searchDistricts(val).then((items) {
              setDialogState(() {
                results = items;
                loading = false;
                error = items.isEmpty ? '没有找到，请尝试更简短或更完整的区县名称' : null;
              });
            }).catchError((_) {
              setDialogState(() {
                results = const [];
                loading = false;
                error = '联网搜索失败，请检查网络后重试';
              });
            });
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.search_rounded, size: 22),
                SizedBox(width: 8),
                Text('搜索备用地区'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '输入区、县或城市名 (如 柘城、呈贡、海淀)',
                      prefixIcon: const Icon(Icons.location_searching),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          setDialogState(() {
                            results = const [];
                            error = null;
                          });
                        },
                      ),
                    ),
                    onChanged: (text) {
                      debounceTimer?.cancel();
                      debounceTimer =
                          Timer(const Duration(milliseconds: 250), () {
                        doSearch(text);
                      });
                    },
                    onSubmitted: (text) => doSearch(text),
                  ),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (results.isEmpty && controller.text.trim().isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '🔥 热门及常查地区：',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        '北京',
                        '上海',
                        '广州',
                        '深圳',
                        '杭州',
                        '成都',
                        '柘城',
                        '呈贡',
                        '商丘',
                        '昆明'
                      ]
                          .map((tag) => ActionChip(
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  controller.text = tag;
                                  doSearch(tag);
                                },
                              ))
                          .toList(),
                    ),
                    const Divider(height: 20),
                    const Text(
                      '💡 提示：支持全国 3700+ 省市县区离线即刻检索，即使偏远区县亦能精准匹配。',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                  Expanded(
                    child: ListView.separated(
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          leading:
                              const Icon(Icons.location_on_outlined, size: 20),
                          title: Text(item.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(item.displayName,
                              style: const TextStyle(fontSize: 11.5)),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
    debounceTimer?.cancel();
    controller.dispose();
    if (selected == null) return;
    final saved = await repository.saveLocation(selected);
    try {
      await repository.current(saved);
    } catch (_) {}
    if (mounted) setState(() => revision++);
  }

  Future<void> _showLocationWeatherDialog(
    WeatherRepository repository,
    WeatherLocationEntry location,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WeatherHeroCard(
                repository: repository,
                location: location,
                isPopup: true,
                onSetDefault: !location.isDefault
                    ? () async {
                        Navigator.pop(dialogCtx);
                        await repository.setDefault(location.id);
                        if (!mounted) return;
                        setState(() => revision++);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已将「${location.name}」设为主城'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 14),
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(dialogCtx),
                  tooltip: '关闭',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLocation(
    WeatherRepository repository,
    WeatherLocationEntry location,
  ) async {
    HapticFeedback.mediumImpact();
    if (location.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${location.name}」是当前主城，不可删除。如需删除请先将其他地区设为主城。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('删除地区'),
          ],
        ),
        content: Text('确定要删除备用地区「${location.name}」吗？\n删除后可随时通过右上角重新添加。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await repository.deleteLocation(location.id);
      if (mounted) {
        setState(() => revision++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除地区「${location.name}」'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Formats administrative divisions concisely up to city-level,
/// removing redundant country prefixes for Chinese cities to avoid ellipses.
String formatLocationHierarchy(WeatherLocationEntry location) {
  final country = location.country?.trim();
  final a1 = location.admin1?.trim();
  final a2 = location.admin2?.trim();
  final name = location.name.trim();

  final parts = <String>[];

  // If outside China, include country name
  if (country != null && country.isNotEmpty && country != '中国') {
    parts.add(country);
  }

  if (a1 != null && a1.isNotEmpty) {
    final isDirectCity = (a1.contains('北京') ||
        a1.contains('上海') ||
        a1.contains('天津') ||
        a1.contains('重庆'));
    if (isDirectCity) {
      final cityName = a1.endsWith('市') ? a1 : '$a1市';
      if (name != cityName) {
        parts.add(cityName);
      }
    } else {
      parts.add(a1);
      if (a2 != null && a2.isNotEmpty && a2 != a1 && a2 != name) {
        parts.add(a2);
      }
    }
  } else if (a2 != null && a2.isNotEmpty && a2 != name) {
    parts.add(a2);
  }

  if (parts.isEmpty) {
    if (a1 != null &&
        (a1.contains('北京') ||
            a1.contains('上海') ||
            a1.contains('天津') ||
            a1.contains('重庆'))) {
      return '直辖市';
    }
    if (country != null && country.isNotEmpty && country != '中国') {
      return country;
    }
    return '';
  }
  return parts.join(' · ');
}

class _WeatherTileSummary extends StatelessWidget {
  const _WeatherTileSummary({
    required this.repository,
    required this.location,
  });

  final WeatherRepository repository;
  final WeatherLocationEntry location;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CurrentWeather>(
      future: repository.current(location),
      builder: (context, snapshot) {
        final weather = snapshot.data;
        if (weather == null) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _weatherIcon(weather.weatherCode),
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              '${weather.temperature.round()}°',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              _weatherText(weather.weatherCode),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeatherHeroCard extends StatelessWidget {
  const _WeatherHeroCard({
    required this.repository,
    required this.location,
    this.statusMessage,
    this.isPopup = false,
    this.onSetDefault,
  });

  final WeatherRepository repository;
  final WeatherLocationEntry location;
  final String? statusMessage;
  final bool isPopup;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CurrentWeather>(
      future: repository.current(location),
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null) {
          return Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              location.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    location.isDefault
                                        ? Icons.near_me
                                        : Icons.location_on_outlined,
                                    size: 11,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    location.isDefault ? '当前主城' : '备用地区',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Builder(
                          builder: (context) {
                            final hierarchy =
                                formatLocationHierarchy(location);
                            if (hierarchy.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              hierarchy,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          snapshot.hasError
                              ? '天气拉取失败，请检查网络后刷新'
                              : '正在获取实时气象数据...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onSetDefault != null)
                    FilledButton.tonal(
                      onPressed: onSetDefault,
                      child: const Text('设为主城'),
                    ),
                ],
              ),
            ),
          );
        }

        final tips = <String>[];
        if (value.precipitationProbability >= 30 ||
            (value.weatherCode >= 51 && value.weatherCode <= 82)) {
          tips.add('☂️ 建议带伞（降雨概率${value.precipitationProbability}%）');
        }
        final tempDiff = value.maximumTemperature - value.minimumTemperature;
        if (tempDiff >= 10) {
          tips.add('🧥 昼夜温差大（${tempDiff.round()}℃），注意添衣');
        }
        if (value.weatherCode <= 1 && value.maximumTemperature >= 26) {
          tips.add('🧴 阳光充足，注意防晒补水');
        }
        if (value.windSpeed >= 20) {
          tips.add('💨 风力较大（${value.windSpeed.toStringAsFixed(0)}km/h），外出防风');
        }
        if (value.airQualityIndex != null && value.airQualityIndex! <= 50) {
          tips.add('🍃 空气优良，适合外出通风');
        }

        return Container(
          decoration: BoxDecoration(
            gradient: _weatherGradient(value.weatherCode),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                location.name,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      location.isDefault
                                          ? Icons.near_me
                                          : Icons.location_on_outlined,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      location.isDefault ? '当前主城' : '备用地区',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (context) {
                              final hierarchy =
                                  formatLocationHierarchy(location);
                              if (hierarchy.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                hierarchy,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (onSetDefault != null) ...[
                      FilledButton.tonalIcon(
                        onPressed: onSetDefault,
                        icon: const Icon(Icons.home_outlined, size: 16),
                        label: const Text('设为主城'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                        ),
                      ),
                    ] else if (value.stale)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '离线缓存',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '${value.temperature.round()}°',
                      style: const TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_weatherIcon(value.weatherCode),
                                color: Colors.white, size: 26),
                            const SizedBox(width: 6),
                            Text(
                              _weatherText(value.weatherCode),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '体感 ${value.apparentTemperature.round()}°  ·  最高 ${value.maximumTemperature.round()}° / 最低 ${value.minimumTemperature.round()}°',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _metricCapsule(
                        Icons.water_drop_outlined,
                        '湿度',
                        '${value.humidity}%',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCapsule(
                        Icons.air_rounded,
                        '风速',
                        '${value.windSpeed.toStringAsFixed(1)} km/h',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCapsule(
                        Icons.umbrella_outlined,
                        '降水率',
                        '${value.precipitationProbability}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metricCapsule(
                        Icons.energy_savings_leaf_outlined,
                        '空气',
                        _aqi(value.airQualityIndex),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCapsule(
                        Icons.wb_twilight_rounded,
                        '日出',
                        DateFormat('HH:mm').format(value.sunrise),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCapsule(
                        Icons.nightlight_outlined,
                        '日落',
                        DateFormat('HH:mm').format(value.sunset),
                      ),
                    ),
                  ],
                ),
                if (tips.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: tips
                        .map((tip) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tip,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 12, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      '${value.stale ? '离线显示 · ' : ''}更新于 ${DateFormat('M月d日 HH:mm').format(value.fetchedAt.toLocal())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const Spacer(),
                      Text(
                        statusMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricCapsule(IconData icon, String label, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  val,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

LinearGradient _weatherGradient(int weatherCode) {
  if (weatherCode == 0) {
    return const LinearGradient(
      colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  } else if (weatherCode <= 3) {
    return const LinearGradient(
      colors: [Color(0xFF475569), Color(0xFF64748B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  } else if (weatherCode >= 51 && weatherCode <= 82) {
    return const LinearGradient(
      colors: [Color(0xFF1E293B), Color(0xFF334155)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  } else if (weatherCode >= 95) {
    return const LinearGradient(
      colors: [Color(0xFF312E81), Color(0xFF4338CA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  } else if ((weatherCode >= 71 && weatherCode <= 77) ||
      (weatherCode >= 85 && weatherCode <= 86)) {
    return const LinearGradient(
      colors: [Color(0xFF1E293B), Color(0xFF475569)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
  return const LinearGradient(
    colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

String _weatherText(int code) => switch (code) {
      0 => '晴',
      1 || 2 => '少云',
      3 => '阴',
      45 || 48 => '雾',
      >= 51 && <= 67 => '雨',
      >= 71 && <= 77 => '雪',
      >= 80 && <= 82 => '阵雨',
      >= 85 && <= 86 => '阵雪',
      >= 95 => '雷暴',
      _ => '天气变化',
    };

IconData _weatherIcon(int code) => switch (code) {
      0 => Icons.wb_sunny_outlined,
      1 || 2 => Icons.wb_cloudy_outlined,
      3 || 45 || 48 => Icons.cloud_outlined,
      >= 71 && <= 77 || >= 85 && <= 86 => Icons.ac_unit,
      >= 95 => Icons.thunderstorm_outlined,
      >= 51 && <= 82 => Icons.water_drop_outlined,
      _ => Icons.cloud_queue,
    };

String _aqi(int? value) {
  if (value == null) return '未知';
  return switch (value) {
    <= 50 => '优 ($value)',
    <= 100 => '良 ($value)',
    <= 150 => '轻度 ($value)',
    <= 200 => '中度 ($value)',
    _ => '差 ($value)',
  };
}
