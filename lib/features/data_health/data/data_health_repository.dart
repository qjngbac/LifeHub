import 'dart:io';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';

enum DataHealthSeverity { warning, error }

class DataHealthIssue {
  const DataHealthIssue({
    required this.code,
    required this.severity,
    required this.entityType,
    required this.entityId,
    required this.message,
  });

  final String code;
  final DataHealthSeverity severity;
  final String entityType;
  final String entityId;
  final String message;
}

class DataHealthReport {
  const DataHealthReport(this.issues);

  final List<DataHealthIssue> issues;
  bool get hasErrors =>
      issues.any((issue) => issue.severity == DataHealthSeverity.error);
}

class DataHealthRepository {
  DataHealthRepository(this._database);

  final AppDatabase _database;

  Future<DataHealthReport> inspect() async {
    final issues = <DataHealthIssue>[];
    final projects = await _database.select(_database.projects).get();
    final activeProjectIds = projects
        .where((project) => project.deletedAt == null)
        .map((project) => project.id)
        .toSet();
    final tasks = await _database.select(_database.tasks).get();
    for (final task in tasks) {
      if (task.deletedAt == null &&
          task.projectId != null &&
          !activeProjectIds.contains(task.projectId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_TASK_PROJECT',
          severity: DataHealthSeverity.error,
          entityType: 'TASK',
          entityId: task.id,
          message: '任务“${task.title}”关联的项目不存在或已删除。',
        ));
      }
      if (task.startAt != null &&
          task.dueAt != null &&
          task.dueAt! < task.startAt!) {
        issues.add(DataHealthIssue(
          code: 'INVALID_TASK_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'TASK',
          entityId: task.id,
          message: '任务“${task.title}”的结束时间早于开始时间。',
        ));
      }
    }

    final lists = await _database.select(_database.lists).get();
    final listIds = lists
        .where((list) => list.deletedAt == null)
        .map((list) => list.id)
        .toSet();
    final listItems = await _database.select(_database.listItems).get();
    for (final item in listItems) {
      if (item.deletedAt == null && !listIds.contains(item.listId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_LIST_ITEM',
          severity: DataHealthSeverity.warning,
          entityType: 'LIST_ITEM',
          entityId: item.id,
          message: '清单条目“${item.textValue}”没有有效清单。',
        ));
      }
    }

    final schedules = await _database.select(_database.courseSchedules).get();
    final courses = await _database.select(_database.courses).get();
    final courseIds = courses
        .where((course) => course.deletedAt == null)
        .map((course) => course.id)
        .toSet();
    for (final schedule in schedules) {
      if (schedule.deletedAt == null &&
          !courseIds.contains(schedule.courseId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_COURSE_SCHEDULE',
          severity: DataHealthSeverity.warning,
          entityType: 'COURSE_SCHEDULE',
          entityId: schedule.id,
          message: '一个课程时间没有有效课程。',
        ));
      }
    }

    final reminders = await _database.select(_database.reminders).get();
    for (final reminder
        in reminders.where((value) => value.deletedAt == null)) {
      final deleted = await _targetDeleted(
        reminder.entityType,
        reminder.entityId,
      );
      if (deleted) {
        issues.add(DataHealthIssue(
          code: 'REMINDER_DELETED_ENTITY',
          severity: DataHealthSeverity.error,
          entityType: 'REMINDER',
          entityId: reminder.id,
          message: '一条提醒指向已经删除的数据。',
        ));
      }
    }
    final trips = await _database.select(_database.tripProfiles).get();
    final activeTripIds = trips
        .where((trip) => trip.deletedAt == null)
        .map((trip) => trip.id)
        .toSet();
    for (final trip in trips.where((value) => value.deletedAt == null)) {
      if (!activeProjectIds.contains(trip.projectId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_TRIP_PROJECT',
          severity: DataHealthSeverity.error,
          entityType: 'TRIP',
          entityId: trip.id,
          message: '旅行计划关联的项目不存在或已删除。',
        ));
      }
    }
    final expenses = await _database.select(_database.tripExpenses).get();
    for (final expense in expenses.where((value) => value.deletedAt == null)) {
      if (!activeTripIds.contains(expense.tripId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_TRIP_EXPENSE',
          severity: DataHealthSeverity.warning,
          entityType: 'TRIP_EXPENSE',
          entityId: expense.id,
          message: '一条旅行花费没有有效旅行。',
        ));
      }
    }
    final attachments = await _database.select(_database.attachments).get();
    final activeAttachmentIds = attachments
        .where((value) => value.deletedAt == null)
        .map((value) => value.id)
        .toSet();
    for (final attachment
        in attachments.where((value) => value.deletedAt == null)) {
      if (!await File(attachment.storedPath).exists()) {
        issues.add(DataHealthIssue(
          code: 'MISSING_ATTACHMENT_FILE',
          severity: DataHealthSeverity.warning,
          entityType: 'ATTACHMENT',
          entityId: attachment.id,
          message: '附件“${attachment.displayName}”的本地文件已丢失。',
        ));
      }
    }
    final attachmentLinks =
        await _database.select(_database.attachmentLinks).get();
    for (final link
        in attachmentLinks.where((value) => value.deletedAt == null)) {
      if (!activeAttachmentIds.contains(link.attachmentId) ||
          !await _entityExists(link.entityType, link.entityId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_ATTACHMENT_LINK',
          severity: DataHealthSeverity.warning,
          entityType: 'ATTACHMENT_LINK',
          entityId: link.id,
          message: '一条附件关联指向不存在的数据。',
        ));
      }
    }
    final entityLinks = await _database.select(_database.entityLinks).get();
    for (final link in entityLinks.where((value) => value.deletedAt == null)) {
      if (!await _entityExists(link.sourceType, link.sourceId) ||
          !await _entityExists(link.targetType, link.targetId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_ENTITY_LINK',
          severity: DataHealthSeverity.warning,
          entityType: 'ENTITY_LINK',
          entityId: link.id,
          message: '一条模块关联指向不存在的数据。',
        ));
      }
    }
    final medicationPlans =
        await _database.select(_database.medicationPlans).get();
    final medicationPlanIds = medicationPlans
        .where((value) => value.deletedAt == null)
        .map((value) => value.id)
        .toSet();
    for (final plan
        in medicationPlans.where((value) => value.deletedAt == null)) {
      if (plan.endDate != null && plan.endDate! < plan.startDate) {
        issues.add(DataHealthIssue(
          code: 'INVALID_MEDICATION_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'MEDICATION',
          entityId: plan.id,
          message: '用药记录的结束日期早于开始日期。',
        ));
      }
    }
    for (final log in (await _database.select(_database.medicationLogs).get())
        .where((value) => value.deletedAt == null)) {
      if (!medicationPlanIds.contains(log.planId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_MEDICATION_LOG',
          severity: DataHealthSeverity.warning,
          entityType: 'MEDICATION_LOG',
          entityId: log.id,
          message: '一条用药打卡没有有效的提醒计划。',
        ));
      }
    }
    for (final item in (await _database.select(_database.householdItems).get())
        .where((value) => value.deletedAt == null)) {
      if (item.purchaseDate != null &&
          item.warrantyEndDate != null &&
          item.warrantyEndDate! < item.purchaseDate!) {
        issues.add(DataHealthIssue(
          code: 'INVALID_WARRANTY_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'HOUSEHOLD',
          entityId: item.id,
          message: '家庭物品的保修截止日期早于购买日期。',
        ));
      }
      if (!item.quantity.isFinite ||
          item.quantity < 0 ||
          item.minimumQuantity != null &&
              (!item.minimumQuantity!.isFinite || item.minimumQuantity! < 0)) {
        issues.add(DataHealthIssue(
          code: 'INVALID_CONSUMABLE_STOCK',
          severity: DataHealthSeverity.error,
          entityType: 'HOUSEHOLD',
          entityId: item.id,
          message: '家庭消耗品“${item.name}”的库存数量无效。',
        ));
      }
      if (item.openedDate != null &&
          item.expiryDate != null &&
          item.expiryDate! < item.openedDate!) {
        issues.add(DataHealthIssue(
          code: 'INVALID_CONSUMABLE_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'HOUSEHOLD',
          entityId: item.id,
          message: '家庭消耗品“${item.name}”的到期日期早于开封日期。',
        ));
      }
    }
    for (final record
        in (await _database.select(_database.credentialRecords).get())
            .where((value) => value.deletedAt == null)) {
      if (record.issuedDate != null &&
          record.expiryDate != null &&
          record.expiryDate! < record.issuedDate!) {
        issues.add(DataHealthIssue(
          code: 'INVALID_CREDENTIAL_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'CREDENTIAL',
          entityId: record.id,
          message: '证件到期日期早于签发日期。',
        ));
      }
    }
    final mediaSeriesIds = (await _database.select(_database.mediaSeries).get())
        .where((value) => value.deletedAt == null)
        .map((value) => value.id)
        .toSet();
    for (final entry in (await _database.select(_database.mediaEntries).get())
        .where((value) => value.deletedAt == null)) {
      if (entry.seriesId != null && !mediaSeriesIds.contains(entry.seriesId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_MEDIA_SERIES',
          severity: DataHealthSeverity.warning,
          entityType: 'MEDIA_ENTRY',
          entityId: entry.id,
          message: '影视作品“${entry.title}”关联的系列不存在或已删除。',
        ));
      }
      if (entry.completedEpisodes < 0 ||
          entry.totalEpisodes != null &&
              (entry.totalEpisodes! < 0 ||
                  entry.completedEpisodes > entry.totalEpisodes!) ||
          entry.playbackPositionSeconds < 0 ||
          entry.durationSeconds != null &&
              (entry.durationSeconds! < 0 ||
                  entry.playbackPositionSeconds > entry.durationSeconds!) ||
          entry.rating != null && (entry.rating! < 0 || entry.rating! > 10)) {
        issues.add(DataHealthIssue(
          code: 'INVALID_MEDIA_PROGRESS',
          severity: DataHealthSeverity.error,
          entityType: 'MEDIA_ENTRY',
          entityId: entry.id,
          message: '影视作品“${entry.title}”的进度或评分无效。',
        ));
      }
    }
    for (final grade in (await _database.select(_database.courseGrades).get())
        .where((value) => value.deletedAt == null)) {
      if (!courseIds.contains(grade.courseId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_COURSE_GRADE',
          severity: DataHealthSeverity.warning,
          entityType: 'COURSE_GRADE',
          entityId: grade.id,
          message: '成绩“${grade.title}”没有有效课程。',
        ));
      }
      if (!grade.score.isFinite ||
          !grade.maximum.isFinite ||
          grade.score < 0 ||
          grade.maximum <= 0 ||
          grade.score > grade.maximum ||
          grade.weight != null &&
              (!grade.weight!.isFinite ||
                  grade.weight! < 0 ||
                  grade.weight! > 1)) {
        issues.add(DataHealthIssue(
          code: 'INVALID_COURSE_GRADE',
          severity: DataHealthSeverity.error,
          entityType: 'COURSE_GRADE',
          entityId: grade.id,
          message: '成绩“${grade.title}”的分数、满分或权重无效。',
        ));
      }
    }
    for (final subscription
        in (await _database.select(_database.subscriptions).get())
            .where((value) => value.deletedAt == null)) {
      if (subscription.amountMinor <= 0 ||
          subscription.cycleInterval <= 0 ||
          subscription.cycleUnit == 'FIXED_DAYS' &&
              (subscription.fixedDays == null ||
                  subscription.fixedDays! <= 0)) {
        issues.add(DataHealthIssue(
          code: 'INVALID_SUBSCRIPTION',
          severity: DataHealthSeverity.error,
          entityType: 'SUBSCRIPTION',
          entityId: subscription.id,
          message: '订阅“${subscription.name}”的金额或周期无效。',
        ));
      }
    }
    final maintenancePlans =
        await _database.select(_database.maintenancePlans).get();
    final maintenancePlanIds = maintenancePlans
        .where((value) => value.deletedAt == null)
        .map((value) => value.id)
        .toSet();
    for (final plan
        in maintenancePlans.where((value) => value.deletedAt == null)) {
      if (plan.householdItemId != null &&
          !(await _entityExists('HOUSEHOLD', plan.householdItemId!))) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_MAINTENANCE_HOUSEHOLD',
          severity: DataHealthSeverity.warning,
          entityType: 'MAINTENANCE',
          entityId: plan.id,
          message: '维护计划“${plan.title}”关联的家庭物品不存在。',
        ));
      }
      if (plan.intervalDays <= 0 ||
          plan.nextDueAt < 0 ||
          plan.reminderDays < 0) {
        issues.add(DataHealthIssue(
          code: 'INVALID_MAINTENANCE_PLAN',
          severity: DataHealthSeverity.error,
          entityType: 'MAINTENANCE',
          entityId: plan.id,
          message: '维护计划“${plan.title}”的周期或日期无效。',
        ));
      }
    }
    for (final log in (await _database.select(_database.maintenanceLogs).get())
        .where((value) => value.deletedAt == null)) {
      if (!maintenancePlanIds.contains(log.planId)) {
        issues.add(DataHealthIssue(
          code: 'ORPHAN_MAINTENANCE_LOG',
          severity: DataHealthSeverity.warning,
          entityType: 'MAINTENANCE_LOG',
          entityId: log.id,
          message: '一条维护记录没有有效维护计划。',
        ));
      }
    }
    for (final reading in (await _database.select(_database.readingItems).get())
        .where((value) => value.deletedAt == null)) {
      if (reading.currentProgress < 0 ||
          reading.totalProgress != null &&
              (reading.totalProgress! < 0 ||
                  reading.currentProgress > reading.totalProgress!) ||
          reading.rating != null &&
              (reading.rating! < 0 || reading.rating! > 10)) {
        issues.add(DataHealthIssue(
          code: 'INVALID_READING_PROGRESS',
          severity: DataHealthSeverity.error,
          entityType: 'READING',
          entityId: reading.id,
          message: '读物“${reading.title}”的进度或评分无效。',
        ));
      }
    }
    for (final parcel in (await _database.select(_database.parcels).get())
        .where((value) => value.deletedAt == null)) {
      if (parcel.arrivedAt != null &&
          parcel.pickupDeadline != null &&
          parcel.pickupDeadline! < parcel.arrivedAt!) {
        issues.add(DataHealthIssue(
          code: 'INVALID_PARCEL_RANGE',
          severity: DataHealthSeverity.error,
          entityType: 'PARCEL',
          entityId: parcel.id,
          message: '快递“${parcel.title}”的取件截止早于到达时间。',
        ));
      }
    }
    return DataHealthReport(List.unmodifiable(issues));
  }

  Future<bool> _entityExists(String type, String id) async {
    final table = switch (type) {
      'TASK' => 'tasks',
      'PROJECT' => 'projects',
      'EVENT' => 'events',
      'COURSE' => 'courses',
      'LIST' => 'lists',
      'HABIT' => 'habits',
      'RELATIONSHIP' => 'relationship_profiles',
      'LIFE_EVENT' => 'life_events',
      'ANNIVERSARY' => 'anniversaries',
      'GOAL' => 'goals',
      'MILESTONE' => 'milestones',
      'SAVED_ITEM' => 'saved_items',
      'ATTACHMENT' => 'attachments',
      'LOCATION' => 'locations',
      'TRIP' => 'trip_profiles',
      'TRIP_EXPENSE' => 'trip_expenses',
      'HOUSEHOLD' => 'household_items',
      'MEDICATION' => 'medication_plans',
      'FINANCE' => 'finance_entries',
      'CREDENTIAL' => 'credential_records',
      'MEDIA_SERIES' => 'media_series',
      'MEDIA_ENTRY' => 'media_entries',
      'COURSE_GRADE' => 'course_grades',
      'SUBSCRIPTION' => 'subscriptions',
      'MAINTENANCE' => 'maintenance_plans',
      'MAINTENANCE_LOG' => 'maintenance_logs',
      'READING' => 'reading_items',
      'PARCEL' => 'parcels',
      _ => null,
    };
    if (table == null) return false;
    final values = await _database.customSelect(
      'SELECT id FROM $table WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    return values.isNotEmpty;
  }

  Future<bool> _targetDeleted(String type, String id) async {
    switch (type) {
      case 'TASK':
        final row = await (_database.select(_database.tasks)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'EVENT':
        final row = await (_database.select(_database.events)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'HABIT':
        final row = await (_database.select(_database.habits)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'ANNIVERSARY':
        final row = await (_database.select(_database.anniversaries)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'COURSE':
        final row = await (_database.select(_database.courses)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'COURSE_SCHEDULE':
        final row = await (_database.select(_database.courseSchedules)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'MEDICATION':
        final row = await (_database.select(_database.medicationPlans)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'SUBSCRIPTION':
        final row = await (_database.select(_database.subscriptions)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'HOUSEHOLD':
        final row = await (_database.select(_database.householdItems)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'MAINTENANCE':
        final row = await (_database.select(_database.maintenancePlans)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      case 'PARCEL':
        final row = await (_database.select(_database.parcels)
              ..where((value) => value.id.equals(id)))
            .getSingleOrNull();
        return row == null || row.deletedAt != null;
      default:
        return true;
    }
  }
}
