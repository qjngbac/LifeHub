import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final refreshProvider = StateProvider<int>((ref) => 0);

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);
