import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/today/application/today_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetSnapshotService {
  WidgetSnapshotService(this._database);
  final AppDatabase _database;

  static const _channel = MethodChannel('lifehub/widgets');

  Future<Map<String, Object?>> refresh({
    DateTime? now,
    SharedPreferences? preferences,
    bool notifyNative = true,
  }) async {
    final current = now ?? DateTime.now();
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
      'nextEventTitle': nextEvent?.title ?? '',
      'nextEventTime':
          nextEvent == null ? '' : DateFormat.Hm().format(nextEvent.start),
      'nextCourseTitle': nextCourse?.title ?? '',
      'nextCourseTime':
          nextCourse == null ? '' : DateFormat.Hm().format(nextCourse.start),
      'nextCourseTeacher': nextCourse?.teacher ?? '',
      'nextCourseRoom': nextCourse?.room ?? '',
      'courseEntriesJson': jsonEncode(courses
          .map((value) => {
                'title': value.title,
                'startAt': value.start.millisecondsSinceEpoch,
                'endAt': value.end.millisecondsSinceEpoch,
                'teacher': value.teacher ?? '',
                'room': value.room ?? '',
              })
          .toList()),
      'eventEntriesJson': jsonEncode(today.events
          .map((value) => {
                'title': value.title,
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
    if (notifyNative) {
      await _channel.invokeMethod<bool>('updateWidgets', snapshot);
    }
    return snapshot;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
