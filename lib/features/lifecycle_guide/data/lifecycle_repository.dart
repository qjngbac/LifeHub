import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';

class LifecycleRepository {
  LifecycleRepository({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  LifecycleCatalog? _cached;

  Future<LifecycleCatalog> loadCatalog() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await _bundle.loadString(
      'assets/content/lifecycle_guide/catalog.json',
    );
    return _cached = LifecycleCatalog.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}
