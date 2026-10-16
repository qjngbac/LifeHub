import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/widgets');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'widget snapshot contains useful counts and excludes private mood text',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'lifehub-widget-snapshot-',
      );
      addTearDown(database.close);
      addTearDown(() => directory.delete(recursive: true));
      await TaskRepository(
        database,
      ).create(TaskDraft(title: '桌面任务', dueAt: DateTime(2026, 8, 9, 18)));
      await MoodRepository(database).save(
        MoodDraft(
          date: DateTime(2026, 8, 9),
          moodCode: MoodCatalog.happy,
          note: '绝对不能出现在桌面',
        ),
      );
      Map<Object?, Object?>? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            sent = Map<Object?, Object?>.from(call.arguments as Map);
            return true;
          });

      final snapshot = await WidgetSnapshotService(
        database,
      ).refresh(now: DateTime(2026, 8, 9, 12), snapshotDirectory: directory);

      expect(snapshot['taskCount'], 1);
      expect(snapshot.values.join(' '), isNot(contains('绝对不能')));
      expect(sent?['taskCount'], 1);
    },
  );

  test(
    'course widget snapshot includes today and future courses for native filtering',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'lifehub-widget-snapshot-',
      );
      addTearDown(database.close);
      addTearDown(() => directory.delete(recursive: true));
      final repository = CourseRepository(database);
      final semester = await repository.createSemester(
        SemesterDraft(
          name: '秋季学期',
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 12, 20),
          totalWeeks: 19,
        ),
      );
      final course = await repository.createCourse(
        CourseDraft(
          name: '离散数学',
          semesterId: semester.id,
          teacher: '张老师',
          room: '203',
        ),
      );
      await repository.createSchedule(
        CourseScheduleDraft(
          courseId: course.id,
          weekday: DateTime.monday,
          startMinutes: 610,
          endMinutes: 765,
          weekSet: '1-19',
        ),
      );
      final second = await repository.createCourse(
        CourseDraft(
          name: '数据库',
          semesterId: semester.id,
          teacher: '李老师',
          room: '305',
        ),
      );
      await repository.createSchedule(
        CourseScheduleDraft(
          courseId: second.id,
          weekday: DateTime.tuesday,
          startMinutes: 800,
          endMinutes: 850,
          weekSet: '1-19',
        ),
      );

      final snapshot = await WidgetSnapshotService(database).refresh(
        now: DateTime(2026, 8, 10, 8),
        notifyNative: false,
        snapshotDirectory: directory,
      );

      expect(snapshot['nextCourseTitle'], '离散数学');
      expect(snapshot['nextCourseTeacher'], '张老师');
      expect(snapshot['nextCourseRoom'], '203');
      final entries = snapshot['courseEntriesJson'] as String;
      expect(entries, contains('张老师'));
      expect(entries, contains('李老师'));
    },
  );

  test('background refresh writes a native-readable snapshot file', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp(
      'lifehub-widget-snapshot-',
    );
    addTearDown(database.close);
    addTearDown(() => directory.delete(recursive: true));
    await TaskRepository(
      database,
    ).create(TaskDraft(title: '后台刷新任务', dueAt: DateTime(2026, 8, 9, 18)));

    await WidgetSnapshotService(database).refresh(
      now: DateTime(2026, 8, 9, 12),
      notifyNative: false,
      snapshotDirectory: directory,
    );

    final file = File('${directory.path}/lifehub_widget_snapshot.json');
    expect(await file.exists(), isTrue);
    final snapshot = jsonDecode(await file.readAsString());
    expect(snapshot['taskCount'], 1);
    expect(snapshot['updatedAt'], isA<int>());
  });

  test(
    'privacy mode hides course and event details from widget snapshots',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'lifehub-widget-private-',
      );
      addTearDown(database.close);
      addTearDown(() => directory.delete(recursive: true));
      final repository = CourseRepository(database);
      final semester = await repository.createSemester(
        SemesterDraft(
          name: '隐私学期',
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 12, 20),
          totalWeeks: 19,
        ),
      );
      final course = await repository.createCourse(
        CourseDraft(
          name: '敏感课程',
          semesterId: semester.id,
          teacher: '敏感教师',
          room: '敏感教室',
        ),
      );
      await repository.createSchedule(
        CourseScheduleDraft(
          courseId: course.id,
          weekday: DateTime.monday,
          startMinutes: 610,
          endMinutes: 660,
          weekSet: '1-19',
        ),
      );

      final snapshot = await WidgetSnapshotService(database).refresh(
        now: DateTime(2026, 8, 10, 8),
        privacyMode: true,
        notifyNative: false,
        snapshotDirectory: directory,
      );

      expect(snapshot['nextCourseTitle'], '内容已隐藏');
      expect(snapshot.values.join(' '), isNot(contains('敏感课程')));
      expect(snapshot.values.join(' '), isNot(contains('敏感教师')));
      expect(snapshot.values.join(' '), isNot(contains('敏感教室')));
    },
  );

  test(
    'failed snapshot rename preserves the previous readable snapshot',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'widget-failure-',
      );
      addTearDown(database.close);
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/lifehub_widget_snapshot.json');
      await file.writeAsString('{"updatedAt":1,"taskCount":7}');
      final parentZone = Zone.current;
      await expectLater(
        IOOverrides.runZoned(
          () => WidgetSnapshotService(database).refresh(
            now: DateTime(2026, 10, 1),
            notifyNative: false,
            snapshotDirectory: directory,
          ),
          createFile: (path) {
            final real = parentZone.run(() => File(path));
            return path.contains('lifehub_widget_snapshot.json')
                ? _RenameFailure(real)
                : real;
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(jsonDecode(await file.readAsString())['taskCount'], 7);
      expect(
        await directory
            .list()
            .where((entity) => entity.path.endsWith('.tmp'))
            .toList(),
        isEmpty,
      );
    },
  );

  test('an older refresh cannot replace a newer published snapshot', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp('widget-stale-');
    addTearDown(database.close);
    addTearDown(() => directory.delete(recursive: true));
    final service = WidgetSnapshotService(database);
    final newer = DateTime(2026, 10, 2);
    await service.refresh(
      now: newer,
      notifyNative: false,
      snapshotDirectory: directory,
    );
    await service.refresh(
      now: DateTime(2026, 10, 1),
      notifyNative: false,
      snapshotDirectory: directory,
    );

    final file = File('${directory.path}/lifehub_widget_snapshot.json');
    expect(
      jsonDecode(await file.readAsString())['updatedAt'],
      newer.toUtc().millisecondsSinceEpoch,
    );
  });

  test(
    'separate isolates publish complete snapshots without shared temp files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'widget-isolates-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databasePath = '${directory.path}/data.sqlite';
      final database = AppDatabase.forTesting(
        NativeDatabase(File(databasePath)),
      );
      await database.customSelect('SELECT 1').get();
      await database.close();
      final newer = DateTime(2026, 10, 2).millisecondsSinceEpoch;
      await Future.wait([
        _refreshInWorker((databasePath, directory.path, newer)),
        _refreshInWorker((databasePath, directory.path, newer - 1000)),
      ]);

      final file = File('${directory.path}/lifehub_widget_snapshot.json');
      final snapshot = jsonDecode(await file.readAsString()) as Map;
      expect(snapshot['updatedAt'], newer);
      expect(snapshot['taskCount'], 0);
      expect(
        await directory
            .list()
            .where((entity) => entity.path.endsWith('.tmp'))
            .toList(),
        isEmpty,
      );
    },
  );
}

class _RenameFailure implements File {
  _RenameFailure(this.file);
  final File file;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      file.readAsString(encoding: encoding);
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => file.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
  @override
  Future<File> rename(String newPath) async =>
      throw FileSystemException('rename failure', path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _refreshInWorker((String, String, int) arguments) =>
    Isolate.run(() => _refreshIsolated(arguments));

Future<void> _refreshIsolated((String, String, int) arguments) async {
  final database = AppDatabase.forTesting(
    NativeDatabase(
      File(arguments.$1),
    ),
  );
  try {
    await WidgetSnapshotService(database).refresh(
      now: DateTime.fromMillisecondsSinceEpoch(arguments.$3),
      snapshotDirectory: Directory(arguments.$2),
      notifyNative: false,
    );
  } finally {
    await database.close();
  }
}
