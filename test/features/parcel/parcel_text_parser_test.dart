import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/parcel/domain/parcel_text_parser.dart';

void main() {
  test('extracts labeled pickup code and tracking number as candidates', () {
    final value = ParcelTextParser.parse(
      '您的快递已到，取件码 3-12-8841，运单号 SF1234567890。',
    );
    expect(value.pickupCode, '3-12-8841');
    expect(value.trackingNumber, 'SF1234567890');
  });

  test('does not treat an unlabeled phone number as a parcel secret', () {
    final value = ParcelTextParser.parse('请联系 13800138000');
    expect(value.pickupCode, isNull);
    expect(value.trackingNumber, isNull);
  });
}
