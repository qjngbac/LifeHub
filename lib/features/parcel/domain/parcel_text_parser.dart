class ParcelTextCandidates {
  const ParcelTextCandidates({this.pickupCode, this.trackingNumber});

  final String? pickupCode;
  final String? trackingNumber;
}

abstract final class ParcelTextParser {
  static ParcelTextCandidates parse(String text) {
    final pickup = RegExp(
      r'(?:取件码|提货码|取货码)\s*[：:]?\s*([A-Za-z0-9-]{3,20})',
      caseSensitive: false,
    ).firstMatch(text);
    final tracking = RegExp(
      r'(?:运单号|快递单号|单号)\s*[：:]?\s*([A-Za-z]{0,4}\d{8,24})',
      caseSensitive: false,
    ).firstMatch(text);
    return ParcelTextCandidates(
      pickupCode: pickup?.group(1),
      trackingNumber: tracking?.group(1),
    );
  }
}
