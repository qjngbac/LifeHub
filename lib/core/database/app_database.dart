import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

int _nowMillis() => DateTime.now().toUtc().millisecondsSinceEpoch;
String _newId() => const Uuid().v4();

abstract class SyncTable extends Table {
  TextColumn get id => text().clientDefault(_newId)();
  IntColumn get createdAt => integer().clientDefault(_nowMillis)();
  IntColumn get updatedAt => integer().clientDefault(_nowMillis)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get syncState => integer().withDefault(const Constant(0))();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TaskEntry')
class Tasks extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get description => text().nullable()();
  TextColumn get category =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('LIFE'))();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('TODO'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get startAt => integer().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get actualMinutes => integer().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get repeatRule => text().nullable()();
  IntColumn get completedAt => integer().nullable()();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
}

@DataClassName('ProjectEntry')
class Projects extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  TextColumn get color => text().withDefault(const Constant('#4F46E5'))();
  IntColumn get startAt => integer().nullable()();
  IntColumn get dueAt => integer().nullable()();
  TextColumn get progressMode =>
      text().withDefault(const Constant('AUTO_TASK'))();
  RealColumn get manualProgress => real().nullable()();
}

@DataClassName('EventEntry')
class Events extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get eventType => text().withDefault(const Constant('LIFE'))();
  IntColumn get startAt => integer()();
  IntColumn get endAt => integer()();
  TextColumn get timezoneId =>
      text().withDefault(const Constant('Asia/Shanghai'))();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  IntColumn get localDate => integer().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get repeatRule => text().nullable()();
  TextColumn get sourceType => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get preparationMinutes =>
      integer().withDefault(const Constant(0))();
  IntColumn get travelMinutes => integer().withDefault(const Constant(0))();
  BoolColumn get departureReminderEnabled =>
      boolean().withDefault(const Constant(false))();
}

@DataClassName('SemesterEntry')
class Semesters extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer()();
  IntColumn get totalWeeks => integer().withDefault(const Constant(16))();
}

@DataClassName('CourseEntry')
class Courses extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get teacher => text().nullable()();
  TextColumn get room => text().nullable()();
  TextColumn get semesterId => text()();
  TextColumn get color => text().withDefault(const Constant('#4F46E5'))();
}

@DataClassName('CourseScheduleEntry')
class CourseSchedules extends SyncTable {
  TextColumn get courseId => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinutes => integer()();
  IntColumn get endMinutes => integer()();
  TextColumn get weekSet => text().withDefault(const Constant('1-16'))();
  TextColumn get excludedDates => text().withDefault(const Constant('[]'))();
  TextColumn get roomOverride => text().nullable()();
  IntColumn get reminderMinutes => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('ListEntry')
class Lists extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get listType => text().withDefault(const Constant('GENERAL'))();
  TextColumn get projectId => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get template => boolean().withDefault(const Constant(false))();
}

@DataClassName('ListItemEntry')
class ListItems extends SyncTable {
  TextColumn get listId => text()();
  TextColumn get textValue => text().withLength(min: 1, max: 1000)();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
}

@DataClassName('HabitEntry')
class Habits extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get scheduleRule => text().withDefault(const Constant('DAILY'))();
  IntColumn get targetCount => integer().withDefault(const Constant(1))();
  TextColumn get unit => text().withDefault(const Constant('次'))();
  TextColumn get reminderPolicy => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

@DataClassName('HabitLogEntry')
class HabitLogs extends SyncTable {
  TextColumn get habitId => text()();
  IntColumn get localDate => integer()();
  IntColumn get value => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('DONE'))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {habitId, localDate},
      ];
}

@DataClassName('RelationshipProfileEntry')
class RelationshipProfiles extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get nickname => text().nullable()();
  TextColumn get relationType =>
      text().withDefault(const Constant('PARTNER'))();
  IntColumn get startDate => integer().nullable()();
  IntColumn get birthday => integer().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

@DataClassName('MoodLogEntry')
class MoodLogs extends SyncTable {
  IntColumn get localDate => integer()();
  TextColumn get moodCode => text().withLength(min: 1, max: 40)();
  IntColumn get intensity => integer().withDefault(const Constant(3))();
  TextColumn get note => text().nullable()();
  TextColumn get contextKey =>
      text().withLength(min: 1, max: 100).withDefault(const Constant('SELF'))();
  TextColumn get relationshipId => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {localDate, contextKey},
      ];
}

@DataClassName('LifeEventEntry')
class LifeEvents extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 500)();
  IntColumn get localDate => integer()();
  IntColumn get timeMinutes => integer().nullable()();
  TextColumn get eventType => text().withDefault(const Constant('LIFE'))();
  TextColumn get note => text().nullable()();
  TextColumn get relationshipId => text().nullable()();
}

@DataClassName('CycleRecordEntry')
class CycleRecords extends SyncTable {
  TextColumn get relationshipId => text()();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('AnniversaryEntry')
class Anniversaries extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 300)();
  IntColumn get date => integer()();
  BoolColumn get repeatYearly => boolean().withDefault(const Constant(true))();
  TextColumn get category => text().withDefault(const Constant('LIFE'))();
  TextColumn get relationshipId => text().nullable()();
  BoolColumn get showInToday => boolean().withDefault(const Constant(true))();
}

@DataClassName('GoalEntry')
class Goals extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('LIFE'))();
  TextColumn get color => text().withDefault(const Constant('#8B79C6'))();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  IntColumn get startAt => integer().nullable()();
  IntColumn get targetAt => integer().nullable()();
  TextColumn get progressMode =>
      text().withDefault(const Constant('MILESTONE'))();
  RealColumn get manualProgress => real().nullable()();
}

@DataClassName('MilestoneEntry')
class Milestones extends SyncTable {
  TextColumn get goalId => text()();
  TextColumn get name => text().withLength(min: 1, max: 300)();
  IntColumn get targetAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
}

@DataClassName('EntityLinkEntry')
class EntityLinks extends SyncTable {
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  TextColumn get relationType => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {sourceType, sourceId, targetType, targetId},
      ];
}

@DataClassName('FocusSessionEntry')
class FocusSessions extends SyncTable {
  TextColumn get mode => text().withDefault(const Constant('COUNTDOWN'))();
  IntColumn get plannedMinutes => integer()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get pausedAt => integer().nullable()();
  IntColumn get pausedMillis => integer().withDefault(const Constant(0))();
  IntColumn get actualMinutes => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('RUNNING'))();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('ReviewEntry')
class Reviews extends SyncTable {
  TextColumn get periodType => text()();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer()();
  TextColumn get summaryJson => text().withDefault(const Constant('{}'))();
  TextColumn get wins => text().nullable()();
  TextColumn get blockers => text().nullable()();
  TextColumn get nextPriorities => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {periodType, startDate, endDate},
      ];
}

@DataClassName('InboxItemEntry')
class InboxItems extends SyncTable {
  TextColumn get content => text().withLength(min: 1, max: 10000)();
  TextColumn get sourceType => text().withDefault(const Constant('MANUAL'))();
  TextColumn get sourceUri => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('NEW'))();
  TextColumn get convertedType => text().nullable()();
  TextColumn get convertedId => text().nullable()();
}

@DataClassName('AutomationRuleEntry')
class AutomationRules extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get triggerType => text()();
  TextColumn get triggerJson => text().withDefault(const Constant('{}'))();
  TextColumn get actionType => text()();
  TextColumn get actionJson => text().withDefault(const Constant('{}'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get lastRunAt => integer().nullable()();
}

@DataClassName('AutomationRunEntry')
class AutomationRuns extends SyncTable {
  TextColumn get ruleId => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get status => text().withDefault(const Constant('SUCCESS'))();
  TextColumn get message => text().nullable()();
  IntColumn get executedAt => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {idempotencyKey},
      ];
}

@DataClassName('SavedItemEntry')
class SavedItems extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get itemType => text().withDefault(const Constant('NOTE'))();
  TextColumn get content => text().nullable()();
  TextColumn get sourceUri => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  TextColumn get associationType => text().nullable()();
  TextColumn get associationId => text().nullable()();
  BoolColumn get sensitive => boolean().withDefault(const Constant(false))();
}

@DataClassName('AttachmentEntry')
class Attachments extends SyncTable {
  TextColumn get displayName => text().withLength(min: 1, max: 500)();
  TextColumn get storedPath => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get byteSize => integer()();
  TextColumn get contentDigest => text()();
  BoolColumn get sensitive => boolean().withDefault(const Constant(false))();
}

@DataClassName('AttachmentLinkEntry')
class AttachmentLinks extends SyncTable {
  TextColumn get attachmentId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {attachmentId, entityType, entityId},
      ];
}

@DataClassName('LocationEntry')
class Locations extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get locationType => text().withDefault(const Constant('PLACE'))();
  TextColumn get address => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
}

@DataClassName('TripProfileEntry')
class TripProfiles extends SyncTable {
  TextColumn get projectId => text()();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer()();
  TextColumn get status => text().withDefault(const Constant('PLANNING'))();
  TextColumn get notes => text().nullable()();
  TextColumn get coverAttachmentId => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {projectId},
      ];
}

@DataClassName('TripExpenseEntry')
class TripExpenses extends SyncTable {
  TextColumn get tripId => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  IntColumn get expenseDate => integer()();
  TextColumn get category => text().withDefault(const Constant('OTHER'))();
  TextColumn get payer => text().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('WeatherLocationEntry')
class WeatherLocations extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get country => text().nullable()();
  TextColumn get admin1 => text().nullable()();
  TextColumn get admin2 => text().nullable()();
  TextColumn get admin3 => text().nullable()();
  TextColumn get admin4 => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Shanghai'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(true))();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
}

@DataClassName('WeatherForecastCacheEntry')
class WeatherForecastCaches extends SyncTable {
  TextColumn get locationId => text()();
  IntColumn get forecastDate => integer()();
  IntColumn get fetchedAt => integer()();
  TextColumn get payloadJson => text()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {locationId, forecastDate},
      ];
}

@DataClassName('EveningPrepItemEntry')
class EveningPrepItems extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 300)();
  IntColumn get localDate => integer()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  TextColumn get sourceType => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
}

@DataClassName('HouseholdItemEntry')
class HouseholdItems extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get category => text().withDefault(const Constant('OTHER'))();
  TextColumn get brandModel => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  IntColumn get purchaseDate => integer().nullable()();
  IntColumn get purchaseAmountMinor => integer().nullable()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  IntColumn get warrantyEndDate => integer().nullable()();
  TextColumn get locationId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  BoolColumn get sensitive => boolean().withDefault(const Constant(false))();
  TextColumn get itemKind => text().withDefault(const Constant('DURABLE'))();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  TextColumn get unit => text().nullable()();
  IntColumn get openedDate => integer().nullable()();
  IntColumn get expiryDate => integer().nullable()();
  RealColumn get minimumQuantity => real().nullable()();
}

@DataClassName('MedicationPlanEntry')
class MedicationPlans extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get instructions => text().nullable()();
  IntColumn get startDate => integer()();
  IntColumn get endDate => integer().nullable()();
  TextColumn get reminderTimesJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get sensitive => boolean().withDefault(const Constant(true))();
}

@DataClassName('MedicationLogEntry')
class MedicationLogs extends SyncTable {
  TextColumn get planId => text()();
  IntColumn get localDate => integer()();
  IntColumn get timeMinutes => integer()();
  TextColumn get status => text().withDefault(const Constant('TAKEN'))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {planId, localDate, timeMinutes},
      ];
}

@DataClassName('EmergencyCardEntry')
class EmergencyCards extends SyncTable {
  TextColumn get name => text().nullable()();
  IntColumn get birthDate => integer().nullable()();
  TextColumn get bloodType => text().nullable()();
  TextColumn get allergies => text().nullable()();
  TextColumn get conditions => text().nullable()();
  TextColumn get medications => text().nullable()();
  TextColumn get emergencyContacts => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get sensitive => boolean().withDefault(const Constant(true))();
}

@DataClassName('FinanceEntry')
class FinanceEntries extends SyncTable {
  TextColumn get direction => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  TextColumn get category => text().withDefault(const Constant('OTHER'))();
  IntColumn get occurredAt => integer()();
  TextColumn get note => text().nullable()();
  BoolColumn get sensitive => boolean().withDefault(const Constant(false))();
}

@DataClassName('CredentialRecordEntry')
class CredentialRecords extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get credentialType =>
      text().withDefault(const Constant('OTHER'))();
  TextColumn get holder => text().nullable()();
  TextColumn get numberHint => text().nullable()();
  IntColumn get issuedDate => integer().nullable()();
  IntColumn get expiryDate => integer().nullable()();
  IntColumn get reminderDays => integer().withDefault(const Constant(30))();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  BoolColumn get sensitive => boolean().withDefault(const Constant(true))();
}

@DataClassName('MediaSeriesEntry')
class MediaSeries extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get category => text().withLength(min: 1, max: 20)();
  TextColumn get description => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  IntColumn get releaseYear => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('MediaEntry')
class MediaEntries extends SyncTable {
  TextColumn get seriesId => text().nullable()();
  TextColumn get category => text().withLength(min: 1, max: 20)();
  TextColumn get entryType => text().withLength(min: 1, max: 30)();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get subtitle => text().nullable()();
  RealColumn get sortKey => real().withDefault(const Constant(0))();
  IntColumn get seasonNumber => integer().nullable()();
  IntColumn get releaseYear => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get watchStatus => text().withDefault(const Constant('PLAN'))();
  IntColumn get totalEpisodes => integer().nullable()();
  IntColumn get completedEpisodes => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().nullable()();
  IntColumn get playbackPositionSeconds =>
      integer().withDefault(const Constant(0))();
  IntColumn get lastWatchedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('CourseGradeEntry')
class CourseGrades extends SyncTable {
  TextColumn get courseId => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get gradeType => text().withDefault(const Constant('OTHER'))();
  RealColumn get score => real()();
  RealColumn get maximum => real().withDefault(const Constant(100))();
  RealColumn get weight => real().nullable()();
  IntColumn get occurredDate => integer().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('SubscriptionEntry')
class Subscriptions extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get category => text().withDefault(const Constant('OTHER'))();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  TextColumn get cycleUnit => text()();
  IntColumn get cycleInterval => integer().withDefault(const Constant(1))();
  IntColumn get fixedDays => integer().nullable()();
  IntColumn get nextRenewalDate => integer()();
  IntColumn get trialEndDate => integer().nullable()();
  BoolColumn get autoRenew => boolean().withDefault(const Constant(true))();
  TextColumn get cancellationUrl => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get reminderDaysJson =>
      text().withDefault(const Constant('[7,3,1]'))();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  IntColumn get lastConfirmedCycleDate => integer().nullable()();
}

@DataClassName('MaintenancePlanEntry')
class MaintenancePlans extends SyncTable {
  TextColumn get householdItemId => text().nullable()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  IntColumn get intervalDays => integer()();
  IntColumn get lastCompletedAt => integer().nullable()();
  IntColumn get nextDueAt => integer()();
  IntColumn get reminderDays => integer().withDefault(const Constant(1))();
  TextColumn get currentTaskId => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
}

@DataClassName('MaintenanceLogEntry')
class MaintenanceLogs extends SyncTable {
  TextColumn get planId => text()();
  IntColumn get completedAt => integer()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('ReadingItemEntry')
class ReadingItems extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get author => text().nullable()();
  TextColumn get readingType => text().withDefault(const Constant('BOOK'))();
  TextColumn get progressUnit => text().withDefault(const Constant('PAGE'))();
  IntColumn get currentProgress => integer().withDefault(const Constant(0))();
  IntColumn get totalProgress => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('PLANNED'))();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get lastReadAt => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get coverPath => text().nullable()();
}

@DataClassName('ParcelEntry')
class Parcels extends SyncTable {
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get carrier => text().nullable()();
  TextColumn get trackingNumber => text().nullable()();
  TextColumn get pickupCode => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('IN_TRANSIT'))();
  IntColumn get expectedAt => integer().nullable()();
  IntColumn get arrivedAt => integer().nullable()();
  IntColumn get pickupDeadline => integer().nullable()();
  TextColumn get locationId => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get sensitive => boolean().withDefault(const Constant(true))();
}

@DataClassName('TagEntry')
class Tags extends SyncTable {
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get color => text().withDefault(const Constant('#4F46E5'))();
}

@DataClassName('EntityTagEntry')
class EntityTags extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column<Object>> get primaryKey => {entityType, entityId, tagId};
}

@DataClassName('ReminderEntry')
class Reminders extends SyncTable {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get triggerAt => integer()();
  IntColumn get notificationId => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get reminderKind =>
      text().withDefault(const Constant('DEFAULT'))();
}

@DataClassName('ModuleConfigEntry')
class ModuleConfigs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer().clientDefault(_nowMillis)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('ChangeLogEntry')
class ChangeLogs extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadHash => text().nullable()();
  IntColumn get createdAt => integer().clientDefault(_nowMillis)();
}

@DriftDatabase(
  tables: [
    Tasks,
    Projects,
    Events,
    Semesters,
    Courses,
    CourseSchedules,
    Lists,
    ListItems,
    Habits,
    HabitLogs,
    RelationshipProfiles,
    MoodLogs,
    LifeEvents,
    CycleRecords,
    Anniversaries,
    Goals,
    Milestones,
    EntityLinks,
    FocusSessions,
    Reviews,
    InboxItems,
    AutomationRules,
    AutomationRuns,
    SavedItems,
    Attachments,
    AttachmentLinks,
    Locations,
    TripProfiles,
    TripExpenses,
    WeatherLocations,
    WeatherForecastCaches,
    EveningPrepItems,
    HouseholdItems,
    MedicationPlans,
    MedicationLogs,
    EmergencyCards,
    FinanceEntries,
    CredentialRecords,
    MediaSeries,
    MediaEntries,
    CourseGrades,
    Subscriptions,
    MaintenancePlans,
    MaintenanceLogs,
    ReadingItems,
    Parcels,
    Tags,
    EntityTags,
    Reminders,
    ModuleConfigs,
    ChangeLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createIndexes();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(relationshipProfiles);
            await migrator.createTable(moodLogs);
            await migrator.createTable(lifeEvents);
            await migrator.createTable(cycleRecords);
            await migrator.createTable(anniversaries);
          }
          if (from < 3) {
            await migrator.addColumn(events, events.archived);
            await migrator.addColumn(courseSchedules, courseSchedules.archived);
            await customStatement(
              'UPDATE events SET archived = 1, deleted_at = NULL '
              'WHERE deleted_at IS NOT NULL',
            );
            await customStatement(
              'UPDATE course_schedules SET archived = 1, deleted_at = NULL '
              'WHERE deleted_at IS NOT NULL',
            );
          }
          if (from < 4) {
            await migrator.createTable(goals);
            await migrator.createTable(milestones);
            await migrator.createTable(entityLinks);
            await migrator.createTable(focusSessions);
            await migrator.createTable(reviews);
          }
          if (from < 5) {
            await migrator.createTable(inboxItems);
            await migrator.createTable(automationRules);
            await migrator.createTable(automationRuns);
          }
          if (from < 6) {
            await migrator.createTable(savedItems);
            await migrator.createTable(attachments);
            await migrator.createTable(attachmentLinks);
            await migrator.createTable(locations);
            await migrator.createTable(tripProfiles);
            await migrator.createTable(tripExpenses);
          }
          if (from < 7) {
            await migrator.addColumn(entityLinks, entityLinks.relationType);
            await migrator.addColumn(entityLinks, entityLinks.note);
            await migrator.createTable(weatherLocations);
            await migrator.createTable(weatherForecastCaches);
            await migrator.createTable(eveningPrepItems);
            await migrator.createTable(householdItems);
            await migrator.createTable(medicationPlans);
            await migrator.createTable(medicationLogs);
            await migrator.createTable(emergencyCards);
            await migrator.createTable(financeEntries);
            await migrator.createTable(credentialRecords);
          }
          if (from < 8) {
            await migrator.createTable(mediaSeries);
            await migrator.createTable(mediaEntries);
          }
          if (from < 9) {
            await migrator.addColumn(events, events.preparationMinutes);
            await migrator.addColumn(events, events.travelMinutes);
            await migrator.addColumn(events, events.departureReminderEnabled);
            await migrator.addColumn(householdItems, householdItems.itemKind);
            await migrator.addColumn(householdItems, householdItems.quantity);
            await migrator.addColumn(householdItems, householdItems.unit);
            await migrator.addColumn(householdItems, householdItems.openedDate);
            await migrator.addColumn(householdItems, householdItems.expiryDate);
            await migrator.addColumn(
              householdItems,
              householdItems.minimumQuantity,
            );
            await migrator.addColumn(reminders, reminders.reminderKind);
            await migrator.createTable(courseGrades);
            await migrator.createTable(subscriptions);
            await migrator.createTable(maintenancePlans);
            await migrator.createTable(maintenanceLogs);
            await migrator.createTable(readingItems);
            await migrator.createTable(parcels);
          }
          if (from >= 4 && from < 11) {
            await migrator.addColumn(focusSessions, focusSessions.mode);
          }
          if (from >= 7 && from < 10) {
            await migrator.addColumn(emergencyCards, emergencyCards.birthDate);
            await customStatement(
              'UPDATE emergency_cards '
              'SET birth_date = birth_year * 10000 + 101 '
              'WHERE birth_date IS NULL AND birth_year IS NOT NULL',
            );
          }
          await _createIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_status_due '
      'ON tasks(status, due_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_events_window '
      'ON events(archived, start_at, end_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_habit_logs_date '
      'ON habit_logs(habit_id, local_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_change_logs_entity '
      'ON change_logs(entity_type, entity_id, seq)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mood_context_date '
      'ON mood_logs(context_key, local_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_life_events_date '
      'ON life_events(local_date, relationship_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cycle_relationship_date '
      'ON cycle_records(relationship_id, start_date, end_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_anniversaries_date '
      'ON anniversaries(date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_goals_status '
      'ON goals(status, target_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_milestones_goal '
      'ON milestones(goal_id, sort_key, target_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_entity_links_source '
      'ON entity_links(source_type, source_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_focus_status '
      'ON focus_sessions(status, started_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_reviews_period '
      'ON reviews(period_type, start_date, end_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_inbox_state '
      'ON inbox_items(state, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_automation_enabled '
      'ON automation_rules(enabled, trigger_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_automation_runs_rule '
      'ON automation_runs(rule_id, executed_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_saved_items_state '
      'ON saved_items(status, item_type, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachments_digest '
      'ON attachments(content_digest, deleted_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachment_links_entity '
      'ON attachment_links(entity_type, entity_id, deleted_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_locations_type '
      'ON locations(location_type, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_trip_profiles_dates '
      'ON trip_profiles(start_date, end_date, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_trip_expenses_trip '
      'ON trip_expenses(trip_id, expense_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_weather_default '
      'ON weather_locations(is_default, is_favorite, sort_key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_weather_cache_date '
      'ON weather_forecast_caches(location_id, forecast_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_evening_prep_date '
      'ON evening_prep_items(local_date, checked, sort_key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_household_warranty '
      'ON household_items(status, warranty_end_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_medication_active '
      'ON medication_plans(active, start_date, end_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_medication_logs_date '
      'ON medication_logs(plan_id, local_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_finance_date '
      'ON finance_entries(occurred_at, direction, category)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_credentials_expiry '
      'ON credential_records(status, expiry_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_series_category '
      'ON media_series(category, deleted_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_entries_status '
      'ON media_entries(category, watch_status, deleted_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_entries_series '
      'ON media_entries(series_id, sort_key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_entries_recent '
      'ON media_entries(watch_status, last_watched_at, updated_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_course_grades_course '
      'ON course_grades(course_id, occurred_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_subscriptions_due '
      'ON subscriptions(status, next_renewal_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_maintenance_due '
      'ON maintenance_plans(active, next_due_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_reading_continue '
      'ON reading_items(status, last_read_at, updated_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_parcels_status_deadline '
      'ON parcels(status, pickup_deadline)',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lifehub.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
