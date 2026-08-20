import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/knowledge/domain/offline_knowledge_models.dart';

void main() {
  test('consumer guide contains all 431 products and supports local search',
      () {
    final raw =
        File('assets/content/consumer_guide/catalog.json').readAsStringSync();
    final library = ConsumerGuideLibrary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(library.categories, hasLength(18));
    expect(library.items, hasLength(431));
    expect(
        library.search('保温').any((item) => item.name.contains('保温')), isTrue);
    expect(library.items.every((item) => item.buyingTip.isNotEmpty), isTrue);
  });

  test('consumer guide does not reuse the electric toothbrush standard', () {
    final raw =
        File('assets/content/consumer_guide/catalog.json').readAsStringSync();
    final library = ConsumerGuideLibrary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    final toothpaste =
        library.search('牙膏').firstWhere((item) => item.name == '牙膏');
    final floss = library.search('牙线').firstWhere((item) => item.name == '牙线');
    final flossPick =
        library.search('牙线棒').firstWhere((item) => item.name == '牙线棒');
    expect(toothpaste.standards, contains('GB/T 8372-2017'));
    expect(floss.standards, contains('QB/T 4748-2014'));
    expect(flossPick.standards, contains('GB/T 41426-2022'));
    expect(
      library.items
          .where((item) => item.name != '电动牙刷')
          .where((item) => item.standards.contains('GB/T 40362-2021')),
      isEmpty,
    );
  });

  test('drug information contains all 728 names and safety fields', () {
    final raw =
        File('assets/content/drug_info/catalog.json').readAsStringSync();
    final library = DrugInfoLibrary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(library.categories, hasLength(32));
    expect(library.items, hasLength(728));
    final ibuprofen = library.search('布洛芬').single;
    expect(ibuprofen.useTags, isNotEmpty);
    expect(ibuprofen.riskSummary, isNotEmpty);
  });
}
