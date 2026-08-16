import 'package:flutter/material.dart';
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
        title: const Text('天气'),
        actions: [
          IconButton(
            tooltip: '刷新当前位置',
            onPressed: locating ? null : () => _locate(repository),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _search(repository),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('备用地区'),
      ),
      body: FutureBuilder<List<WeatherLocationEntry>>(
        key: ValueKey(revision),
        future: repository.locations(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () => _locate(repository),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('当前位置天气',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(message ?? '仅在进入本页或主动刷新时使用前台定位；断网时显示上次成功缓存。'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed:
                              locating ? null : () => _locate(repository),
                          icon: locating
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.near_me_outlined),
                          label: Text(locating ? '正在定位' : '定位并刷新'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (values.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('暂无天气数据。允许定位并联网后会自动保存当前位置。'),
                    ),
                  ),
                for (final value in values) ...[
                  _WeatherCard(repository: repository, location: value),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: Icon(value.isDefault
                          ? Icons.home_outlined
                          : Icons.location_city_outlined),
                      title: Text(value.name),
                      subtitle: Text([
                        value.country,
                        value.admin1,
                        value.admin2,
                        value.admin3,
                      ].whereType<String>().join(' · ')),
                      trailing: value.isDefault
                          ? const Chip(label: Text('默认'))
                          : TextButton(
                              onPressed: () async {
                                await repository.setDefault(value.id);
                                if (mounted) setState(() => revision++);
                              },
                              child: const Text('设为默认'),
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
    final selected = await showDialog<WeatherLocationDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('手动选择备用地区'),
          content: SizedBox(
            width: double.maxFinite,
            height: 430,
            child: Column(children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '区、县或城市名称',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _runSearch(
                      repository,
                      controller.text,
                      (values, problem) => setDialogState(() {
                        results = values;
                        error = problem;
                        loading = false;
                      }),
                      () => setDialogState(() => loading = true),
                    ),
                  ),
                ),
                onSubmitted: (value) => _runSearch(
                  repository,
                  value,
                  (values, problem) => setDialogState(() {
                    results = values;
                    error = problem;
                    loading = false;
                  }),
                  () => setDialogState(() => loading = true),
                ),
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final value = results[index];
                    return ListTile(
                      title: Text(value.name),
                      subtitle: Text(value.displayName),
                      onTap: () => Navigator.pop(context, value),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (selected == null) return;
    final saved = await repository.saveLocation(selected);
    try {
      await repository.current(saved);
    } catch (_) {}
    if (mounted) setState(() => revision++);
  }

  Future<void> _runSearch(
    WeatherRepository repository,
    String query,
    void Function(List<WeatherLocationDraft>, String?) complete,
    VoidCallback start,
  ) async {
    start();
    try {
      final values = await repository.searchDistricts(query);
      complete(values, values.isEmpty ? '没有找到，请尝试更完整的区县或城市名称' : null);
    } catch (_) {
      complete(const [], '联网搜索失败，请检查网络后重试');
    }
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.repository, required this.location});
  final WeatherRepository repository;
  final WeatherLocationEntry location;

  @override
  Widget build(BuildContext context) => FutureBuilder<CurrentWeather>(
        future: repository.current(location),
        builder: (context, snapshot) {
          final value = snapshot.data;
          if (value == null) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(location.name),
                subtitle: Text(snapshot.hasError ? '暂无天气数据，请联网刷新' : '正在读取天气'),
              ),
            );
          }
          return Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(_weatherIcon(value.weatherCode), size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(location.name,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              Text(
                                  '${value.temperature.round()}℃ · ${_weatherText(value.weatherCode)}'),
                            ]),
                      ),
                      if (value.stale) const Chip(label: Text('缓存')),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 14, runSpacing: 8, children: [
                      Text('体感 ${value.apparentTemperature.round()}℃'),
                      Text('最高 ${value.maximumTemperature.round()}℃'),
                      Text('最低 ${value.minimumTemperature.round()}℃'),
                      Text('湿度 ${value.humidity}%'),
                      Text('风速 ${value.windSpeed.toStringAsFixed(1)} km/h'),
                      Text('降雨 ${value.precipitationProbability}%'),
                      if (value.airQualityIndex != null)
                        Text('空气质量 ${_aqi(value.airQualityIndex!)}'),
                      Text('日出 ${DateFormat('HH:mm').format(value.sunrise)}'),
                      Text('日落 ${DateFormat('HH:mm').format(value.sunset)}'),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                        '${value.stale ? '离线显示上次数据 · ' : ''}更新于 ${DateFormat('M月d日 HH:mm').format(value.fetchedAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
          );
        },
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

String _aqi(int value) => switch (value) {
      <= 50 => '优',
      <= 100 => '良',
      <= 150 => '轻度污染',
      <= 200 => '中度污染',
      _ => '较差',
    };
