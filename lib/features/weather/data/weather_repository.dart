import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/weather/domain/weather_models.dart';

export 'package:lifehub/features/weather/domain/weather_models.dart';

class WeatherRepository {
  WeatherRepository(
    this._database, {
    http.Client? client,
    this.geocodingBaseUrl = 'https://geocoding-api.open-meteo.com/v1/search',
    this.forecastBaseUrl = 'https://api.open-meteo.com/v1/forecast',
    this.airQualityBaseUrl =
        'https://air-quality-api.open-meteo.com/v1/air-quality',
  }) : _client = client ?? http.Client();

  final AppDatabase _database;
  final http.Client _client;
  final String geocodingBaseUrl;
  final String forecastBaseUrl;
  final String airQualityBaseUrl;

  Future<WeatherLocationEntry?> defaultLocation() async {
    final values = await locations();
    if (values.isEmpty) return null;
    return values.firstWhere((row) => row.isDefault,
        orElse: () => values.first);
  }

  Future<WeatherLocationDraft> locationFromCoordinates(
    double latitude,
    double longitude, {
    String? name,
    String? country,
    String? admin1,
    String? admin2,
    String? admin3,
    String? admin4,
  }) async {
    return WeatherLocationDraft(
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : '当前位置 ${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}',
      country: country,
      admin1: admin1,
      admin2: admin2,
      admin3: admin3,
      admin4: admin4,
      latitude: latitude,
      longitude: longitude,
      timezone: 'auto',
    );
  }

  Future<List<WeatherLocationDraft>> searchDistricts(String query) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    final uri = Uri.parse(geocodingBaseUrl).replace(queryParameters: {
      'name': value,
      'count': '20',
      'language': 'zh',
      'format': 'json',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('天气地区查询失败（${response.statusCode}）');
    }
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = root['results'] as List<dynamic>? ?? const [];
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      return WeatherLocationDraft(
        name: row['name'] as String,
        country: row['country'] as String?,
        admin1: row['admin1'] as String?,
        admin2: row['admin2'] as String?,
        admin3: row['admin3'] as String?,
        admin4: row['admin4'] as String?,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        timezone: row['timezone'] as String? ?? 'Asia/Shanghai',
      );
    }).toList();
  }

  Future<WeatherLocationEntry> saveLocation(
    WeatherLocationDraft draft, {
    bool makeDefault = false,
  }) async {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    return _database.transaction(() async {
      final count = _database.weatherLocations.id.count();
      final countRow = await (_database.selectOnly(_database.weatherLocations)
            ..addColumns([count])
            ..where(_database.weatherLocations.deletedAt.isNull()))
          .getSingle();
      final shouldDefault = makeDefault || (countRow.read(count) ?? 0) == 0;
      if (shouldDefault) {
        await (_database.update(_database.weatherLocations)
              ..where((row) => row.deletedAt.isNull()))
            .write(const WeatherLocationsCompanion(isDefault: Value(false)));
      }
      return _database.into(_database.weatherLocations).insertReturning(
            WeatherLocationsCompanion.insert(
              name: draft.name.trim(),
              country: Value(draft.country),
              admin1: Value(draft.admin1),
              admin2: Value(draft.admin2),
              admin3: Value(draft.admin3),
              admin4: Value(draft.admin4),
              latitude: draft.latitude,
              longitude: draft.longitude,
              timezone: Value(draft.timezone),
              isDefault: Value(shouldDefault),
              sortKey: Value(DateTime.now().millisecondsSinceEpoch.toDouble()),
            ),
          );
    });
  }

  Future<List<WeatherLocationEntry>> locations() => (_database
          .select(_database.weatherLocations)
        ..where((row) => row.deletedAt.isNull() & row.isFavorite.equals(true))
        ..orderBy([
          (row) => OrderingTerm.desc(row.isDefault),
          (row) => OrderingTerm(expression: row.sortKey),
        ]))
      .get();

  Future<void> setDefault(String id) => _database.transaction(() async {
        await (_database.update(_database.weatherLocations)
              ..where((row) => row.deletedAt.isNull()))
            .write(const WeatherLocationsCompanion(isDefault: Value(false)));
        await (_database.update(_database.weatherLocations)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .write(const WeatherLocationsCompanion(isDefault: Value(true)));
      });

  Future<CurrentWeather> current(WeatherLocationEntry location) async {
    final today = DateTime.now();
    try {
      final uri = Uri.parse(forecastBaseUrl).replace(queryParameters: {
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m',
        'hourly': 'precipitation_probability',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
        'forecast_days': '1',
        'timezone': location.timezone,
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError('forecast http error');
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final current = root['current'] as Map<String, dynamic>;
      final daily = root['daily'] as Map<String, dynamic>;
      final hourly = root['hourly'] as Map<String, dynamic>?;
      final fetchedAt = DateTime.now().toUtc();
      int? aqi;
      try {
        final airUri = Uri.parse(airQualityBaseUrl).replace(queryParameters: {
          'latitude': '${location.latitude}',
          'longitude': '${location.longitude}',
          'current': 'us_aqi',
          'timezone': location.timezone,
        });
        final air =
            await _client.get(airUri).timeout(const Duration(seconds: 6));
        if (air.statusCode == 200) {
          final airRoot = jsonDecode(air.body) as Map<String, dynamic>;
          aqi =
              ((airRoot['current'] as Map<String, dynamic>?)?['us_aqi'] as num?)
                  ?.round();
        }
      } catch (_) {}
      final dailyProbability = daily['precipitation_probability_max'] as List?;
      final probability =
          (dailyProbability != null && dailyProbability.isNotEmpty
                  ? (dailyProbability.first as num?)?.round()
                  : null) ??
              ((hourly?['precipitation_probability'] as List?)
                  ?.whereType<num>()
                  .fold<num>(0, (a, b) => a > b ? a : b))?.round() ??
              0;
      final result = CurrentWeather(
        temperature: (current['temperature_2m'] as num).toDouble(),
        apparentTemperature:
            (current['apparent_temperature'] as num).toDouble(),
        humidity: (current['relative_humidity_2m'] as num).round(),
        weatherCode: (current['weather_code'] as num).round(),
        windSpeed: (current['wind_speed_10m'] as num).toDouble(),
        windDirection: (current['wind_direction_10m'] as num).round(),
        precipitationProbability: probability,
        maximumTemperature:
            ((daily['temperature_2m_max'] as List).first as num).toDouble(),
        minimumTemperature:
            ((daily['temperature_2m_min'] as List).first as num).toDouble(),
        sunrise: DateTime.parse((daily['sunrise'] as List).first as String),
        sunset: DateTime.parse((daily['sunset'] as List).first as String),
        airQualityIndex: aqi,
        fetchedAt: fetchedAt,
      );
      await _writeCurrentCache(location.id, today, result);
      return result;
    } catch (_) {
      final cached = await _readCurrentCache(location.id, today);
      if (cached != null) return cached.copyWith(stale: true);
      rethrow;
    }
  }

  Future<void> _writeCurrentCache(
    String locationId,
    DateTime date,
    CurrentWeather weather,
  ) async {
    final dateKey = _currentDateKey(date);
    final existing = await (_database.select(_database.weatherForecastCaches)
          ..where((row) =>
              row.locationId.equals(locationId) &
              row.forecastDate.equals(dateKey)))
        .getSingleOrNull();
    final payload = jsonEncode({
      'kind': 'current',
      'temperature': weather.temperature,
      'apparentTemperature': weather.apparentTemperature,
      'humidity': weather.humidity,
      'weatherCode': weather.weatherCode,
      'windSpeed': weather.windSpeed,
      'windDirection': weather.windDirection,
      'precipitationProbability': weather.precipitationProbability,
      'maximumTemperature': weather.maximumTemperature,
      'minimumTemperature': weather.minimumTemperature,
      'sunrise': weather.sunrise.toIso8601String(),
      'sunset': weather.sunset.toIso8601String(),
      'airQualityIndex': weather.airQualityIndex,
    });
    final companion = WeatherForecastCachesCompanion(
      fetchedAt: Value(weather.fetchedAt.millisecondsSinceEpoch),
      payloadJson: Value(payload),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _database.into(_database.weatherForecastCaches).insert(
            WeatherForecastCachesCompanion.insert(
              locationId: locationId,
              forecastDate: dateKey,
              fetchedAt: weather.fetchedAt.millisecondsSinceEpoch,
              payloadJson: payload,
            ),
          );
    } else {
      await (_database.update(_database.weatherForecastCaches)
            ..where((row) => row.id.equals(existing.id)))
          .write(companion);
    }
  }

  Future<CurrentWeather?> _readCurrentCache(
    String locationId,
    DateTime date,
  ) async {
    final row = await (_database.select(_database.weatherForecastCaches)
          ..where((value) =>
              value.locationId.equals(locationId) &
              value.forecastDate.equals(_currentDateKey(date)) &
              value.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final value = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    if (value['kind'] != 'current') return null;
    return CurrentWeather(
      temperature: (value['temperature'] as num).toDouble(),
      apparentTemperature: (value['apparentTemperature'] as num).toDouble(),
      humidity: (value['humidity'] as num).round(),
      weatherCode: (value['weatherCode'] as num).round(),
      windSpeed: (value['windSpeed'] as num).toDouble(),
      windDirection: (value['windDirection'] as num).round(),
      precipitationProbability:
          (value['precipitationProbability'] as num).round(),
      maximumTemperature: (value['maximumTemperature'] as num).toDouble(),
      minimumTemperature: (value['minimumTemperature'] as num).toDouble(),
      sunrise: DateTime.parse(value['sunrise'] as String),
      sunset: DateTime.parse(value['sunset'] as String),
      airQualityIndex: (value['airQualityIndex'] as num?)?.round(),
      fetchedAt:
          DateTime.fromMillisecondsSinceEpoch(row.fetchedAt, isUtc: true),
      stale: true,
    );
  }

  Future<DailyWeather> daily(
    WeatherLocationEntry location,
    DateTime date,
  ) async {
    final normalized = DateTime(date.year, date.month, date.day);
    try {
      final iso = _isoDate(normalized);
      final uri = Uri.parse(forecastBaseUrl).replace(queryParameters: {
        'latitude': location.latitude.toString(),
        'longitude': location.longitude.toString(),
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': location.timezone,
        'start_date': iso,
        'end_date': iso,
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw StateError('forecast http error');
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = root['daily'] as Map<String, dynamic>;
      final fetchedAt = DateTime.now().toUtc();
      final result = DailyWeather(
        date: DateTime.parse((daily['time'] as List).first as String),
        weatherCode: ((daily['weather_code'] as List).first as num).toInt(),
        maximumTemperature:
            ((daily['temperature_2m_max'] as List).first as num).toDouble(),
        minimumTemperature:
            ((daily['temperature_2m_min'] as List).first as num).toDouble(),
        precipitationProbability:
            ((daily['precipitation_probability_max'] as List).first as num?)
                    ?.toInt() ??
                0,
        fetchedAt: fetchedAt,
      );
      await _writeCache(location.id, normalized, result);
      return result;
    } catch (_) {
      final cached = await _readCache(location.id, normalized);
      if (cached != null) return cached.copyWith(stale: true);
      rethrow;
    }
  }

  Future<void> _writeCache(
    String locationId,
    DateTime date,
    DailyWeather weather,
  ) async {
    final dateKey = _dateKey(date);
    final existing = await (_database.select(_database.weatherForecastCaches)
          ..where((row) =>
              row.locationId.equals(locationId) &
              row.forecastDate.equals(dateKey)))
        .getSingleOrNull();
    final payload = jsonEncode({
      'date': _isoDate(weather.date),
      'weatherCode': weather.weatherCode,
      'maximumTemperature': weather.maximumTemperature,
      'minimumTemperature': weather.minimumTemperature,
      'precipitationProbability': weather.precipitationProbability,
    });
    if (existing == null) {
      await _database.into(_database.weatherForecastCaches).insert(
            WeatherForecastCachesCompanion.insert(
              locationId: locationId,
              forecastDate: dateKey,
              fetchedAt: weather.fetchedAt.millisecondsSinceEpoch,
              payloadJson: payload,
            ),
          );
    } else {
      await (_database.update(_database.weatherForecastCaches)
            ..where((row) => row.id.equals(existing.id)))
          .write(WeatherForecastCachesCompanion(
        fetchedAt: Value(weather.fetchedAt.millisecondsSinceEpoch),
        payloadJson: Value(payload),
        deletedAt: const Value(null),
      ));
    }
  }

  Future<DailyWeather?> _readCache(String locationId, DateTime date) async {
    final row = await (_database.select(_database.weatherForecastCaches)
          ..where((value) =>
              value.locationId.equals(locationId) &
              value.forecastDate.equals(_dateKey(date)) &
              value.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return DailyWeather(
      date: DateTime.parse(payload['date'] as String),
      weatherCode: (payload['weatherCode'] as num).toInt(),
      maximumTemperature: (payload['maximumTemperature'] as num).toDouble(),
      minimumTemperature: (payload['minimumTemperature'] as num).toDouble(),
      precipitationProbability:
          (payload['precipitationProbability'] as num).toInt(),
      fetchedAt:
          DateTime.fromMillisecondsSinceEpoch(row.fetchedAt, isUtc: true),
      stale: true,
    );
  }
}

int _dateKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

// Current conditions and daily forecasts share the same cache table. A
// negative key keeps both payload shapes available for the same day/location.
int _currentDateKey(DateTime value) => -_dateKey(value);

String _isoDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
