import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/parcel/domain/parcel_text_parser.dart';

void main() {
  group('ParcelTextParser', () {
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

    test('extracts Cainiao Yizhan format: 凭 4-2-301 来取', () {
      final value = ParcelTextParser.parse(
        '【菜鸟驿站】凭 4-2-301 来取中通包裹，请于20点前取走，地址：幸福家园北门菜鸟驿站',
      );
      expect(value.carrier, '菜鸟驿站');
      expect(value.pickupCode, '4-2-301');
      expect(value.station, contains('菜鸟驿站'));
    });

    test('extracts Fengchao smart locker with 6-digit code', () {
      final value = ParcelTextParser.parse(
        '【丰巢】您的快件已暂存丰巢智能柜，取件码 882910，请尽快取出。',
      );
      expect(value.carrier, '丰巢');
      expect(value.pickupCode, '882910');
    });

    test('extracts Tuxi Shenghuo format with tracking number', () {
      final value = ParcelTextParser.parse(
        '【兔喜生活】您的中通包裹已到，请凭 5-18 到店取件，单号：758291048291',
      );
      expect(value.carrier, '兔喜生活');
      expect(value.pickupCode, '5-18');
      expect(value.trackingNumber, '758291048291');
    });

    test('extracts SF Express with brand tracking code', () {
      final value = ParcelTextParser.parse(
        '【顺丰速运】快件已送达，凭码【682103】前往物业中心领取，单号SF123456789012',
      );
      expect(value.carrier, '顺丰速运');
      expect(value.pickupCode, '682103');
      expect(value.trackingNumber, 'SF123456789012');
    });

    test('extracts JD format with pickup code', () {
      final value = ParcelTextParser.parse(
        '【京东快递】您的京东包裹已放自提点，提货码 482910，单号 JD00123456789',
      );
      expect(value.carrier, '京东快递');
      expect(value.pickupCode, '482910');
      expect(value.trackingNumber, 'JD00123456789');
    });

    test('does not misidentify date as pickup code', () {
      final value = ParcelTextParser.parse(
        '您的包裹预计 2026-10-15 送达，请留意电话。',
      );
      expect(value.pickupCode, isNull);
    });
  });
}
