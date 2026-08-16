import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

enum DeviceLocationFailure { serviceDisabled, denied, deniedForever }

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.failure);
  final DeviceLocationFailure failure;
}

class DeviceCoordinates {
  const DeviceCoordinates(
    this.latitude,
    this.longitude, {
    this.name,
    this.country,
    this.admin1,
    this.admin2,
    this.admin3,
    this.admin4,
  });
  final double latitude;
  final double longitude;
  final String? name;
  final String? country;
  final String? admin1;
  final String? admin2;
  final String? admin3;
  final String? admin4;
}

class DeviceLocationService {
  Future<DeviceCoordinates> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
          DeviceLocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(DeviceLocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(DeviceLocationFailure.denied);
    }
    final last = await Geolocator.getLastKnownPosition();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    ).onError((_, __) {
      if (last != null) return last;
      throw const DeviceLocationException(
          DeviceLocationFailure.serviceDisabled);
    });
    try {
      final values = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = values.firstOrNull;
      if (place != null) {
        final name = _firstMeaningful([
          place.subLocality,
          place.subAdministrativeArea,
          place.locality,
          place.administrativeArea,
        ]);
        return DeviceCoordinates(
          position.latitude,
          position.longitude,
          name: name,
          country: _optional(place.country),
          admin1: _optional(place.administrativeArea),
          admin2: _optional(place.locality),
          admin3: _optional(place.subAdministrativeArea),
          admin4: _optional(place.subLocality),
        );
      }
    } catch (_) {
      // Position is still useful when the platform cannot resolve an address.
    }
    return DeviceCoordinates(position.latitude, position.longitude);
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

String? _optional(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

String? _firstMeaningful(List<String?> values) {
  for (final value in values) {
    final result = _optional(value);
    if (result != null) return result;
  }
  return null;
}
