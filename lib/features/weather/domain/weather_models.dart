class WeatherLocationDraft {
  const WeatherLocationDraft({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.country,
    this.admin1,
    this.admin2,
    this.admin3,
    this.admin4,
  });

  final String name;
  final String? country;
  final String? admin1;
  final String? admin2;
  final String? admin3;
  final String? admin4;
  final double latitude;
  final double longitude;
  final String timezone;

  String get displayName => [
        country,
        admin1,
        admin2,
        admin3,
        admin4,
        name,
      ]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' · ');
}

class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.weatherCode,
    required this.maximumTemperature,
    required this.minimumTemperature,
    required this.precipitationProbability,
    required this.fetchedAt,
    this.stale = false,
  });

  final DateTime date;
  final int weatherCode;
  final double maximumTemperature;
  final double minimumTemperature;
  final int precipitationProbability;
  final DateTime fetchedAt;
  final bool stale;

  DailyWeather copyWith({bool? stale}) => DailyWeather(
        date: date,
        weatherCode: weatherCode,
        maximumTemperature: maximumTemperature,
        minimumTemperature: minimumTemperature,
        precipitationProbability: precipitationProbability,
        fetchedAt: fetchedAt,
        stale: stale ?? this.stale,
      );
}

class CurrentWeather {
  const CurrentWeather({
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.weatherCode,
    required this.windSpeed,
    required this.windDirection,
    required this.precipitationProbability,
    required this.maximumTemperature,
    required this.minimumTemperature,
    required this.sunrise,
    required this.sunset,
    required this.fetchedAt,
    this.airQualityIndex,
    this.stale = false,
  });

  final double temperature;
  final double apparentTemperature;
  final int humidity;
  final int weatherCode;
  final double windSpeed;
  final int windDirection;
  final int precipitationProbability;
  final double maximumTemperature;
  final double minimumTemperature;
  final DateTime sunrise;
  final DateTime sunset;
  final int? airQualityIndex;
  final DateTime fetchedAt;
  final bool stale;

  CurrentWeather copyWith({bool? stale}) => CurrentWeather(
        temperature: temperature,
        apparentTemperature: apparentTemperature,
        humidity: humidity,
        weatherCode: weatherCode,
        windSpeed: windSpeed,
        windDirection: windDirection,
        precipitationProbability: precipitationProbability,
        maximumTemperature: maximumTemperature,
        minimumTemperature: minimumTemperature,
        sunrise: sunrise,
        sunset: sunset,
        airQualityIndex: airQualityIndex,
        fetchedAt: fetchedAt,
        stale: stale ?? this.stale,
      );
}
