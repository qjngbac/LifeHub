import 'dart:convert';
import 'dart:io';

const _assetPath = r'assets\content\entertainment\content.json';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/merge_entertainment_documents.dart '
      '<target-markdown> [asset-json]',
    );
  }
  final documentFile = File(arguments.first);
  final assetPath = arguments.length > 1 ? arguments[1] : _assetPath;
  final asset =
      jsonDecode(File(assetPath).readAsStringSync()) as Map<String, dynamic>;
  final items = (asset['items'] as List).cast<Map<String, dynamic>>();
  final categories = (asset['categories'] as List).cast<Map<String, dynamic>>();
  if (items.length != 746 || categories.length != 32) {
    throw StateError(
      'Validated asset must contain 32 categories and 746 items; '
      'got ${categories.length}/${items.length}.',
    );
  }

  final original = documentFile.readAsStringSync();
  final contentStart = original.indexOf('# 13. 首批内容库');
  if (contentStart < 0) {
    throw StateError('Could not find the original content library section.');
  }
  var prefix = original.substring(0, contentStart).trimRight();
  prefix = prefix.replaceFirst(
    RegExp(r'> \*\*首批内容规模\*\*：.*'),
    '> **内置内容规模**：32 个分类，共 **746 条**精选离线内容。  ',
  );
  prefix = prefix.replaceAll('20 个叶子分类', '32 个分类');
  prefix = prefix.replaceAll('首批目标总量 **440 条**', '内置总量 **746 条**');

  final architectureStart = prefix.indexOf('## 2. 信息架构');
  final architectureEnd = prefix.indexOf('## 3. 实用入口');
  if (architectureStart < 0 || architectureEnd < 0) {
    throw StateError('Could not find information architecture section.');
  }
  prefix = '${prefix.substring(0, architectureStart)}'
      '${_architecture(categories)}\n\n---\n\n'
      '${prefix.substring(architectureEnd)}';

  final buffer = StringBuffer()
    ..writeln(prefix.trimRight())
    ..writeln()
    ..writeln('# 13. 内置内容库')
    ..writeln()
    ..writeln('> 笑话类使用 `content_type=joke`；脑筋急转弯使用 '
        '`content_type=riddle`；其余内容使用 `content_type=story`。')
    ..writeln('> 本节为应用唯一内容源，共 32 个分类、746 条内容。')
    ..writeln();

  for (final group in const ['joke', 'story', 'atmosphere']) {
    final groupCategories =
        categories.where((category) => category['group'] == group).toList();
    if (groupCategories.isEmpty) continue;
    buffer
      ..writeln('# ${_groupTitle(group)}')
      ..writeln();
    for (final category in groupCategories) {
      final categoryItems =
          items.where((item) => item['categoryId'] == category['id']).toList();
      buffer
        ..writeln('## ${category['name']}（${categoryItems.length} 条）')
        ..writeln();
      for (var index = 0; index < categoryItems.length; index++) {
        final item = categoryItems[index];
        buffer
          ..writeln('### ${index + 1}. ${item['title']}')
          ..writeln(item['body'])
          ..writeln();
      }
    }
  }

  documentFile.writeAsStringSync('${buffer.toString().trimRight()}\n');
  stdout.writeln(
    'Merged ${items.length} items into ${categories.length} categories at '
    '${documentFile.path}',
  );
}

String _architecture(List<Map<String, dynamic>> categories) {
  final buffer = StringBuffer()
    ..writeln('## 2. 信息架构：32 个分类')
    ..writeln()
    ..writeln('```text')
    ..writeln('笑话与故事');
  for (final group in const ['joke', 'story', 'atmosphere']) {
    final values =
        categories.where((category) => category['group'] == group).toList();
    buffer.writeln('├─ ${_groupTitle(group)}');
    for (var index = 0; index < values.length; index++) {
      final branch = index == values.length - 1 ? '└─' : '├─';
      buffer.writeln('│  $branch ${values[index]['name']}');
    }
  }
  buffer
    ..writeln('```')
    ..writeln()
    ..writeln('分类只用于浏览和随机筛选；全部内容仍使用统一的数据模型，'
        '不会为每个分类建立独立数据表。');
  return buffer.toString().trimRight();
}

String _groupTitle(String group) => switch (group) {
      'joke' => '😂 笑话',
      'atmosphere' => '🌙 氛围与短内容',
      _ => '📖 故事',
    };
