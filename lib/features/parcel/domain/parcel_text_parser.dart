class ParcelTextCandidates {
  const ParcelTextCandidates({
    this.pickupCode,
    this.trackingNumber,
    this.carrier,
    this.station,
  });

  final String? pickupCode;
  final String? trackingNumber;
  final String? carrier;
  final String? station;
}

abstract final class ParcelTextParser {
  static ParcelTextCandidates parse(String text) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return const ParcelTextCandidates();
    }

    // 1. 快递公司 / 驿站识别
    String? carrier;
    // 优先匹配短信签名标签：【菜鸟驿站】、【丰巢】、【兔喜生活】等
    final signMatch = RegExp(r'[【\[]([^】\]]+)[】\]]').firstMatch(raw);
    if (signMatch != null) {
      final sign = signMatch.group(1)!.trim();
      for (final name in _knownCarriers) {
        if (sign.contains(name)) {
          carrier = name;
          break;
        }
      }
      carrier ??= sign;
    }
    if (carrier == null) {
      for (final name in _knownCarriers) {
        if (raw.contains(name)) {
          carrier = name;
          break;
        }
      }
    }

    // 2. 快递单号识别
    String? trackingNumber;
    final trackingExplicit = RegExp(
      r'(?:运单号|快递单号|单号|包裹号)\s*[：:]?\s*([A-Za-z0-9]{8,26})',
      caseSensitive: false,
    ).firstMatch(raw);
    if (trackingExplicit != null) {
      final candidate = trackingExplicit.group(1)!;
      if (!_isPhoneNumber(candidate) && !_isDateTime(candidate)) {
        trackingNumber = candidate;
      }
    }
    if (trackingNumber == null) {
      final brandTracking = RegExp(
        r'\b(SF\d{12,15}|JD[A-Za-z0-9]{8,15}|YT\d{10,15}|JT\d{10,15}|STO\d{10,15})\b',
        caseSensitive: false,
      ).firstMatch(raw);
      if (brandTracking != null) {
        trackingNumber = brandTracking.group(1);
      }
    }

    // 3. 取件码识别
    String? pickupCode;
    // 3.1 显式关键字：取件码 / 提货码 / 取货码 / 提取码 / 开柜码 / 凭码 / 验证码
    final codeExplicit = RegExp(
      r'(?:取件码|提货码|取货码|提取码|开柜码|验证码|凭码|凭取件码)\s*[：:为是【\[]?\s*([A-Za-z0-9#-]{3,15})[】\]]?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (codeExplicit != null) {
      final cand = codeExplicit.group(1)!.trim();
      if (cand != trackingNumber && !_isPhoneNumber(cand) && !_isDateTime(cand)) {
        pickupCode = cand;
      }
    }

    // 3.2 菜鸟/兔喜/驿站常见格式：“凭 4-2-301 来取 / 取件 / 到店”
    if (pickupCode == null) {
      final pingMatch = RegExp(
        r'凭\s*[【\[]?\s*([A-Za-z0-9]+-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)?|[0-9]{3,8})\s*[】\]]?\s*(?:[来前往去到]|到店|取件|开柜|领取)',
        caseSensitive: false,
      ).firstMatch(raw);
      if (pingMatch != null) {
        final cand = pingMatch.group(1)!.trim();
        if (cand != trackingNumber && !_isPhoneNumber(cand) && !_isDateTime(cand)) {
          pickupCode = cand;
        }
      }
    }

    // 3.3 括号内的取件码格式：“【4-2-10】前往取件” 或 “请凭【4-2-301】”
    if (pickupCode == null) {
      final bracketMatch = RegExp(
        r'请?凭\s*[【\[]([A-Za-z0-9-]+)[】\]]',
      ).firstMatch(raw);
      if (bracketMatch != null) {
        final cand = bracketMatch.group(1)!.trim();
        if (cand != trackingNumber && !_isPhoneNumber(cand)) {
          pickupCode = cand;
        }
      }
    }

    // 3.4 独立连字符格式（如 3-12-8841 或 5-18 或 A-02-14）在含"取"或"驿站"的语境中
    if (pickupCode == null && (raw.contains('取') || raw.contains('驿站') || raw.contains('丰巢'))) {
      final hyphenMatch = RegExp(
        r'(?<!\d)(?:[A-Za-z0-9]{1,3}-\d{1,3}-\d{2,5}|\d{1,3}-\d{2,5})(?!\d)',
      ).firstMatch(raw);
      if (hyphenMatch != null) {
        final cand = hyphenMatch.group(0)!.trim();
        if (!_isDateTime(cand) && cand != trackingNumber) {
          pickupCode = cand;
        }
      }
    }

    // 4. 驿站 / 位置识别
    String? station;
    final stationMatch = RegExp(
      r'(?:地址|前往|到达|放至|暂存|送到|存放在)\s*[：:]?\s*([^\s,，。!！]{3,24}(?:驿站|快递超市|智能柜|自提点|小店|门卫|物业|超市|柜))',
    ).firstMatch(raw);
    if (stationMatch != null) {
      station = stationMatch.group(1)!.trim();
    }

    return ParcelTextCandidates(
      pickupCode: pickupCode,
      trackingNumber: trackingNumber,
      carrier: carrier,
      station: station,
    );
  }

  static const _knownCarriers = [
    '菜鸟驿站',
    '菜鸟速递',
    '菜鸟',
    '丰巢智能柜',
    '丰巢',
    '兔喜生活',
    '兔喜快递超市',
    '兔喜',
    '妈妈驿站',
    '快宝驿站',
    '顺丰速运',
    '顺丰',
    '京东快递',
    '京东',
    '中通快递',
    '中通',
    '圆通速递',
    '圆通',
    '申通快递',
    '申通',
    '韵达快递',
    '韵达超市',
    '韵达',
    '极兔速递',
    '极兔',
    '中国邮政',
    '邮政EMS',
    '邮政',
    '德邦快递',
    '德邦',
    '丹鸟',
  ];

  static bool _isPhoneNumber(String s) {
    if (RegExp(r'^1[3-9]\d{9}$').hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^\d{3,4}-\d{7,8}$').hasMatch(s)) {
      return true;
    }
    return false;
  }

  static bool _isDateTime(String s) {
    return RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(s) ||
        RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s);
  }
}
