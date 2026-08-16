class KnowledgeCategory {
  const KnowledgeCategory({
    required this.id,
    required this.name,
    required this.count,
  });

  factory KnowledgeCategory.fromJson(Map<String, dynamic> json) =>
      KnowledgeCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        count: json['count'] as int,
      );

  final String id;
  final String name;
  final int count;
}

class ConsumerGuideItem {
  const ConsumerGuideItem({
    required this.id,
    required this.number,
    required this.categoryId,
    required this.category,
    required this.name,
    required this.buyingTip,
    required this.standards,
    required this.misconception,
  });

  factory ConsumerGuideItem.fromJson(Map<String, dynamic> json) =>
      ConsumerGuideItem(
        id: json['id'] as String,
        number: json['number'] as int,
        categoryId: json['categoryId'] as String,
        category: json['category'] as String,
        name: json['name'] as String,
        buyingTip: json['buyingTip'] as String,
        standards: json['standards'] as String,
        misconception: json['misconception'] as String,
      );

  final String id;
  final int number;
  final String categoryId;
  final String category;
  final String name;
  final String buyingTip;
  final String standards;
  final String misconception;

  bool matches(String query) => _matches(
        query,
        [name, category, buyingTip, standards, misconception],
      );
}

class ConsumerGuideLibrary {
  const ConsumerGuideLibrary({required this.categories, required this.items});

  factory ConsumerGuideLibrary.fromJson(Map<String, dynamic> json) =>
      ConsumerGuideLibrary(
        categories: (json['categories'] as List)
            .cast<Map<String, dynamic>>()
            .map(KnowledgeCategory.fromJson)
            .toList(),
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(ConsumerGuideItem.fromJson)
            .toList(),
      );

  final List<KnowledgeCategory> categories;
  final List<ConsumerGuideItem> items;

  List<ConsumerGuideItem> search(String query, {String? categoryId}) => items
      .where((item) => categoryId == null || item.categoryId == categoryId)
      .where((item) => item.matches(query))
      .toList();
}

class DrugInfoItem {
  const DrugInfoItem({
    required this.id,
    required this.number,
    required this.categoryId,
    required this.category,
    required this.name,
    required this.useTags,
    required this.riskSummary,
  });

  factory DrugInfoItem.fromJson(Map<String, dynamic> json) => DrugInfoItem(
        id: json['id'] as String,
        number: json['number'] as int,
        categoryId: json['categoryId'] as String,
        category: json['category'] as String,
        name: json['name'] as String,
        useTags: json['useTags'] as String,
        riskSummary: json['riskSummary'] as String,
      );

  final String id;
  final int number;
  final String categoryId;
  final String category;
  final String name;
  final String useTags;
  final String riskSummary;

  bool matches(String query) =>
      _matches(query, [name, category, useTags, riskSummary]);
}

class DrugInfoLibrary {
  const DrugInfoLibrary({required this.categories, required this.items});

  factory DrugInfoLibrary.fromJson(Map<String, dynamic> json) =>
      DrugInfoLibrary(
        categories: (json['categories'] as List)
            .cast<Map<String, dynamic>>()
            .map(KnowledgeCategory.fromJson)
            .toList(),
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(DrugInfoItem.fromJson)
            .toList(),
      );

  final List<KnowledgeCategory> categories;
  final List<DrugInfoItem> items;

  List<DrugInfoItem> search(String query, {String? categoryId}) => items
      .where((item) => categoryId == null || item.categoryId == categoryId)
      .where((item) => item.matches(query))
      .toList();
}

bool _matches(String query, Iterable<String> values) {
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return true;
  return values.any((value) => value.toLowerCase().contains(term));
}
