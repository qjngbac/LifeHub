import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/today/application/today_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WidgetSnapshotService {
  WidgetSnapshotService(this._database);
  final AppDatabase _database;

  static const _channel = MethodChannel('lifehub/widgets');

  Future<Map<String, Object?>> refresh({
    DateTime? now,
    SharedPreferences? preferences,
    bool? privacyMode,
    bool notifyNative = true,
    Directory? snapshotDirectory,
  }) async {
    final current = now ?? DateTime.now();
    final hideDetails =
        privacyMode ?? preferences?.getBool('privacy_mode') ?? false;
    final today = await TodayService(_database).load(current);
    final dayStart = DateTime(current.year, current.month, current.day);
    final courses = await CourseRepository(_database).projectedEvents(
      dayStart,
      dayStart.add(const Duration(days: 8)),
    )
      ..sort((a, b) => a.start.compareTo(b.start));
    final futureCourses =
        courses.where((course) => course.end.isAfter(current)).toList();
    final nextCourse = futureCourses.isEmpty ? null : futureCourses.first;
    final nextEvent =
        today.events.where((event) => event.end.isAfter(current)).firstOrNull;
    final snapshot = <String, Object?>{
      'updatedAt': current.toUtc().millisecondsSinceEpoch,
      'taskCount': today.tasks.length,
      'habitDone': today.habits.where((habit) => habit.completed).length,
      'habitTotal': today.habits.length,
      'nextEventTitle': nextEvent == null
          ? ''
          : hideDetails
              ? '内容已隐藏'
              : nextEvent.title,
      'nextEventTime':
          nextEvent == null ? '' : DateFormat.Hm().format(nextEvent.start),
      'nextCourseTitle': nextCourse == null
          ? ''
          : hideDetails
              ? '内容已隐藏'
              : nextCourse.title,
      'nextCourseTime':
          nextCourse == null ? '' : DateFormat.Hm().format(nextCourse.start),
      'nextCourseTeacher': hideDetails ? '' : nextCourse?.teacher ?? '',
      'nextCourseRoom': hideDetails ? '' : nextCourse?.room ?? '',
      'courseEntriesJson': jsonEncode(courses
          .map((value) => {
                'title': hideDetails ? '内容已隐藏' : value.title,
                'startAt': value.start.millisecondsSinceEpoch,
                'endAt': value.end.millisecondsSinceEpoch,
                'teacher': hideDetails ? '' : value.teacher ?? '',
                'room': hideDetails ? '' : value.room ?? '',
              })
          .toList()),
      'eventEntriesJson': jsonEncode(today.events
          .map((value) => {
                'title': hideDetails ? '内容已隐藏' : value.title,
                'startAt': value.start.millisecondsSinceEpoch,
                'endAt': value.end.millisecondsSinceEpoch,
              })
          .toList()),
    };
    if (preferences != null) {
      for (final entry in snapshot.entries) {
        final key = 'lifehub.widget.${entry.key}';
        final value = entry.value;
        if (value is int) await preferences.setInt(key, value);
        if (value is String) await preferences.setString(key, value);
      }
    }
    final directory =
        snapshotDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'lifehub_widget_snapshot.json'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    if (notifyNative) {
      await _channel.invokeMethod<bool>('updateWidgets', snapshot);
    }
    return snapshot;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
