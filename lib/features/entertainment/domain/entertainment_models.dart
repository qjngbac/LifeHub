class EntertainmentCategory {
  const EntertainmentCategory({
    required this.id,
    required this.name,
    required this.group,
  });

  factory EntertainmentCategory.fromJson(Map<String, dynamic> json) =>
      EntertainmentCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        group: json['group'] as String,
      );

  final String id;
  final String name;
  final String group;
}

class EntertainmentItem {
  const EntertainmentItem({
    required this.id,
    required this.categoryId,
    required this.category,
    required this.group,
    required this.contentType,
    required this.title,
    required this.body,
    required this.estimatedReadSeconds,
  });

  factory EntertainmentItem.fromJson(Map<String, dynamic> json) =>
      EntertainmentItem(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        category: json['category'] as String,
        group: json['group'] as String,
        contentType: json['contentType'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        estimatedReadSeconds: json['estimatedReadSeconds'] as int,
      );

  final String id;
  final String categoryId;
  final String category;
  final String group;
  final String contentType;
  final String title;
  final String body;
  final int estimatedReadSeconds;

  bool matches(String query) {
    final term = query.trim().toLowerCase();
    return term.isEmpty ||
        title.toLowerCase().contains(term) ||
        body.toLowerCase().contains(term) ||
        category.toLowerCase().contains(term);
  }
}

class EntertainmentLibrary {
  const EntertainmentLibrary({required this.categories, required this.items});
  final List<EntertainmentCategory> categories;
  final List<EntertainmentItem> items;
}
