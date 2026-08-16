import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/weather/data/weather_repository.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('searches districts and preserves the administrative hierarchy',
      () async {
    final repository = WeatherRepository(
      database,
      client: MockClient((request) async {
        expect(request.url.queryParameters['name'], '海淀区');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'results': [
              {
                'name': '海淀区',
                'country': '中国',
                'admin1': '北京市',
                'admin2': '北京市',
                'latitude': 39.96,
                'longitude': 116.30,
                'timezone': 'Asia/Shanghai'
              }
            ]
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final results = await repository.searchDistricts('海淀区');
    expect(results.single.displayName, '中国 · 北京市 · 北京市 · 海淀区');
    expect(results.single.latitude, 39.96);
  });

  test('keeps one default and uses a cached forecast when the network fails',
      () async {
    var networkWorks = true;
    final repository = WeatherRepository(
      database,
      client: MockClient((request) async {
        if (!networkWorks) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({
            'daily': {
              'time': ['2026-08-12'],
              'weather_code': [61],
              'temperature_2m_max': [31.2],
              'temperature_2m_min': [23.4],
              'precipitation_probability_max': [80]
            }
          }),
          200,
        );
      }),
    );
    final first = await repository.saveLocation(
      const WeatherLocationDraft(
        name: '海淀区',
        latitude: 39.96,
        longitude: 116.30,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: true,
    );
    final second = await repository.saveLocation(
      const WeatherLocationDraft(
        name: '西湖区',
        latitude: 30.25,
        longitude: 120.16,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: true,
    );
    final locations = await repository.locations();
    expect(locations.where((value) => value.isDefault).single.id, second.id);
    expect(locations.firstWhere((value) => value.id == first.id).isDefault,
        isFalse);

    final fresh = await repository.daily(second, DateTime(2026, 8, 12));
    expect(fresh.stale, isFalse);
    expect(fresh.precipitationProbability, 80);
    networkWorks = false;
    final cached = await repository.daily(second, DateTime(2026, 8, 12));
    expect(cached.stale, isTrue);
    expect(cached.maximumTemperature, 31.2);
  });

  test('parses current important weather and falls back to its cache',
      () async {
    var online = true;
    final repository = WeatherRepository(
      database,
      client: MockClient((request) async {
        if (!online) throw http.ClientException('offline');
        if (request.url.host.contains('air-quality')) {
          return http.Response(
              jsonEncode({
                'current': {'us_aqi': 42}
              }),
              200);
        }
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 22.4,
              'relative_humidity_2m': 68,
              'apparent_temperature': 21.1,
              'weather_code': 2,
              'wind_speed_10m': 7.5,
              'wind_direction_10m': 180,
            },
            'hourly': {
              'precipitation_probability': [10, 30]
            },
            'daily': {
              'weather_code': [2],
              'temperature_2m_max': [26.0],
              'temperature_2m_min': [17.0],
              'precipitation_probability_max': [30],
              'sunrise': ['2026-08-12T06:35'],
              'sunset': ['2026-08-12T19:42'],
            }
          }),
          200,
        );
      }),
    );
    final location = await repository.saveLocation(
      const WeatherLocationDraft(
        name: '当前位置',
        latitude: 25.03,
        longitude: 102.71,
        timezone: 'Asia/Shanghai',
      ),
    );
    final fresh = await repository.current(location);
    expect(fresh.temperature, 22.4);
    expect(fresh.humidity, 68);
    expect(fresh.airQualityIndex, 42);
    online = false;
    final cached = await repository.current(location);
    expect(cached.stale, isTrue);
    expect(cached.maximumTemperature, 26);
  });

  test('keeps current conditions and daily forecast caches side by side',
      () async {
    var online = true;
    final repository = WeatherRepository(
      database,
      client: MockClient((request) async {
        if (!online) throw http.ClientException('offline');
        if (request.url.host.contains('air-quality')) {
          return http.Response(
              jsonEncode({
                'current': {'us_aqi': 35}
              }),
              200);
        }
        if (request.url.queryParameters.containsKey('current')) {
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': 20,
                'relative_humidity_2m': 50,
                'apparent_temperature': 19,
                'weather_code': 1,
                'wind_speed_10m': 4,
                'wind_direction_10m': 90,
              },
              'hourly': {
                'precipitation_probability': [5]
              },
              'daily': {
                'weather_code': [1],
                'temperature_2m_max': [25],
                'temperature_2m_min': [15],
                'precipitation_probability_max': [5],
                'sunrise': ['2026-08-12T06:00'],
                'sunset': ['2026-08-12T19:00'],
              }
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'daily': {
              'time': ['2026-08-12'],
              'weather_code': [61],
              'temperature_2m_max': [30],
              'temperature_2m_min': [18],
              'precipitation_probability_max': [70]
            }
          }),
          200,
        );
      }),
    );
    final location = await repository.saveLocation(
      const WeatherLocationDraft(
        name: '当前位置',
        latitude: 25,
        longitude: 102,
        timezone: 'Asia/Shanghai',
      ),
    );
    await repository.current(location);
    await repository.daily(location, DateTime(2026, 8, 12));
    online = false;

    expect((await repository.current(location)).temperature, 20);
    expect(
      (await repository.daily(location, DateTime(2026, 8, 12)))
          .precipitationProbability,
      70,
    );
  });
}
