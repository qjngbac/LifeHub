import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('search audit random entertainment keeps deferred group last', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = EntertainmentRepository(
      bundle: _TinyLibrary(),
      preferences: await SharedPreferences.getInstance(),
      random: _ZeroRandom(),
    );
    await repository.toggleBlocked('b');
    await repository.toggleDeferred('c');
    await repository.toggleDeferred('d');
    final sequence = await repository.randomSequence(group: 'joke');
    expect(sequence.map((item) => item.id), ['a', 'd', 'c']);
    expect(sequence.map((item) => item.id).toSet(), {'a', 'c', 'd'});
  });
}

class _ZeroRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

class _TinyLibrary extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'categories': [
            {'id': 'category', 'name': '测试', 'group': 'joke'},
          ],
          'items': [
            for (final id in ['a', 'b', 'c', 'd'])
              {
                'id': id,
                'categoryId': 'category',
                'category': '测试',
                'group': 'joke',
                'contentType': 'joke',
                'title': id,
                'body': id,
                'estimatedReadSeconds': 1,
              },
          ],
        }),
      ),
    ),
  );
}
