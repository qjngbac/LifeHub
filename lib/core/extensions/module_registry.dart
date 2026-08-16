abstract interface class ModuleDescriptor {
  String get id;
  String get title;
  bool get enabledByDefault;
}

abstract interface class SearchProvider<T> {
  String get moduleId;
  Future<List<T>> search(String query);
}

abstract interface class TodayCardProvider<T> {
  String get moduleId;
  Future<T?> load(DateTime date);
}

abstract interface class StatisticsProvider<T> {
  String get moduleId;
  Future<T> load(DateTime start, DateTime end);
}

abstract interface class SyncEntityAdapter<T> {
  String get entityType;
  Map<String, Object?> encode(T entity);
}

abstract interface class NaturalLanguageCreateParser<T> {
  T? parse(String source);
}

class ModuleRegistry {
  ModuleRegistry(Iterable<ModuleDescriptor> modules)
      : modules = Map.unmodifiable(
            {for (final module in modules) module.id: module}) {
    if (this.modules.length != modules.length) {
      throw ArgumentError('Module ids must be unique.');
    }
  }

  final Map<String, ModuleDescriptor> modules;
}

class CoreModuleDescriptor implements ModuleDescriptor {
  const CoreModuleDescriptor(this.id, this.title,
      {this.enabledByDefault = true});
  @override
  final String id;
  @override
  final String title;
  @override
  final bool enabledByDefault;
}

const coreModules = <ModuleDescriptor>[
  CoreModuleDescriptor('tasks', '任务'),
  CoreModuleDescriptor('events', '日程'),
  CoreModuleDescriptor('projects', '项目'),
  CoreModuleDescriptor('courses', '课程'),
  CoreModuleDescriptor('lists', '清单'),
  CoreModuleDescriptor('habits', '习惯'),
];
