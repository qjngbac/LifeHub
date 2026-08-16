import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/backup/encrypted_backup_codec.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/event/domain/recurrence.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ImportMode { replace, merge }

class BackupInspection {
  const BackupInspection({
    required this.schemaVersion,
    required this.exportedAt,
    required this.recordCounts,
  });

  final int schemaVersion;
  final DateTime? exportedAt;
  final Map<String, int> recordCounts;
}

class _AttachmentFileMutation {
  const _AttachmentFileMutation({
    required this.file,
    required this.existed,
    this.originalBytes,
  });

  final File file;
  final bool existed;
  final List<int>? originalBytes;

  Future<void> rollback() async {
    if (existed) {
      await file.writeAsBytes(originalBytes!, flush: true);
    } else if (await file.exists()) {
      await file.delete();
    }
  }
}

class _AttachmentRestoreResult {
  const _AttachmentRestoreResult(this.entries, this.mutations);

  final List<AttachmentEntry> entries;
  final List<_AttachmentFileMutation> mutations;

  Future<void> rollback() async {
    for (final mutation in mutations.reversed) {
      await mutation.rollback();
    }
  }
}

class BackupService {
  BackupService(this._database, {Directory? attachmentStorageRoot})
      : _attachmentStorageRoot = attachmentStorageRoot;
  final AppDatabase _database;
  final Directory? _attachmentStorageRoot;

  BackupInspection inspectJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['exportVersion'] != 1) {
      throw const FormatException('不支持的备份版本');
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema < 1 || schema > _database.schemaVersion) {
      throw FormatException('备份数据库版本不兼容：$schema');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('备份缺少 data');
    }
    final counts = <String, int>{};
    for (final entry in data.entries) {
      if (entry.value is List) counts[entry.key] = (entry.value as List).length;
    }
    final rawExportedAt = decoded['exportedAt'];
    final exportedAt = rawExportedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(
            rawExportedAt.toInt() * 1000,
            isUtc: true,
          )
        : DateTime.tryParse(rawExportedAt?.toString() ?? '');
    return BackupInspection(
      schemaVersion: schema,
      exportedAt: exportedAt,
      recordCounts: Map.unmodifiable(counts),
    );
  }

  Future<String> exportJson({bool includeAttachmentFiles = true}) async {
    final payload = <String, Object?>{
      'exportVersion': 1,
      'schemaVersion': _database.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': <String, Object?>{
        'tasks': (await _database.select(_database.tasks).get())
            .map((e) => e.toJson())
            .toList(),
        'projects': (await _database.select(_database.projects).get())
            .map((e) => e.toJson())
            .toList(),
        'events': (await _database.select(_database.events).get())
            .map((e) => e.toJson())
            .toList(),
        'semesters': (await _database.select(_database.semesters).get())
            .map((e) => e.toJson())
            .toList(),
        'courses': (await _database.select(_database.courses).get())
            .map((e) => e.toJson())
            .toList(),
        'courseSchedules':
            (await _database.select(_database.courseSchedules).get())
                .map((e) => e.toJson())
                .toList(),
        'lists': (await _database.select(_database.lists).get())
            .map((e) => e.toJson())
            .toList(),
        'listItems': (await _database.select(_database.listItems).get())
            .map((e) => e.toJson())
            .toList(),
        'habits': (await _database.select(_database.habits).get())
            .map((e) => e.toJson())
            .toList(),
        'habitLogs': (await _database.select(_database.habitLogs).get())
            .map((e) => e.toJson())
            .toList(),
        'relationshipProfiles':
            (await _database.select(_database.relationshipProfiles).get())
                .map((e) => e.toJson())
                .toList(),
        'moodLogs': (await _database.select(_database.moodLogs).get())
            .map((e) => e.toJson())
            .toList(),
        'lifeEvents': (await _database.select(_database.lifeEvents).get())
            .map((e) => e.toJson())
            .toList(),
        'cycleRecords': (await _database.select(_database.cycleRecords).get())
            .map((e) => e.toJson())
            .toList(),
        'anniversaries': (await _database.select(_database.anniversaries).get())
            .map((e) => e.toJson())
            .toList(),
        'goals': (await _database.select(_database.goals).get())
            .map((e) => e.toJson())
            .toList(),
        'milestones': (await _database.select(_database.milestones).get())
            .map((e) => e.toJson())
            .toList(),
        'entityLinks': (await _database.select(_database.entityLinks).get())
            .map((e) => e.toJson())
            .toList(),
        'focusSessions': (await _database.select(_database.focusSessions).get())
            .map((e) => e.toJson())
            .toList(),
        'reviews': (await _database.select(_database.reviews).get())
            .map((e) => e.toJson())
            .toList(),
        'inboxItems': (await _database.select(_database.inboxItems).get())
            .map((e) => e.toJson())
            .toList(),
        'automationRules':
            (await _database.select(_database.automationRules).get())
                .map((e) => e.toJson())
                .toList(),
        'automationRuns':
            (await _database.select(_database.automationRuns).get())
                .map((e) => e.toJson())
                .toList(),
        'savedItems': (await _database.select(_database.savedItems).get())
            .map((e) => e.toJson())
            .toList(),
        'attachments': (await _database.select(_database.attachments).get())
            .map((e) => e.toJson())
            .toList(),
        'attachmentLinks':
            (await _database.select(_database.attachmentLinks).get())
                .map((e) => e.toJson())
                .toList(),
        'locations': (await _database.select(_database.locations).get())
            .map((e) => e.toJson())
            .toList(),
        'tripProfiles': (await _database.select(_database.tripProfiles).get())
            .map((e) => e.toJson())
            .toList(),
        'tripExpenses': (await _database.select(_database.tripExpenses).get())
            .map((e) => e.toJson())
            .toList(),
        'weatherLocations':
            (await _database.select(_database.weatherLocations).get())
                .map((e) => e.toJson())
                .toList(),
        'weatherForecastCaches':
            (await _database.select(_database.weatherForecastCaches).get())
                .map((e) => e.toJson())
                .toList(),
        'eveningPrepItems':
            (await _database.select(_database.eveningPrepItems).get())
                .map((e) => e.toJson())
                .toList(),
        'householdItems':
            (await _database.select(_database.householdItems).get())
                .map((e) => e.toJson())
                .toList(),
        'medicationPlans':
            (await _database.select(_database.medicationPlans).get())
                .map((e) => e.toJson())
                .toList(),
        'medicationLogs':
            (await _database.select(_database.medicationLogs).get())
                .map((e) => e.toJson())
                .toList(),
        'emergencyCards':
            (await _database.select(_database.emergencyCards).get())
                .map((e) => e.toJson())
                .toList(),
        'financeEntries':
            (await _database.select(_database.financeEntries).get())
                .map((e) => e.toJson())
                .toList(),
        'credentialRecords':
            (await _database.select(_database.credentialRecords).get())
                .map((e) => e.toJson())
                .toList(),
        'mediaSeries': (await _database.select(_database.mediaSeries).get())
            .map((e) => e.toJson())
            .toList(),
        'mediaEntries': (await _database.select(_database.mediaEntries).get())
            .map((e) => e.toJson())
            .toList(),
        'courseGrades': (await _database.select(_database.courseGrades).get())
            .map((e) => e.toJson())
            .toList(),
        'subscriptions': (await _database.select(_database.subscriptions).get())
            .map((e) => e.toJson())
            .toList(),
        'maintenancePlans':
            (await _database.select(_database.maintenancePlans).get())
                .map((e) => e.toJson())
                .toList(),
        'maintenanceLogs':
            (await _database.select(_database.maintenanceLogs).get())
                .map((e) => e.toJson())
                .toList(),
        'readingItems': (await _database.select(_database.readingItems).get())
            .map((e) => e.toJson())
            .toList(),
        'parcels': (await _database.select(_database.parcels).get())
            .map((e) => e.toJson())
            .toList(),
        'tags': (await _database.select(_database.tags).get())
            .map((e) => e.toJson())
            .toList(),
        'entityTags': (await _database.select(_database.entityTags).get())
            .map((e) => e.toJson())
            .toList(),
        'reminders': (await _database.select(_database.reminders).get())
            .map((e) => e.toJson())
            .toList(),
        'moduleConfigs': (await _database.select(_database.moduleConfigs).get())
            .map((e) => e.toJson())
            .toList(),
        'changeLogs': (await _database.select(_database.changeLogs).get())
            .map((e) => e.toJson())
            .toList(),
        'attachmentFiles': includeAttachmentFiles
            ? await _attachmentFilePayload()
            : <Map<String, Object?>>[],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<String> exportEncryptedJson(
    String password, {
    bool includeAttachmentFiles = true,
    EncryptedBackupCodec? codec,
  }) async {
    final clear =
        await exportJson(includeAttachmentFiles: includeAttachmentFiles);
    return (codec ?? EncryptedBackupCodec()).encrypt(clear, password);
  }

  Future<void> importEncryptedJson(
    String source,
    String password, {
    ImportMode mode = ImportMode.replace,
    EncryptedBackupCodec? codec,
  }) async {
    final clear = await (codec ?? EncryptedBackupCodec()).decrypt(
      source,
      password,
    );
    inspectJson(clear);
    await importJson(clear, mode: mode);
  }

  Future<List<Map<String, Object?>>> _attachmentFilePayload() async {
    final values = await (_database.select(_database.attachments)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final result = <Map<String, Object?>>[];
    for (final value in values) {
      final file = File(value.storedPath);
      if (!await file.exists()) continue;
      result.add({
        'attachmentId': value.id,
        'fileName': p.basename(value.storedPath),
        'contentBase64': base64Encode(await file.readAsBytes()),
      });
    }
    return result;
  }

  Future<File> exportToFile({bool includeAttachmentFiles = true}) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'lifehub_backups'));
    await directory.create(recursive: true);
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name = 'lifehub_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    final file = File(p.join(directory.path, name));
    return file.writeAsString(
      await exportJson(includeAttachmentFiles: includeAttachmentFiles),
      flush: true,
    );
  }

  Future<bool> exportWithPicker({bool includeAttachmentFiles = true}) async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final kind = includeAttachmentFiles ? '' : '_data';
    final name = 'lifehub${kind}_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存 LifeHub 备份',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(
        await exportJson(includeAttachmentFiles: includeAttachmentFiles),
      )),
    );
    return path != null;
  }

  Future<bool> exportEncryptedWithPicker(
    String password, {
    bool includeAttachmentFiles = true,
  }) async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name = 'lifehub_secure_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.lifehubx';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存 LifeHub 加密备份',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['lifehubx'],
      bytes: Uint8List.fromList(utf8.encode(await exportEncryptedJson(
        password,
        includeAttachmentFiles: includeAttachmentFiles,
      ))),
    );
    return path != null;
  }

  Future<String?> pickBackupJson() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LifeHub JSON 备份',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes != null) return utf8.decode(file.bytes!);
    if (file.path != null) return File(file.path!).readAsString();
    throw const FileSystemException('无法读取所选备份');
  }

  Future<String?> pickBackupText() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LifeHub 备份',
      type: FileType.custom,
      allowedExtensions: const ['json', 'lifehubx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes != null) return utf8.decode(file.bytes!);
    if (file.path != null) return File(file.path!).readAsString();
    throw const FileSystemException('无法读取所选备份');
  }

  Future<List<File>> backupFiles() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'lifehub_backups'));
    if (!await directory.exists()) return [];
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> importFile(File file) async =>
      importJson(await file.readAsString());

  Future<void> importJson(
    String source, {
    ImportMode mode = ImportMode.replace,
  }) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['exportVersion'] != 1) {
      throw const FormatException('不支持的备份版本');
    }
    final backupSchema = decoded['schemaVersion'];
    if (backupSchema is! int ||
        backupSchema < 1 ||
        backupSchema > _database.schemaVersion) {
      throw FormatException(
        '备份数据库版本不兼容：${decoded['schemaVersion']}',
      );
    }
    final rawData = decoded['data'];
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('备份缺少 data');
    }
    List<Map<String, dynamic>> rows(String key) {
      final value = rawData[key];
      if (value is! List) throw FormatException('备份缺少 $key');
      return value.map((row) {
        if (row is! Map) throw FormatException('$key 包含无效记录');
        return Map<String, dynamic>.from(row);
      }).toList();
    }

    List<Map<String, dynamic>> versionedRows(String key, int introducedIn) {
      final value = rawData[key];
      if (value == null && backupSchema < introducedIn) return const [];
      return rows(key);
    }

    List<Map<String, dynamic>> optionalRows(String key) {
      if (rawData[key] == null) return const [];
      return rows(key);
    }

    List<Map<String, dynamic>> compatibleRows(String key) {
      final values = rows(key);
      if (backupSchema > 2) return values;
      return values.map((row) => _normalizeLegacyV1Row(key, row)).toList();
    }

    List<Map<String, dynamic>> rowsWithArchiveState(String key) {
      final values = compatibleRows(key);
      if (backupSchema >= 3) return values;
      return values.map((row) {
        final normalized = Map<String, dynamic>.from(row);
        final legacyArchived = normalized['deletedAt'] != null;
        normalized['archived'] = legacyArchived;
        if (legacyArchived) normalized['deletedAt'] = null;
        return normalized;
      }).toList();
    }

    List<Map<String, dynamic>> withV9Defaults(
      String key,
      List<Map<String, dynamic>> values,
    ) {
      if (backupSchema >= 9) return values;
      return values.map((value) {
        final row = Map<String, dynamic>.from(value);
        switch (key) {
          case 'events':
            row['preparationMinutes'] ??= 0;
            row['travelMinutes'] ??= 0;
            row['departureReminderEnabled'] ??= false;
          case 'householdItems':
            row['itemKind'] ??= 'DURABLE';
            row['quantity'] = (row['quantity'] as num? ?? 1).toDouble();
          case 'reminders':
            row['reminderKind'] ??= 'DEFAULT';
        }
        return row;
      }).toList();
    }

    List<Map<String, dynamic>> withV10EmergencyCardDefaults(
      List<Map<String, dynamic>> values,
    ) {
      if (backupSchema >= 10) return values;
      return values.map((value) {
        final row = Map<String, dynamic>.from(value);
        final year = row.remove('birthYear');
        row['birthDate'] = year is num ? year.toInt() * 10000 + 101 : null;
        return row;
      }).toList();
    }

    List<Map<String, dynamic>> withV11FocusDefaults(
      List<Map<String, dynamic>> values,
    ) {
      if (backupSchema >= 11) return values;
      return values.map((value) {
        final row = Map<String, dynamic>.from(value);
        row['mode'] ??= 'COUNTDOWN';
        return row;
      }).toList();
    }

    final tasks = compatibleRows('tasks').map(TaskEntry.fromJson).toList();
    final projects =
        compatibleRows('projects').map(ProjectEntry.fromJson).toList();
    final events = withV9Defaults(
      'events',
      rowsWithArchiveState('events'),
    ).map(EventEntry.fromJson).toList();
    final semesters =
        compatibleRows('semesters').map(SemesterEntry.fromJson).toList();
    final courses =
        compatibleRows('courses').map(CourseEntry.fromJson).toList();
    final schedules = rowsWithArchiveState('courseSchedules')
        .map(CourseScheduleEntry.fromJson)
        .toList();
    final lists = compatibleRows('lists').map(ListEntry.fromJson).toList();
    final listItems =
        compatibleRows('listItems').map(ListItemEntry.fromJson).toList();
    final habits = compatibleRows('habits').map(HabitEntry.fromJson).toList();
    final habitLogs =
        compatibleRows('habitLogs').map(HabitLogEntry.fromJson).toList();
    final relationships = versionedRows('relationshipProfiles', 2)
        .map(RelationshipProfileEntry.fromJson)
        .toList();
    final moodLogs =
        versionedRows('moodLogs', 2).map(MoodLogEntry.fromJson).toList();
    final lifeEvents =
        versionedRows('lifeEvents', 2).map(LifeEventEntry.fromJson).toList();
    final cycleRecords = versionedRows('cycleRecords', 2)
        .map(CycleRecordEntry.fromJson)
        .toList();
    final anniversaries = versionedRows('anniversaries', 2)
        .map(AnniversaryEntry.fromJson)
        .toList();
    final goals = versionedRows('goals', 4).map(GoalEntry.fromJson).toList();
    final milestones =
        versionedRows('milestones', 4).map(MilestoneEntry.fromJson).toList();
    final entityLinks =
        versionedRows('entityLinks', 4).map(EntityLinkEntry.fromJson).toList();
    final focusSessions = withV11FocusDefaults(
      versionedRows('focusSessions', 4),
    ).map(FocusSessionEntry.fromJson).toList();
    final reviews =
        versionedRows('reviews', 4).map(ReviewEntry.fromJson).toList();
    final inboxItems =
        versionedRows('inboxItems', 5).map(InboxItemEntry.fromJson).toList();
    final automationRules = versionedRows('automationRules', 5)
        .map(AutomationRuleEntry.fromJson)
        .toList();
    final automationRuns = versionedRows('automationRuns', 5)
        .map(AutomationRunEntry.fromJson)
        .toList();
    final savedItems =
        versionedRows('savedItems', 6).map(SavedItemEntry.fromJson).toList();
    final attachments =
        versionedRows('attachments', 6).map(AttachmentEntry.fromJson).toList();
    final attachmentLinks = versionedRows('attachmentLinks', 6)
        .map(AttachmentLinkEntry.fromJson)
        .toList();
    final locations =
        versionedRows('locations', 6).map(LocationEntry.fromJson).toList();
    final tripProfiles = versionedRows('tripProfiles', 6)
        .map(TripProfileEntry.fromJson)
        .toList();
    final tripExpenses = versionedRows('tripExpenses', 6)
        .map(TripExpenseEntry.fromJson)
        .toList();
    final weatherLocations = versionedRows('weatherLocations', 7)
        .map(WeatherLocationEntry.fromJson)
        .toList();
    final weatherForecastCaches = versionedRows('weatherForecastCaches', 7)
        .map(WeatherForecastCacheEntry.fromJson)
        .toList();
    final eveningPrepItems = versionedRows('eveningPrepItems', 7)
        .map(EveningPrepItemEntry.fromJson)
        .toList();
    final householdItems = withV9Defaults(
      'householdItems',
      versionedRows('householdItems', 7),
    ).map(HouseholdItemEntry.fromJson).toList();
    final medicationPlans = versionedRows('medicationPlans', 7)
        .map(MedicationPlanEntry.fromJson)
        .toList();
    final medicationLogs = versionedRows('medicationLogs', 7)
        .map(MedicationLogEntry.fromJson)
        .toList();
    final emergencyCards = withV10EmergencyCardDefaults(
      versionedRows('emergencyCards', 7),
    ).map(EmergencyCardEntry.fromJson).toList();
    final financeEntries =
        versionedRows('financeEntries', 7).map(FinanceEntry.fromJson).toList();
    final credentialRecords = versionedRows('credentialRecords', 7)
        .map(CredentialRecordEntry.fromJson)
        .toList();
    final mediaSeries =
        versionedRows('mediaSeries', 8).map(MediaSeriesEntry.fromJson).toList();
    final mediaEntries =
        versionedRows('mediaEntries', 8).map(MediaEntry.fromJson).toList();
    final courseGrades = versionedRows('courseGrades', 9)
        .map(CourseGradeEntry.fromJson)
        .toList();
    final subscriptions = versionedRows('subscriptions', 9)
        .map(SubscriptionEntry.fromJson)
        .toList();
    final maintenancePlans = versionedRows('maintenancePlans', 9)
        .map(MaintenancePlanEntry.fromJson)
        .toList();
    final maintenanceLogs = versionedRows('maintenanceLogs', 9)
        .map(MaintenanceLogEntry.fromJson)
        .toList();
    final readingItems = versionedRows('readingItems', 9)
        .map(ReadingItemEntry.fromJson)
        .toList();
    final parcels =
        versionedRows('parcels', 9).map(ParcelEntry.fromJson).toList();
    final attachmentFiles = versionedRows('attachmentFiles', 6);
    final tags = compatibleRows('tags').map(TagEntry.fromJson).toList();
    final entityTags = rows('entityTags').map(EntityTagEntry.fromJson).toList();
    final reminders = withV9Defaults(
      'reminders',
      optionalRows('reminders'),
    ).map(ReminderEntry.fromJson).toList();
    final configs =
        optionalRows('moduleConfigs').map(ModuleConfigEntry.fromJson).toList();
    final changeLogs =
        optionalRows('changeLogs').map(ChangeLogEntry.fromJson).toList();
    for (final value in changeLogs) {
      _requiredText('changeLogs.entityType', value.entityType);
      _requiredText('changeLogs.entityId', value.entityId);
      _requiredText('changeLogs.operation', value.operation);
      if (value.createdAt < 0) throw const FormatException('审计日志时间无效');
    }

    _validateBackup(
      tasks: tasks,
      projects: projects,
      events: events,
      semesters: semesters,
      courses: courses,
      schedules: schedules,
      lists: lists,
      listItems: listItems,
      habits: habits,
      habitLogs: habitLogs,
      relationships: relationships,
      moodLogs: moodLogs,
      lifeEvents: lifeEvents,
      cycleRecords: cycleRecords,
      anniversaries: anniversaries,
      goals: goals,
      milestones: milestones,
      entityLinks: entityLinks,
      focusSessions: focusSessions,
      reviews: reviews,
      inboxItems: inboxItems,
      automationRules: automationRules,
      automationRuns: automationRuns,
      savedItems: savedItems,
      attachments: attachments,
      attachmentLinks: attachmentLinks,
      locations: locations,
      tripProfiles: tripProfiles,
      tripExpenses: tripExpenses,
      weatherLocations: weatherLocations,
      weatherForecastCaches: weatherForecastCaches,
      eveningPrepItems: eveningPrepItems,
      householdItems: householdItems,
      medicationPlans: medicationPlans,
      medicationLogs: medicationLogs,
      emergencyCards: emergencyCards,
      financeEntries: financeEntries,
      credentialRecords: credentialRecords,
      mediaSeries: mediaSeries,
      mediaEntries: mediaEntries,
      courseGrades: courseGrades,
      subscriptions: subscriptions,
      maintenancePlans: maintenancePlans,
      maintenanceLogs: maintenanceLogs,
      readingItems: readingItems,
      parcels: parcels,
      attachmentFiles: attachmentFiles,
      tags: tags,
      entityTags: entityTags,
      reminders: reminders,
      configs: configs,
    );

    Future<void> pruneMergeRows() async {
      await _removeStaleMergeRows(_database.projects.actualTableName, projects);
      await _removeStaleMergeRows(_database.tasks.actualTableName, tasks);
      await _removeStaleMergeRows(_database.events.actualTableName, events);
      await _removeStaleMergeRows(
          _database.semesters.actualTableName, semesters);
      await _removeStaleMergeRows(_database.courses.actualTableName, courses);
      await _removeStaleMergeRows(
          _database.courseSchedules.actualTableName, schedules);
      await _removeStaleMergeRows(_database.lists.actualTableName, lists);
      await _removeStaleMergeRows(
          _database.listItems.actualTableName, listItems);
      await _removeStaleMergeRows(_database.habits.actualTableName, habits);
      await _removeStaleMergeRows(
          _database.habitLogs.actualTableName, habitLogs);
      await _removeStaleMergeRows(
          _database.relationshipProfiles.actualTableName, relationships);
      await _removeStaleMergeRows(_database.moodLogs.actualTableName, moodLogs);
      await _removeStaleMergeRows(
          _database.lifeEvents.actualTableName, lifeEvents);
      await _removeStaleMergeRows(
          _database.cycleRecords.actualTableName, cycleRecords);
      await _removeStaleMergeRows(
          _database.anniversaries.actualTableName, anniversaries);
      await _removeStaleMergeRows(_database.goals.actualTableName, goals);
      await _removeStaleMergeRows(
          _database.milestones.actualTableName, milestones);
      await _removeStaleMergeRows(
          _database.entityLinks.actualTableName, entityLinks);
      await _removeStaleMergeRows(
          _database.focusSessions.actualTableName, focusSessions);
      await _removeStaleMergeRows(_database.reviews.actualTableName, reviews);
      await _removeStaleMergeRows(
          _database.inboxItems.actualTableName, inboxItems);
      await _removeStaleMergeRows(
          _database.automationRules.actualTableName, automationRules);
      await _removeStaleMergeRows(
          _database.automationRuns.actualTableName, automationRuns);
      await _removeStaleMergeRows(
          _database.savedItems.actualTableName, savedItems);
      await _removeStaleMergeRows(
          _database.attachments.actualTableName, attachments);
      await _removeStaleMergeRows(
          _database.attachmentLinks.actualTableName, attachmentLinks);
      await _removeStaleMergeRows(
          _database.locations.actualTableName, locations);
      await _removeStaleMergeRows(
          _database.tripProfiles.actualTableName, tripProfiles);
      await _removeStaleMergeRows(
          _database.tripExpenses.actualTableName, tripExpenses);
      await _removeStaleMergeRows(
          _database.weatherLocations.actualTableName, weatherLocations);
      await _removeStaleMergeRows(
          _database.weatherForecastCaches.actualTableName,
          weatherForecastCaches);
      await _removeStaleMergeRows(
          _database.eveningPrepItems.actualTableName, eveningPrepItems);
      await _removeStaleMergeRows(
          _database.householdItems.actualTableName, householdItems);
      await _removeStaleMergeRows(
          _database.medicationPlans.actualTableName, medicationPlans);
      await _removeStaleMergeRows(
          _database.medicationLogs.actualTableName, medicationLogs);
      await _removeStaleMergeRows(
          _database.emergencyCards.actualTableName, emergencyCards);
      await _removeStaleMergeRows(
          _database.financeEntries.actualTableName, financeEntries);
      await _removeStaleMergeRows(
          _database.credentialRecords.actualTableName, credentialRecords);
      await _removeStaleMergeRows(
          _database.mediaSeries.actualTableName, mediaSeries);
      await _removeStaleMergeRows(
          _database.mediaEntries.actualTableName, mediaEntries);
      await _removeStaleMergeRows(
          _database.courseGrades.actualTableName, courseGrades);
      await _removeStaleMergeRows(
          _database.subscriptions.actualTableName, subscriptions);
      await _removeStaleMergeRows(
          _database.maintenancePlans.actualTableName, maintenancePlans);
      await _removeStaleMergeRows(
          _database.maintenanceLogs.actualTableName, maintenanceLogs);
      await _removeStaleMergeRows(
          _database.readingItems.actualTableName, readingItems);
      await _removeStaleMergeRows(_database.parcels.actualTableName, parcels);
      await _removeStaleMergeRows(_database.tags.actualTableName, tags);
      await _removeStaleMergeRows(
          _database.reminders.actualTableName, reminders);
      await _removeStaleConfigs(configs);
    }

    final previousAttachmentPaths = mode == ImportMode.replace
        ? (await _database.select(_database.attachments).get())
            .map((value) => value.storedPath)
            .toList()
        : const <String>[];
    var attachmentRestore = const _AttachmentRestoreResult([], []);
    var restoredAttachments = <AttachmentEntry>[];

    try {
      await _database.transaction(() async {
        if (mode == ImportMode.merge) await pruneMergeRows();
        attachmentRestore =
            await _restoreAttachmentPayload(attachments, attachmentFiles);
        restoredAttachments = attachmentRestore.entries;
        if (mode == ImportMode.replace) {
          await _database.delete(_database.maintenanceLogs).go();
          await _database.delete(_database.courseGrades).go();
          await _database.delete(_database.maintenancePlans).go();
          await _database.delete(_database.subscriptions).go();
          await _database.delete(_database.readingItems).go();
          await _database.delete(_database.parcels).go();
          await _database.delete(_database.mediaEntries).go();
          await _database.delete(_database.mediaSeries).go();
          await _database.delete(_database.medicationLogs).go();
          await _database.delete(_database.weatherForecastCaches).go();
          await _database.delete(_database.eveningPrepItems).go();
          await _database.delete(_database.financeEntries).go();
          await _database.delete(_database.credentialRecords).go();
          await _database.delete(_database.emergencyCards).go();
          await _database.delete(_database.medicationPlans).go();
          await _database.delete(_database.householdItems).go();
          await _database.delete(_database.weatherLocations).go();
          await _database.delete(_database.attachmentLinks).go();
          await _database.delete(_database.tripExpenses).go();
          await _database.delete(_database.tripProfiles).go();
          await _database.delete(_database.entityLinks).go();
          await _database.delete(_database.milestones).go();
          await _database.delete(_database.automationRuns).go();
          await _database.delete(_database.focusSessions).go();
          await _database.delete(_database.reviews).go();
          await _database.delete(_database.inboxItems).go();
          await _database.delete(_database.automationRules).go();
          await _database.delete(_database.savedItems).go();
          await _database.delete(_database.attachments).go();
          await _database.delete(_database.locations).go();
          await _database.delete(_database.goals).go();
          await _database.delete(_database.entityTags).go();
          await _database.delete(_database.cycleRecords).go();
          await _database.delete(_database.moodLogs).go();
          await _database.delete(_database.lifeEvents).go();
          await _database.delete(_database.anniversaries).go();
          await _database.delete(_database.habitLogs).go();
          await _database.delete(_database.listItems).go();
          await _database.delete(_database.courseSchedules).go();
          await _database.delete(_database.reminders).go();
          await _database.delete(_database.tags).go();
          await _database.delete(_database.habits).go();
          await _database.delete(_database.lists).go();
          await _database.delete(_database.courses).go();
          await _database.delete(_database.semesters).go();
          await _database.delete(_database.events).go();
          await _database.delete(_database.tasks).go();
          await _database.delete(_database.projects).go();
          await _database.delete(_database.relationshipProfiles).go();
          await _database.delete(_database.moduleConfigs).go();
          await _database.delete(_database.changeLogs).go();
        }
        final insertMode = mode == ImportMode.merge
            ? InsertMode.insertOrReplace
            : InsertMode.insert;
        for (final value in projects) {
          await _database
              .into(_database.projects)
              .insert(value, mode: insertMode);
        }
        for (final value in tasks) {
          await _database.into(_database.tasks).insert(value, mode: insertMode);
        }
        for (final value in events) {
          await _database
              .into(_database.events)
              .insert(value, mode: insertMode);
        }
        for (final value in semesters) {
          await _database
              .into(_database.semesters)
              .insert(value, mode: insertMode);
        }
        for (final value in courses) {
          await _database
              .into(_database.courses)
              .insert(value, mode: insertMode);
        }
        for (final value in courseGrades) {
          await _database
              .into(_database.courseGrades)
              .insert(value, mode: insertMode);
        }
        for (final value in schedules) {
          await _database
              .into(_database.courseSchedules)
              .insert(value, mode: insertMode);
        }
        for (final value in lists) {
          await _database.into(_database.lists).insert(value, mode: insertMode);
        }
        for (final value in listItems) {
          await _database
              .into(_database.listItems)
              .insert(value, mode: insertMode);
        }
        for (final value in habits) {
          await _database
              .into(_database.habits)
              .insert(value, mode: insertMode);
        }
        for (final value in habitLogs) {
          await _database
              .into(_database.habitLogs)
              .insert(value, mode: insertMode);
        }
        for (final value in relationships) {
          await _database
              .into(_database.relationshipProfiles)
              .insert(value, mode: insertMode);
        }
        for (final value in moodLogs) {
          await _database
              .into(_database.moodLogs)
              .insert(value, mode: insertMode);
        }
        for (final value in lifeEvents) {
          await _database
              .into(_database.lifeEvents)
              .insert(value, mode: insertMode);
        }
        for (final value in cycleRecords) {
          await _database
              .into(_database.cycleRecords)
              .insert(value, mode: insertMode);
        }
        for (final value in anniversaries) {
          await _database
              .into(_database.anniversaries)
              .insert(value, mode: insertMode);
        }
        for (final value in goals) {
          await _database.into(_database.goals).insert(value, mode: insertMode);
        }
        for (final value in milestones) {
          await _database
              .into(_database.milestones)
              .insert(value, mode: insertMode);
        }
        for (final value in entityLinks) {
          await _database
              .into(_database.entityLinks)
              .insert(value, mode: insertMode);
        }
        for (final value in focusSessions) {
          await _database
              .into(_database.focusSessions)
              .insert(value, mode: insertMode);
        }
        for (final value in reviews) {
          await _database
              .into(_database.reviews)
              .insert(value, mode: insertMode);
        }
        for (final value in inboxItems) {
          await _database
              .into(_database.inboxItems)
              .insert(value, mode: insertMode);
        }
        for (final value in automationRules) {
          await _database
              .into(_database.automationRules)
              .insert(value, mode: insertMode);
        }
        for (final value in automationRuns) {
          await _database
              .into(_database.automationRuns)
              .insert(value, mode: insertMode);
        }
        for (final value in savedItems) {
          await _database
              .into(_database.savedItems)
              .insert(value, mode: insertMode);
        }
        for (final value in locations) {
          await _database
              .into(_database.locations)
              .insert(value, mode: insertMode);
        }
        for (final value in restoredAttachments) {
          await _database
              .into(_database.attachments)
              .insert(value, mode: insertMode);
        }
        for (final value in attachmentLinks) {
          await _database
              .into(_database.attachmentLinks)
              .insert(value, mode: insertMode);
        }
        for (final value in tripProfiles) {
          await _database
              .into(_database.tripProfiles)
              .insert(value, mode: insertMode);
        }
        for (final value in tripExpenses) {
          await _database
              .into(_database.tripExpenses)
              .insert(value, mode: insertMode);
        }
        for (final value in weatherLocations) {
          await _database
              .into(_database.weatherLocations)
              .insert(value, mode: insertMode);
        }
        for (final value in weatherForecastCaches) {
          await _database
              .into(_database.weatherForecastCaches)
              .insert(value, mode: insertMode);
        }
        for (final value in eveningPrepItems) {
          await _database
              .into(_database.eveningPrepItems)
              .insert(value, mode: insertMode);
        }
        for (final value in householdItems) {
          await _database
              .into(_database.householdItems)
              .insert(value, mode: insertMode);
        }
        for (final value in maintenancePlans) {
          await _database
              .into(_database.maintenancePlans)
              .insert(value, mode: insertMode);
        }
        for (final value in maintenanceLogs) {
          await _database
              .into(_database.maintenanceLogs)
              .insert(value, mode: insertMode);
        }
        for (final value in medicationPlans) {
          await _database
              .into(_database.medicationPlans)
              .insert(value, mode: insertMode);
        }
        for (final value in medicationLogs) {
          await _database
              .into(_database.medicationLogs)
              .insert(value, mode: insertMode);
        }
        for (final value in emergencyCards) {
          await _database
              .into(_database.emergencyCards)
              .insert(value, mode: insertMode);
        }
        for (final value in financeEntries) {
          await _database
              .into(_database.financeEntries)
              .insert(value, mode: insertMode);
        }
        for (final value in subscriptions) {
          await _database
              .into(_database.subscriptions)
              .insert(value, mode: insertMode);
        }
        for (final value in credentialRecords) {
          await _database
              .into(_database.credentialRecords)
              .insert(value, mode: insertMode);
        }
        for (final value in mediaSeries) {
          await _database
              .into(_database.mediaSeries)
              .insert(value, mode: insertMode);
        }
        for (final value in mediaEntries) {
          await _database
              .into(_database.mediaEntries)
              .insert(value, mode: insertMode);
        }
        for (final value in readingItems) {
          await _database
              .into(_database.readingItems)
              .insert(value, mode: insertMode);
        }
        for (final value in parcels) {
          await _database
              .into(_database.parcels)
              .insert(value, mode: insertMode);
        }
        for (final value in tags) {
          await _database.into(_database.tags).insert(value, mode: insertMode);
        }
        for (final value in entityTags) {
          await _database.into(_database.entityTags).insert(
                value,
                mode: mode == ImportMode.merge
                    ? InsertMode.insertOrIgnore
                    : insertMode,
              );
        }
        for (final value in reminders) {
          await _database
              .into(_database.reminders)
              .insert(value, mode: insertMode);
        }
        for (final value in configs) {
          await _database
              .into(_database.moduleConfigs)
              .insert(value, mode: insertMode);
        }
        for (final value in changeLogs) {
          if (mode == ImportMode.replace) {
            await _database.into(_database.changeLogs).insert(value);
            continue;
          }
          final duplicate = await (_database.select(_database.changeLogs)
                ..where((row) =>
                    row.entityType.equals(value.entityType) &
                    row.entityId.equals(value.entityId) &
                    row.operation.equals(value.operation) &
                    row.createdAt.equals(value.createdAt)))
              .getSingleOrNull();
          if (duplicate == null) {
            await _database.into(_database.changeLogs).insert(
                  ChangeLogsCompanion.insert(
                    entityType: value.entityType,
                    entityId: value.entityId,
                    operation: value.operation,
                    payloadHash: Value(value.payloadHash),
                    createdAt: Value(value.createdAt),
                  ),
                );
          }
        }
      });
    } catch (_) {
      await attachmentRestore.rollback();
      rethrow;
    }
    if (mode == ImportMode.replace) {
      await _removeReplacedAttachmentFiles(
        previousAttachmentPaths,
        restoredAttachments.map((value) => value.storedPath).toSet(),
      );
    }
  }

  Future<Directory> _attachmentRoot() async =>
      _attachmentStorageRoot ??
      Directory(p.join(
        (await getApplicationDocumentsDirectory()).path,
        'lifehub_attachments',
      ));

  Future<void> _removeReplacedAttachmentFiles(
    List<String> previousPaths,
    Set<String> retainedPaths,
  ) async {
    if (previousPaths.isEmpty) return;
    final root = (await _attachmentRoot()).absolute.path;
    for (final path in previousPaths) {
      final file = File(path);
      final absolute = file.absolute.path;
      if (retainedPaths.contains(path) ||
          !(p.equals(root, absolute) || p.isWithin(root, absolute))) {
        continue;
      }
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _removeStaleMergeRows<T>(
    String table,
    List<T> values,
  ) async {
    final retained = <T>[];
    for (final value in values) {
      final json = (value as dynamic).toJson() as Map<String, dynamic>;
      final id = json['id'] as String;
      final updatedAt = json['updatedAt'] as int;
      final existing = await _database.customSelect(
        'SELECT updated_at FROM "$table" WHERE id = ? LIMIT 1',
        variables: [Variable<String>(id)],
      ).getSingleOrNull();
      final existingUpdatedAt = existing?.read<int>('updated_at');
      if (existingUpdatedAt == null || updatedAt >= existingUpdatedAt) {
        retained.add(value);
      }
    }
    values
      ..clear()
      ..addAll(retained);
  }

  Future<void> _removeStaleConfigs(List<ModuleConfigEntry> values) async {
    final retained = <ModuleConfigEntry>[];
    for (final value in values) {
      final existing = await (_database.select(_database.moduleConfigs)
            ..where((row) => row.key.equals(value.key)))
          .getSingleOrNull();
      if (existing == null || value.updatedAt >= existing.updatedAt) {
        retained.add(value);
      }
    }
    values
      ..clear()
      ..addAll(retained);
  }

  Map<String, dynamic> _normalizeLegacyV1Row(
    String table,
    Map<String, dynamic> source,
  ) {
    final row = Map<String, dynamic>.from(source);

    void addSyncDefaults() {
      row['createdAt'] ??= 0;
      row['updatedAt'] ??= row['createdAt'];
      row['version'] ??= 1;
      row['syncState'] ??= 0;
      row['metadata'] = _normalizedMetadata(row['metadata']);
    }

    switch (table) {
      case 'tasks':
        addSyncDefaults();
        row['category'] ??= 'STUDY';
        row['status'] ??= 'TODO';
        row['priority'] ??= 0;
        row['sortKey'] = (row['sortKey'] as num? ?? 0).toDouble();
        break;
      case 'projects':
        addSyncDefaults();
        final progressMode = row['progressMode'];
        if (progressMode is num) {
          row['progressMode'] =
              progressMode.toInt() == 1 ? 'MANUAL' : 'AUTO_TASK';
        }
        row['progressMode'] ??= 'AUTO_TASK';
        final manualProgress = row['manualProgress'];
        if (manualProgress is num) {
          row['manualProgress'] = manualProgress.toDouble();
        }
        break;
      case 'events':
        addSyncDefaults();
        row['timezoneId'] ??= 'Asia/Shanghai';
        row['location'] ??= row.remove('locationId');
        row['archived'] ??= false;
        break;
      case 'semesters':
        addSyncDefaults();
        row['startDate'] = _legacyDateKey(row['startDate']);
        row['endDate'] = _legacyDateKey(row['endDate']);
        row['totalWeeks'] ??= 16;
        row.remove('currentWeek');
        break;
      case 'courses':
        addSyncDefaults();
        break;
      case 'courseSchedules':
        addSyncDefaults();
        row['startMinutes'] ??= _legacyClockMinutes(row.remove('startTime'));
        row['endMinutes'] ??= _legacyClockMinutes(row.remove('endTime'));
        row['weekSet'] ??= '1-16';
        row['excludedDates'] ??= '[]';
        row['reminderMinutes'] ??= row.remove('reminder');
        row['archived'] ??= false;
        break;
      case 'lists':
        addSyncDefaults();
        row['title'] ??= row.remove('name');
        row['listType'] ??= 'GENERAL';
        row['archived'] ??= false;
        row['template'] ??= false;
        break;
      case 'listItems':
        addSyncDefaults();
        row['textValue'] ??= row.remove('text');
        row['checked'] ??= false;
        row['quantity'] = (row['quantity'] as num? ?? 1).toDouble();
        row['sortKey'] = (row['sortKey'] as num? ?? 0).toDouble();
        break;
      case 'habits':
        addSyncDefaults();
        final reminder = row['reminderPolicy'];
        if (reminder is num) {
          row['reminderPolicy'] =
              reminder.toInt() <= 0 ? null : _legacyClockText(reminder.toInt());
        }
        row['scheduleRule'] ??= 'DAILY';
        row['targetCount'] ??= 1;
        row['active'] ??= true;
        break;
      case 'habitLogs':
        addSyncDefaults();
        row['value'] ??= 1;
        row['status'] ??= 'DONE';
        break;
      case 'tags':
        addSyncDefaults();
        row['color'] ??= '#6750A4';
        break;
    }
    return row;
  }

  String _normalizedMetadata(Object? value) {
    if (value is String) {
      try {
        if (jsonDecode(value) is Map) return value;
      } on FormatException {
        // Invalid legacy metadata is discarded instead of blocking all data.
      }
    }
    return '{}';
  }

  int? _legacyDateKey(Object? value) {
    if (value is! num) return null;
    final number = value.toInt();
    if (number >= 10000101 && number <= 99991231) return number;
    final date =
        DateTime.fromMillisecondsSinceEpoch(number, isUtc: true).toLocal();
    return date.year * 10000 + date.month * 100 + date.day;
  }

  int? _legacyClockMinutes(Object? value) {
    if (value is! num) return null;
    final clock = value.toInt();
    final hour = clock ~/ 100;
    final minute = clock % 100;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String? _legacyClockText(int clock) {
    final minutes = _legacyClockMinutes(clock);
    if (minutes == null) return null;
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<_AttachmentRestoreResult> _restoreAttachmentPayload(
    List<AttachmentEntry> attachments,
    List<Map<String, dynamic>> files,
  ) async {
    if (attachments.isEmpty) {
      return const _AttachmentRestoreResult([], []);
    }
    final root = await _attachmentRoot();
    await root.create(recursive: true);
    final byId = {
      for (final value in files) value['attachmentId'] as String: value,
    };
    final result = <AttachmentEntry>[];
    final mutations = <_AttachmentFileMutation>[];
    try {
      for (final attachment in attachments) {
        final payload = byId[attachment.id];
        final rawName =
            payload?['fileName']?.toString() ?? attachment.storedPath;
        final rawExtension = p.extension(rawName).toLowerCase();
        final extension = RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(rawExtension)
            ? rawExtension
            : '';
        final target = File(p.join(root.path, '${attachment.id}$extension'));
        if (payload != null) {
          final existed = await target.exists();
          mutations.add(_AttachmentFileMutation(
            file: target,
            existed: existed,
            originalBytes: existed ? await target.readAsBytes() : null,
          ));
          await target.writeAsBytes(
            base64Decode(payload['contentBase64'] as String),
            flush: true,
          );
        }
        result.add(attachment.copyWith(storedPath: target.path));
      }
    } catch (_) {
      await _AttachmentRestoreResult(result, mutations).rollback();
      rethrow;
    }
    return _AttachmentRestoreResult(result, mutations);
  }

  void _validateBackup({
    required List<TaskEntry> tasks,
    required List<ProjectEntry> projects,
    required List<EventEntry> events,
    required List<SemesterEntry> semesters,
    required List<CourseEntry> courses,
    required List<CourseScheduleEntry> schedules,
    required List<ListEntry> lists,
    required List<ListItemEntry> listItems,
    required List<HabitEntry> habits,
    required List<HabitLogEntry> habitLogs,
    required List<RelationshipProfileEntry> relationships,
    required List<MoodLogEntry> moodLogs,
    required List<LifeEventEntry> lifeEvents,
    required List<CycleRecordEntry> cycleRecords,
    required List<AnniversaryEntry> anniversaries,
    required List<GoalEntry> goals,
    required List<MilestoneEntry> milestones,
    required List<EntityLinkEntry> entityLinks,
    required List<FocusSessionEntry> focusSessions,
    required List<ReviewEntry> reviews,
    required List<InboxItemEntry> inboxItems,
    required List<AutomationRuleEntry> automationRules,
    required List<AutomationRunEntry> automationRuns,
    required List<SavedItemEntry> savedItems,
    required List<AttachmentEntry> attachments,
    required List<AttachmentLinkEntry> attachmentLinks,
    required List<LocationEntry> locations,
    required List<TripProfileEntry> tripProfiles,
    required List<TripExpenseEntry> tripExpenses,
    required List<WeatherLocationEntry> weatherLocations,
    required List<WeatherForecastCacheEntry> weatherForecastCaches,
    required List<EveningPrepItemEntry> eveningPrepItems,
    required List<HouseholdItemEntry> householdItems,
    required List<MedicationPlanEntry> medicationPlans,
    required List<MedicationLogEntry> medicationLogs,
    required List<EmergencyCardEntry> emergencyCards,
    required List<FinanceEntry> financeEntries,
    required List<CredentialRecordEntry> credentialRecords,
    required List<MediaSeriesEntry> mediaSeries,
    required List<MediaEntry> mediaEntries,
    required List<CourseGradeEntry> courseGrades,
    required List<SubscriptionEntry> subscriptions,
    required List<MaintenancePlanEntry> maintenancePlans,
    required List<MaintenanceLogEntry> maintenanceLogs,
    required List<ReadingItemEntry> readingItems,
    required List<ParcelEntry> parcels,
    required List<Map<String, dynamic>> attachmentFiles,
    required List<TagEntry> tags,
    required List<EntityTagEntry> entityTags,
    required List<ReminderEntry> reminders,
    required List<ModuleConfigEntry> configs,
  }) {
    final taskIds = _uniqueIds('tasks', tasks.map((row) => row.id));
    final projectIds = _uniqueIds('projects', projects.map((row) => row.id));
    final eventIds = _uniqueIds('events', events.map((row) => row.id));
    final semesterIds = _uniqueIds('semesters', semesters.map((row) => row.id));
    final courseIds = _uniqueIds('courses', courses.map((row) => row.id));
    final scheduleIds =
        _uniqueIds('courseSchedules', schedules.map((row) => row.id));
    final listIds = _uniqueIds('lists', lists.map((row) => row.id));
    final listItemIds = _uniqueIds('listItems', listItems.map((row) => row.id));
    final habitIds = _uniqueIds('habits', habits.map((row) => row.id));
    final habitLogIds = _uniqueIds('habitLogs', habitLogs.map((row) => row.id));
    final relationshipIds = _uniqueIds(
      'relationshipProfiles',
      relationships.map((row) => row.id),
    );
    final moodLogIds = _uniqueIds('moodLogs', moodLogs.map((row) => row.id));
    final lifeEventIds =
        _uniqueIds('lifeEvents', lifeEvents.map((row) => row.id));
    final cycleRecordIds =
        _uniqueIds('cycleRecords', cycleRecords.map((row) => row.id));
    final anniversaryIds =
        _uniqueIds('anniversaries', anniversaries.map((row) => row.id));
    final goalIds = _uniqueIds('goals', goals.map((row) => row.id));
    final milestoneIds =
        _uniqueIds('milestones', milestones.map((row) => row.id));
    final focusIds =
        _uniqueIds('focusSessions', focusSessions.map((row) => row.id));
    final reviewIds = _uniqueIds('reviews', reviews.map((row) => row.id));
    final inboxIds = _uniqueIds('inboxItems', inboxItems.map((row) => row.id));
    final automationRuleIds =
        _uniqueIds('automationRules', automationRules.map((row) => row.id));
    final automationRunIds =
        _uniqueIds('automationRuns', automationRuns.map((row) => row.id));
    final savedItemIds =
        _uniqueIds('savedItems', savedItems.map((row) => row.id));
    final attachmentIds =
        _uniqueIds('attachments', attachments.map((row) => row.id));
    final locationIds = _uniqueIds('locations', locations.map((row) => row.id));
    final tripIds =
        _uniqueIds('tripProfiles', tripProfiles.map((row) => row.id));
    final tripExpenseIds =
        _uniqueIds('tripExpenses', tripExpenses.map((row) => row.id));
    final weatherLocationIds =
        _uniqueIds('weatherLocations', weatherLocations.map((row) => row.id));
    _uniqueIds(
        'weatherForecastCaches', weatherForecastCaches.map((row) => row.id));
    _uniqueIds('eveningPrepItems', eveningPrepItems.map((row) => row.id));
    final householdIds =
        _uniqueIds('householdItems', householdItems.map((row) => row.id));
    final medicationPlanIds =
        _uniqueIds('medicationPlans', medicationPlans.map((row) => row.id));
    _uniqueIds('medicationLogs', medicationLogs.map((row) => row.id));
    final emergencyCardIds =
        _uniqueIds('emergencyCards', emergencyCards.map((row) => row.id));
    final financeIds =
        _uniqueIds('financeEntries', financeEntries.map((row) => row.id));
    final credentialIds =
        _uniqueIds('credentialRecords', credentialRecords.map((row) => row.id));
    final mediaSeriesIds =
        _uniqueIds('mediaSeries', mediaSeries.map((row) => row.id));
    final mediaEntryIds =
        _uniqueIds('mediaEntries', mediaEntries.map((row) => row.id));
    final courseGradeIds =
        _uniqueIds('courseGrades', courseGrades.map((row) => row.id));
    final subscriptionIds =
        _uniqueIds('subscriptions', subscriptions.map((row) => row.id));
    final maintenancePlanIds =
        _uniqueIds('maintenancePlans', maintenancePlans.map((row) => row.id));
    final maintenanceLogIds =
        _uniqueIds('maintenanceLogs', maintenanceLogs.map((row) => row.id));
    final readingIds =
        _uniqueIds('readingItems', readingItems.map((row) => row.id));
    final parcelIds = _uniqueIds('parcels', parcels.map((row) => row.id));
    _uniqueIds('entityLinks', entityLinks.map((row) => row.id));
    _uniqueIds('attachmentLinks', attachmentLinks.map((row) => row.id));
    final tagIds = _uniqueIds('tags', tags.map((row) => row.id));
    _uniqueIds('reminders', reminders.map((row) => row.id));

    for (final row in tasks) {
      _validateSync('tasks', row.toJson());
      _requiredText('tasks.title', row.title);
      _allowed('tasks.category', row.category,
          const {'STUDY', 'WORK', 'LIFE', 'OUTDOOR'});
      _allowed('tasks.status', row.status,
          const {'TODO', 'IN_PROGRESS', 'DONE', 'CANCELED', 'ARCHIVED'});
      if (row.priority < 0 || row.priority > 4) {
        throw const FormatException('任务优先级无效');
      }
      _optionalReference('tasks.projectId', row.projectId, projectIds);
      _optionalReference('tasks.parentTaskId', row.parentTaskId, taskIds);
      if (row.parentTaskId == row.id) {
        throw const FormatException('任务不能成为自己的子任务');
      }
      _validateRepeat(row.repeatRule, row.dueAt ?? row.startAt);
    }

    for (final row in projects) {
      _validateSync('projects', row.toJson());
      _requiredText('projects.name', row.name);
      _allowed('projects.status', row.status, const {'ACTIVE', 'ARCHIVED'});
      _allowed('projects.progressMode', row.progressMode,
          const {'AUTO_TASK', 'MANUAL'});
      if (row.manualProgress != null &&
          (row.manualProgress! < 0 || row.manualProgress! > 1)) {
        throw const FormatException('项目进度无效');
      }
      if (row.startAt != null &&
          row.dueAt != null &&
          row.dueAt! < row.startAt!) {
        throw const FormatException('项目日期范围无效');
      }
    }

    for (final row in events) {
      _validateSync('events', row.toJson());
      _requiredText('events.title', row.title);
      _allowed('events.eventType', row.eventType,
          const {'STUDY', 'WORK', 'LIFE', 'OUTDOOR', 'COURSE'});
      if (row.endAt <= row.startAt) {
        throw const FormatException('日程结束时间必须晚于开始时间');
      }
      if (row.allDay && row.localDate == null) {
        throw const FormatException('全天日程缺少本地日期');
      }
      if (row.preparationMinutes < 0 || row.travelMinutes < 0) {
        throw const FormatException('日程准备或路程时间无效');
      }
      if (row.localDate != null) DateKeys.fromLocalDateKey(row.localDate!);
      _optionalReference('events.projectId', row.projectId, projectIds);
      _validateRepeat(row.repeatRule, row.startAt);
    }

    final semestersById = {for (final row in semesters) row.id: row};
    for (final row in semesters) {
      _validateSync('semesters', row.toJson());
      _requiredText('semesters.name', row.name);
      final start = DateKeys.fromLocalDateKey(row.startDate);
      final end = DateKeys.fromLocalDateKey(row.endDate);
      if (end.isBefore(start) || row.totalWeeks < 1 || row.totalWeeks > 104) {
        throw const FormatException('学期范围或周数无效');
      }
    }
    for (final row in courses) {
      _validateSync('courses', row.toJson());
      _requiredText('courses.name', row.name);
      _reference('courses.semesterId', row.semesterId, semesterIds);
    }
    for (final row in schedules) {
      _validateSync('courseSchedules', row.toJson());
      _reference('courseSchedules.courseId', row.courseId, courseIds);
      if (row.weekday < 1 ||
          row.weekday > 7 ||
          row.startMinutes < 0 ||
          row.endMinutes > 1440 ||
          row.endMinutes <= row.startMinutes) {
        throw const FormatException('课程时间无效');
      }
      final course = courses.firstWhere((value) => value.id == row.courseId);
      final semester = semestersById[course.semesterId]!;
      DateKeys.parseWeekSet(row.weekSet, totalWeeks: semester.totalWeeks);
      final excluded = jsonDecode(row.excludedDates);
      if (excluded is! List) {
        throw const FormatException('课程排除日期无效');
      }
      for (final value in excluded) {
        if (value is! int) {
          throw const FormatException('课程排除日期无效');
        }
        DateKeys.fromLocalDateKey(value);
      }
      if (row.reminderMinutes != null && row.reminderMinutes! < 0) {
        throw const FormatException('课程提醒时间无效');
      }
    }

    for (final row in lists) {
      _validateSync('lists', row.toJson());
      _requiredText('lists.title', row.title);
      _allowed('lists.listType', row.listType, const {
        'GENERAL',
        'SHOPPING',
        'TRAVEL',
        'CAMPING',
        'MOVING',
        'INTERVIEW',
      });
      _optionalReference('lists.projectId', row.projectId, projectIds);
    }
    for (final row in listItems) {
      _validateSync('listItems', row.toJson());
      _requiredText('listItems.textValue', row.textValue);
      _reference('listItems.listId', row.listId, listIds);
      if (!row.quantity.isFinite || row.quantity < 0) {
        throw const FormatException('清单数量无效');
      }
    }

    for (final row in habits) {
      _validateSync('habits', row.toJson());
      _requiredText('habits.name', row.name);
      HabitRules.weeklyTarget(row.scheduleRule);
      if (row.targetCount < 1) {
        throw const FormatException('习惯目标数量无效');
      }
      _validateReminderPolicy(row.reminderPolicy);
    }
    final habitDateKeys = <String>{};
    for (final row in habitLogs) {
      _validateSync('habitLogs', row.toJson());
      _reference('habitLogs.habitId', row.habitId, habitIds);
      DateKeys.fromLocalDateKey(row.localDate);
      if (row.value < 0) throw const FormatException('习惯记录数值无效');
      _allowed('habitLogs.status', row.status, const {'DONE', 'SKIPPED'});
      if (!habitDateKeys.add('${row.habitId}:${row.localDate}')) {
        throw const FormatException('习惯日记录重复');
      }
    }

    for (final row in relationships) {
      _validateSync('relationshipProfiles', row.toJson());
      _requiredText('relationshipProfiles.name', row.name);
      if (row.startDate != null) DateKeys.fromLocalDateKey(row.startDate!);
      if (row.birthday != null) DateKeys.fromLocalDateKey(row.birthday!);
    }
    final moodContextDates = <String>{};
    for (final row in moodLogs) {
      _validateSync('moodLogs', row.toJson());
      DateKeys.fromLocalDateKey(row.localDate);
      _requiredText('moodLogs.moodCode', row.moodCode);
      if (row.intensity < 1 || row.intensity > 5) {
        throw const FormatException('心情强度无效');
      }
      _optionalReference(
        'moodLogs.relationshipId',
        row.relationshipId,
        relationshipIds,
      );
      if (!moodContextDates.add('${row.contextKey}:${row.localDate}')) {
        throw const FormatException('心情日记重复');
      }
    }
    for (final row in lifeEvents) {
      _validateSync('lifeEvents', row.toJson());
      _requiredText('lifeEvents.title', row.title);
      DateKeys.fromLocalDateKey(row.localDate);
      if (row.timeMinutes != null &&
          (row.timeMinutes! < 0 || row.timeMinutes! >= 1440)) {
        throw const FormatException('生活记录时间无效');
      }
      _optionalReference(
        'lifeEvents.relationshipId',
        row.relationshipId,
        relationshipIds,
      );
    }
    for (final row in cycleRecords) {
      _validateSync('cycleRecords', row.toJson());
      _reference(
        'cycleRecords.relationshipId',
        row.relationshipId,
        relationshipIds,
      );
      DateKeys.fromLocalDateKey(row.startDate);
      if (row.endDate != null) {
        DateKeys.fromLocalDateKey(row.endDate!);
        if (row.endDate! < row.startDate) {
          throw const FormatException('生理期日期范围无效');
        }
      }
    }
    for (final row in anniversaries) {
      _validateSync('anniversaries', row.toJson());
      _requiredText('anniversaries.title', row.title);
      DateKeys.fromLocalDateKey(row.date);
      _optionalReference(
        'anniversaries.relationshipId',
        row.relationshipId,
        relationshipIds,
      );
    }

    for (final row in goals) {
      _validateSync('goals', row.toJson());
      _requiredText('goals.name', row.name);
      _allowed('goals.status', row.status, const {
        'DRAFT',
        'ACTIVE',
        'PAUSED',
        'COMPLETED',
        'ABANDONED',
        'ARCHIVED'
      });
      _allowed('goals.progressMode', row.progressMode,
          const {'MANUAL', 'MILESTONE', 'TASK', 'PROJECT'});
      if (row.manualProgress != null &&
          (row.manualProgress! < 0 || row.manualProgress! > 1)) {
        throw const FormatException('目标进度无效');
      }
    }
    for (final row in milestones) {
      _validateSync('milestones', row.toJson());
      _requiredText('milestones.name', row.name);
      _reference('milestones.goalId', row.goalId, goalIds);
    }
    for (final row in focusSessions) {
      _validateSync('focusSessions', row.toJson());
      if (row.plannedMinutes < 1 || row.pausedMillis < 0) {
        throw const FormatException('专注记录无效');
      }
      _allowed('focusSessions.status', row.status,
          const {'RUNNING', 'PAUSED', 'FINISHED', 'DISCARDED'});
    }
    for (final row in reviews) {
      _validateSync('reviews', row.toJson());
      DateKeys.fromLocalDateKey(row.startDate);
      DateKeys.fromLocalDateKey(row.endDate);
      if (row.endDate < row.startDate || jsonDecode(row.summaryJson) is! Map) {
        throw const FormatException('复盘记录无效');
      }
    }
    for (final row in inboxItems) {
      _validateSync('inboxItems', row.toJson());
      _requiredText('inboxItems.content', row.content);
      _allowed('inboxItems.state', row.state,
          const {'NEW', 'LATER', 'PROCESSED', 'ARCHIVED'});
    }
    for (final row in automationRules) {
      _validateSync('automationRules', row.toJson());
      _requiredText('automationRules.name', row.name);
      if (jsonDecode(row.triggerJson) is! Map ||
          jsonDecode(row.actionJson) is! Map) {
        throw const FormatException('自动化规则无效');
      }
    }
    final runKeys = <String>{};
    for (final row in automationRuns) {
      _validateSync('automationRuns', row.toJson());
      _reference('automationRuns.ruleId', row.ruleId, automationRuleIds);
      if (!runKeys.add(row.idempotencyKey)) {
        throw const FormatException('自动化执行键重复');
      }
    }
    for (final row in savedItems) {
      _validateSync('savedItems', row.toJson());
      _requiredText('savedItems.title', row.title);
      _allowed('savedItems.itemType', row.itemType,
          const {'NOTE', 'ARTICLE', 'LINK', 'IMAGE', 'DOCUMENT'});
      _allowed('savedItems.status', row.status, const {'ACTIVE', 'ARCHIVED'});
      if ((row.associationType == null) != (row.associationId == null)) {
        throw const FormatException('资料库关联无效');
      }
    }
    for (final row in attachments) {
      _validateSync('attachments', row.toJson());
      _requiredText('attachments.displayName', row.displayName);
      _requiredText('attachments.contentDigest', row.contentDigest);
      if (row.byteSize < 0) throw const FormatException('附件大小无效');
    }
    final attachmentFileIds = <String>{};
    final attachmentsById = {for (final row in attachments) row.id: row};
    for (final row in attachmentFiles) {
      final id = row['attachmentId'];
      final content = row['contentBase64'];
      if (id is! String ||
          !attachmentIds.contains(id) ||
          !attachmentFileIds.add(id) ||
          content is! String) {
        throw const FormatException('附件文件数据无效');
      }
      try {
        final bytes = base64Decode(content);
        final attachment = attachmentsById[id];
        if (attachment == null ||
            bytes.length != attachment.byteSize ||
            AttachmentRepository.contentDigest(bytes) !=
                attachment.contentDigest) {
          throw const FormatException('附件文件校验失败');
        }
      } on FormatException {
        throw const FormatException('附件文件数据无效');
      }
    }
    for (final row in locations) {
      _validateSync('locations', row.toJson());
      _requiredText('locations.name', row.name);
      if ((row.latitude == null) != (row.longitude == null) ||
          (row.latitude != null &&
              (row.latitude! < -90 || row.latitude! > 90)) ||
          (row.longitude != null &&
              (row.longitude! < -180 || row.longitude! > 180))) {
        throw const FormatException('地点坐标无效');
      }
    }
    final tripProjectIds = <String>{};
    for (final row in tripProfiles) {
      _validateSync('tripProfiles', row.toJson());
      _reference('tripProfiles.projectId', row.projectId, projectIds);
      DateKeys.fromLocalDateKey(row.startDate);
      DateKeys.fromLocalDateKey(row.endDate);
      if (row.endDate < row.startDate || !tripProjectIds.add(row.projectId)) {
        throw const FormatException('旅行日期或项目关联无效');
      }
    }
    for (final row in tripExpenses) {
      _validateSync('tripExpenses', row.toJson());
      _reference('tripExpenses.tripId', row.tripId, tripIds);
      _requiredText('tripExpenses.title', row.title);
      DateKeys.fromLocalDateKey(row.expenseDate);
      if (row.amountCents <= 0 ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(row.currency)) {
        throw const FormatException('旅行花费无效');
      }
    }
    for (final row in weatherLocations) {
      _validateSync('weatherLocations', row.toJson());
      _requiredText('weatherLocations.name', row.name);
      if (row.latitude < -90 ||
          row.latitude > 90 ||
          row.longitude < -180 ||
          row.longitude > 180) {
        throw const FormatException('天气地区坐标无效');
      }
    }
    for (final row in weatherForecastCaches) {
      _validateSync('weatherForecastCaches', row.toJson());
      _reference('weatherForecastCaches.locationId', row.locationId,
          weatherLocationIds);
      DateKeys.fromLocalDateKey(row.forecastDate);
    }
    for (final row in eveningPrepItems) {
      _validateSync('eveningPrepItems', row.toJson());
      _requiredText('eveningPrepItems.title', row.title);
      DateKeys.fromLocalDateKey(row.localDate);
    }
    for (final row in householdItems) {
      _validateSync('householdItems', row.toJson());
      _requiredText('householdItems.name', row.name);
      if (row.purchaseAmountMinor != null && row.purchaseAmountMinor! < 0) {
        throw const FormatException('家庭物品金额无效');
      }
      _allowed('householdItems.itemKind', row.itemKind,
          const {'DURABLE', 'CONSUMABLE'});
      if (!row.quantity.isFinite ||
          row.quantity < 0 ||
          row.minimumQuantity != null &&
              (!row.minimumQuantity!.isFinite || row.minimumQuantity! < 0)) {
        throw const FormatException('家庭消耗品数量无效');
      }
      if (row.openedDate != null) DateKeys.fromLocalDateKey(row.openedDate!);
      if (row.expiryDate != null) DateKeys.fromLocalDateKey(row.expiryDate!);
      if (row.openedDate != null &&
          row.expiryDate != null &&
          row.expiryDate! < row.openedDate!) {
        throw const FormatException('家庭消耗品日期范围无效');
      }
    }
    for (final row in medicationPlans) {
      _validateSync('medicationPlans', row.toJson());
      _requiredText('medicationPlans.name', row.name);
      DateKeys.fromLocalDateKey(row.startDate);
      if (row.endDate != null) DateKeys.fromLocalDateKey(row.endDate!);
      if (row.endDate != null && row.endDate! < row.startDate) {
        throw const FormatException('用药记录日期范围无效');
      }
      if (jsonDecode(row.reminderTimesJson) is! List) {
        throw const FormatException('用药提醒时间无效');
      }
    }
    for (final row in medicationLogs) {
      _validateSync('medicationLogs', row.toJson());
      _reference('medicationLogs.planId', row.planId, medicationPlanIds);
      DateKeys.fromLocalDateKey(row.localDate);
      if (row.timeMinutes < 0 || row.timeMinutes >= 1440) {
        throw const FormatException('用药打卡时间无效');
      }
    }
    for (final row in emergencyCards) {
      _validateSync('emergencyCards', row.toJson());
    }
    for (final row in financeEntries) {
      _validateSync('financeEntries', row.toJson());
      if (row.amountMinor <= 0 ||
          !const {'INCOME', 'EXPENSE'}.contains(row.direction)) {
        throw const FormatException('收支记录无效');
      }
    }
    for (final row in credentialRecords) {
      _validateSync('credentialRecords', row.toJson());
      _requiredText('credentialRecords.name', row.name);
      if (row.reminderDays < 0) throw const FormatException('证件提醒天数无效');
    }
    final mediaSeriesById = {for (final row in mediaSeries) row.id: row};
    for (final row in mediaSeries) {
      _validateSync('mediaSeries', row.toJson());
      _requiredText('mediaSeries.title', row.title);
      _allowed(
          'mediaSeries.category', row.category, const {'TV', 'ANIME', 'MOVIE'});
      if (row.rating != null && (row.rating! < 0 || row.rating! > 10)) {
        throw const FormatException('影视系列评分无效');
      }
    }
    for (final row in mediaEntries) {
      _validateSync('mediaEntries', row.toJson());
      _requiredText('mediaEntries.title', row.title);
      _allowed('mediaEntries.category', row.category,
          const {'TV', 'ANIME', 'MOVIE'});
      _allowed('mediaEntries.entryType', row.entryType, const {
        'SEASON',
        'MOVIE',
        'OVA',
        'ONA',
        'SPECIAL',
        'SPIN_OFF',
        'DOCUMENTARY',
        'OTHER',
      });
      _allowed('mediaEntries.watchStatus', row.watchStatus,
          const {'PLAN', 'WATCHING', 'COMPLETED', 'PAUSED', 'DROPPED'});
      _optionalReference('mediaEntries.seriesId', row.seriesId, mediaSeriesIds);
      if (row.seriesId != null &&
          mediaSeriesById[row.seriesId]!.category != row.category) {
        throw const FormatException('影视作品与系列分类不一致');
      }
      if (!row.sortKey.isFinite ||
          row.completedEpisodes < 0 ||
          row.totalEpisodes != null &&
              (row.totalEpisodes! < 0 ||
                  row.completedEpisodes > row.totalEpisodes!) ||
          row.playbackPositionSeconds < 0 ||
          row.durationSeconds != null &&
              (row.durationSeconds! < 0 ||
                  row.playbackPositionSeconds > row.durationSeconds!) ||
          row.rating != null && (row.rating! < 0 || row.rating! > 10)) {
        throw const FormatException('影视作品进度或评分无效');
      }
    }

    for (final row in courseGrades) {
      _validateSync('courseGrades', row.toJson());
      _reference('courseGrades.courseId', row.courseId, courseIds);
      _requiredText('courseGrades.title', row.title);
      if (!row.score.isFinite ||
          !row.maximum.isFinite ||
          row.score < 0 ||
          row.maximum <= 0 ||
          row.score > row.maximum ||
          row.weight != null &&
              (!row.weight!.isFinite || row.weight! < 0 || row.weight! > 1)) {
        throw const FormatException('课程成绩无效');
      }
      if (row.occurredDate != null) {
        DateKeys.fromLocalDateKey(row.occurredDate!);
      }
    }
    for (final row in subscriptions) {
      _validateSync('subscriptions', row.toJson());
      _requiredText('subscriptions.name', row.name);
      _allowed('subscriptions.cycleUnit', row.cycleUnit,
          const {'WEEK', 'MONTH', 'YEAR', 'FIXED_DAYS'});
      _allowed('subscriptions.status', row.status,
          const {'ACTIVE', 'PAUSED', 'CANCELED'});
      DateKeys.fromLocalDateKey(row.nextRenewalDate);
      if (row.trialEndDate != null) {
        DateKeys.fromLocalDateKey(row.trialEndDate!);
      }
      final reminderDays = jsonDecode(row.reminderDaysJson);
      if (row.amountMinor <= 0 ||
          row.cycleInterval <= 0 ||
          row.cycleUnit == 'FIXED_DAYS' &&
              (row.fixedDays == null || row.fixedDays! <= 0) ||
          reminderDays is! List ||
          reminderDays.any((value) => value is! num || value < 0)) {
        throw const FormatException('订阅周期或提醒无效');
      }
    }
    for (final row in maintenancePlans) {
      _validateSync('maintenancePlans', row.toJson());
      _requiredText('maintenancePlans.title', row.title);
      _optionalReference('maintenancePlans.householdItemId',
          row.householdItemId, householdIds);
      _optionalReference(
          'maintenancePlans.currentTaskId', row.currentTaskId, taskIds);
      if (row.intervalDays <= 0 ||
          row.nextDueAt < 0 ||
          row.reminderDays < 0 ||
          row.lastCompletedAt != null && row.lastCompletedAt! < 0) {
        throw const FormatException('维护计划无效');
      }
    }
    for (final row in maintenanceLogs) {
      _validateSync('maintenanceLogs', row.toJson());
      _reference('maintenanceLogs.planId', row.planId, maintenancePlanIds);
      if (row.completedAt < 0) throw const FormatException('维护记录时间无效');
    }
    for (final row in readingItems) {
      _validateSync('readingItems', row.toJson());
      _requiredText('readingItems.title', row.title);
      _allowed('readingItems.status', row.status,
          const {'PLANNED', 'READING', 'COMPLETED', 'PAUSED', 'DROPPED'});
      if (row.currentProgress < 0 ||
          row.totalProgress != null &&
              (row.totalProgress! < 0 ||
                  row.currentProgress > row.totalProgress!) ||
          row.rating != null &&
              (!row.rating!.isFinite || row.rating! < 0 || row.rating! > 10)) {
        throw const FormatException('阅读进度或评分无效');
      }
    }
    for (final row in parcels) {
      _validateSync('parcels', row.toJson());
      _requiredText('parcels.title', row.title);
      _allowed('parcels.status', row.status,
          const {'IN_TRANSIT', 'READY', 'COLLECTED', 'RETURNED', 'ARCHIVED'});
      _optionalReference('parcels.locationId', row.locationId, locationIds);
      if (row.expectedAt != null && row.expectedAt! < 0 ||
          row.arrivedAt != null && row.arrivedAt! < 0 ||
          row.pickupDeadline != null && row.pickupDeadline! < 0 ||
          row.arrivedAt != null &&
              row.pickupDeadline != null &&
              row.pickupDeadline! < row.arrivedAt!) {
        throw const FormatException('快递日期范围无效');
      }
    }

    for (final row in tags) {
      _validateSync('tags', row.toJson());
      _requiredText('tags.name', row.name);
    }
    final entityIds = <String, Set<String>>{
      'TASK': taskIds,
      'PROJECT': projectIds,
      'EVENT': eventIds,
      'COURSE': courseIds,
      'COURSE_SCHEDULE': scheduleIds,
      'LIST': listIds,
      'LIST_ITEM': listItemIds,
      'HABIT': habitIds,
      'HABIT_LOG': habitLogIds,
      'RELATIONSHIP': relationshipIds,
      'MOOD': moodLogIds,
      'LIFE_EVENT': lifeEventIds,
      'CYCLE': cycleRecordIds,
      'ANNIVERSARY': anniversaryIds,
      'GOAL': goalIds,
      'MILESTONE': milestoneIds,
      'FOCUS': focusIds,
      'REVIEW': reviewIds,
      'INBOX': inboxIds,
      'AUTOMATION_RULE': automationRuleIds,
      'AUTOMATION_RUN': automationRunIds,
      'SAVED_ITEM': savedItemIds,
      'ATTACHMENT': attachmentIds,
      'LOCATION': locationIds,
      'TRIP': tripIds,
      'TRIP_EXPENSE': tripExpenseIds,
      'WEATHER_LOCATION': weatherLocationIds,
      'HOUSEHOLD': householdIds,
      'MEDICATION': medicationPlanIds,
      'EMERGENCY_CARD': emergencyCardIds,
      'FINANCE': financeIds,
      'CREDENTIAL': credentialIds,
      'MEDIA_SERIES': mediaSeriesIds,
      'MEDIA_ENTRY': mediaEntryIds,
      'COURSE_GRADE': courseGradeIds,
      'SUBSCRIPTION': subscriptionIds,
      'MAINTENANCE': maintenancePlanIds,
      'MAINTENANCE_LOG': maintenanceLogIds,
      'READING': readingIds,
      'PARCEL': parcelIds,
    };
    final entityLinkKeys = <String>{};
    for (final row in entityLinks) {
      _validateSync('entityLinks', row.toJson());
      final sourceIds = entityIds[row.sourceType];
      final targetIds = entityIds[row.targetType];
      if (sourceIds == null || targetIds == null) {
        throw const FormatException('实体关联类型无效');
      }
      _reference('entityLinks.sourceId', row.sourceId, sourceIds);
      _reference('entityLinks.targetId', row.targetId, targetIds);
      if (!entityLinkKeys.add(
          '${row.sourceType}:${row.sourceId}:${row.targetType}:${row.targetId}')) {
        throw const FormatException('实体关联重复');
      }
    }
    final attachmentLinkKeys = <String>{};
    for (final row in attachmentLinks) {
      _validateSync('attachmentLinks', row.toJson());
      _reference(
          'attachmentLinks.attachmentId', row.attachmentId, attachmentIds);
      final targetIds = entityIds[row.entityType];
      if (targetIds == null) {
        throw const FormatException('附件关联类型无效');
      }
      _reference('attachmentLinks.entityId', row.entityId, targetIds);
      if (!attachmentLinkKeys
          .add('${row.attachmentId}:${row.entityType}:${row.entityId}')) {
        throw const FormatException('附件关联重复');
      }
    }
    final entityTagKeys = <String>{};
    for (final row in entityTags) {
      final ids = entityIds[row.entityType];
      if (ids == null) throw FormatException('未知实体类型：${row.entityType}');
      _reference('entityTags.entityId', row.entityId, ids);
      _reference('entityTags.tagId', row.tagId, tagIds);
      if (!entityTagKeys
          .add('${row.entityType}:${row.entityId}:${row.tagId}')) {
        throw const FormatException('实体标签重复');
      }
    }
    final notificationIds = <int>{};
    for (final row in reminders) {
      _validateSync('reminders', row.toJson());
      final ids = entityIds[row.entityType];
      if (ids == null) throw FormatException('未知提醒类型：${row.entityType}');
      _reference('reminders.entityId', row.entityId, ids);
      if (row.triggerAt < 0 || !notificationIds.add(row.notificationId)) {
        throw const FormatException('提醒时间或通知 ID 无效');
      }
    }
    _uniqueIds('moduleConfigs', configs.map((row) => row.key));
  }

  Set<String> _uniqueIds(String table, Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      if (value.trim().isEmpty || !result.add(value)) {
        throw FormatException('$table 包含空 ID 或重复 ID');
      }
    }
    return result;
  }

  void _validateSync(String table, Map<String, dynamic> row) {
    final createdAt = row['createdAt'];
    final updatedAt = row['updatedAt'];
    final version = row['version'];
    final deletedAt = row['deletedAt'];
    final syncState = row['syncState'];
    if (createdAt is! int ||
        updatedAt is! int ||
        createdAt < 0 ||
        updatedAt < createdAt ||
        version is! int ||
        version < 1 ||
        (deletedAt != null && (deletedAt is! int || deletedAt < 0)) ||
        syncState is! int ||
        syncState < 0) {
      throw FormatException('$table 包含无效的同步字段');
    }
    final metadata = jsonDecode(row['metadata'] as String);
    if (metadata is! Map) throw FormatException('$table metadata 无效');
  }

  void _requiredText(String field, String value) {
    if (value.trim().isEmpty) throw FormatException('$field 不能为空');
  }

  void _allowed(String field, String value, Set<String> allowed) {
    if (!allowed.contains(value)) throw FormatException('$field 值无效：$value');
  }

  void _reference(String field, String value, Set<String> ids) {
    if (!ids.contains(value)) throw FormatException('$field 引用不存在：$value');
  }

  void _optionalReference(String field, String? value, Set<String> ids) {
    if (value != null) _reference(field, value, ids);
  }

  void _validateRepeat(String? rule, int? sourceMillis) {
    if (rule == null) return;
    if (sourceMillis == null) {
      throw const FormatException('重复规则缺少日期');
    }
    final source =
        DateTime.fromMillisecondsSinceEpoch(sourceMillis, isUtc: true);
    Recurrence.expandStarts(
      sourceStart: source,
      rule: rule,
      windowStart: source,
      windowEnd: source.add(const Duration(days: 1)),
    );
  }

  void _validateReminderPolicy(String? value) {
    if (value == null) return;
    final parts = value.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts.first) : null;
    final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('习惯提醒时间无效');
    }
  }
}
