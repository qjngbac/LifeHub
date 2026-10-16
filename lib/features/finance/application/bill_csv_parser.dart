import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';
import 'package:lifehub/features/finance/application/pdf_bill_parser.dart';
import 'package:lifehub/features/finance/application/xlsx_bill_parser.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

enum BillSourceType {
  wechat,
  alipay,
  bank,
  unknown,
}

class ParsedBillItem {
  ParsedBillItem({
    required this.sourceType,
    required this.transactionTime,
    required this.direction,
    required this.amountMinor,
    required this.counterparty,
    required this.description,
    required this.orderId,
    required this.sourcePaymentMethod,
    required this.status,
    required this.category,
    required this.subCategory,
    required this.expenseNature,
    this.suggestedAccountType,
    this.tags = const [],
    this.isDuplicate = false,
    this.selected = true,
    this.assignedAccountId,
    this.assignedTargetAccountId,
  });

  final BillSourceType sourceType;
  final DateTime transactionTime;
  String direction; // EXPENSE, INCOME, TRANSFER
  final int amountMinor;
  final String counterparty;
  final String description;
  final String orderId;
  final String sourcePaymentMethod;
  final String status;
  String category;
  String? subCategory;
  String expenseNature; // NEED, WANT
  final String? suggestedAccountType;
  final List<String> tags;
  bool isDuplicate;
  bool selected;
  String? assignedAccountId;
  String? assignedTargetAccountId;

  String get deduplicationKey => orderId.isNotEmpty
      ? orderId
      : '${transactionTime.millisecondsSinceEpoch}_${amountMinor}_$counterparty';
}

class BillCsvParser {
  /// Entry point for raw file bytes (supports .xlsx, .zip, .csv, .txt, .tsv).
  static List<ParsedBillItem> parseBytes(List<int> bytes,
      {String? fileName, Map<String, UserMerchantRule>? customRules}) {
    if (bytes.isEmpty) return [];

    final nameLower = (fileName ?? '').toLowerCase();

    // 0. Check if it's a PDF (%PDF signature or .pdf extension)
    final isPdf = nameLower.endsWith('.pdf') || PdfBillParser.isPdf(bytes);
    if (isPdf) {
      final items = PdfBillParser.parseBytes(bytes, customRules: customRules);
      if (items.isNotEmpty) return items;
    }

    // 1. Check if it's a ZIP / XLSX archive (PK\x03\x04 signature)
    final isZipOrXlsx = nameLower.endsWith('.xlsx') ||
        nameLower.endsWith('.zip') ||
        (bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04);

    if (isZipOrXlsx) {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        // Check for Excel workbook
        final hasXlsxSheet = archive.files.any((f) =>
            f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'));
        if (hasXlsxSheet) {
          final items = XlsxBillParser.parseBytes(bytes, customRules: customRules);
          if (items.isNotEmpty) return items;
        }

        // Check for CSV/TSV inside zip
        for (final f in archive.files) {
          final fName = f.name.toLowerCase();
          if (f.isFile &&
              (fName.endsWith('.csv') ||
                  fName.endsWith('.txt') ||
                  fName.endsWith('.tsv'))) {
            final uncompressedBytes = f.content as List<int>;
            final text = _decodeBytes(uncompressedBytes);
            final items = parse(text, customRules: customRules);
            if (items.isNotEmpty) return items;
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to decoding raw bytes to string and parsing
    final text = _decodeBytes(bytes);
    return parse(text, customRules: customRules);
  }

  static String _decodeBytes(List<int> bytes) {
    List<int> clean = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      clean = bytes.sublist(3);
    }
    // 1. Standard UTF-8 first
    try {
      final text = utf8.decode(clean);
      return text;
    } catch (_) {}

    // 2. GBK / GB18030 (standard encoding for Alipay CSV export)
    try {
      final text = gbk.decode(clean);
      return text;
    } catch (_) {}

    // 3. Fallback to permissive UTF-8
    return utf8.decode(clean, allowMalformed: true);
  }

  /// Parses text content (auto-detects tab vs comma delimiter).
  static List<ParsedBillItem> parse(String csvContent,
      {Map<String, UserMerchantRule>? customRules}) {
    if (csvContent.trim().isEmpty) return [];
    final rows = _splitRows(csvContent);
    return parseMatrix(rows, customRules: customRules);
  }

  /// Splits content into 2D rows, auto-detecting Tab or Comma delimiters.
  static List<List<dynamic>> _splitRows(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    int tabCount = 0;
    int commaCount = 0;
    for (int i = 0; i < lines.length && i < 40; i++) {
      tabCount += '\t'.allMatches(lines[i]).length;
      commaCount += ','.allMatches(lines[i]).length;
    }

    // If tabs are clearly dominant, treat as Tab-Separated Values (like Alipay receipts)
    if (tabCount > commaCount && tabCount > 3) {
      return lines
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.split('\t').map((c) => c.trim()).toList())
          .toList();
    }

    try {
      final decoded = csv.decode(content);
      if (decoded.isNotEmpty && decoded.any((r) => r.length >= 3)) {
        return decoded;
      }
    } catch (_) {}

    return lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          if (line.contains('\t')) {
            return line.split('\t').map((c) => c.trim()).toList();
          }
          return line.split(',').map((c) => c.trim()).toList();
        })
        .toList();
  }

  /// Parses a 2D matrix of rows (from CSV, TSV, or XLSX).
  static List<ParsedBillItem> parseMatrix(List<List<dynamic>> rows,
      {Map<String, UserMerchantRule>? customRules}) {
    if (rows.isEmpty) return [];

    final allText = rows.take(30).map((r) => r.join(' ')).join('\n');
    final detected = detectSourceType(allText);

    if (detected == BillSourceType.alipay) {
      final alipayItems = _parseAlipayRows(rows, customRules: customRules);
      if (alipayItems.isNotEmpty) return alipayItems;
      final wechatItems = _parseWeChatRows(rows, customRules: customRules);
      if (wechatItems.isNotEmpty) return wechatItems;
    } else {
      final wechatItems = _parseWeChatRows(rows, customRules: customRules);
      if (wechatItems.isNotEmpty) return wechatItems;
      final alipayItems = _parseAlipayRows(rows, customRules: customRules);
      if (alipayItems.isNotEmpty) return alipayItems;
    }

    return [];
  }

  static BillSourceType detectSourceType(String content) {
    if (content.contains('微信支付账单明细') ||
        content.contains('微信支付') ||
        (content.contains('交易单号') && content.contains('商户单号'))) {
      return BillSourceType.wechat;
    }
    if (content.contains('支付宝交易记录明细') ||
        content.contains('支付宝') ||
        content.contains('电子客户回单') ||
        (content.contains('交易订单号') && content.contains('商家订单号'))) {
      return BillSourceType.alipay;
    }
    return BillSourceType.unknown;
  }

  static List<ParsedBillItem> _parseWeChatRows(List<List<dynamic>> rows,
      {Map<String, UserMerchantRule>? customRules}) {
    if (rows.isEmpty) return [];

    int headerIndex = -1;
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length >= 4) {
        final rowStr = row.map((e) => e.toString().trim()).join(' ');
        // WeChat specific columns: 商户单号 or (商品 and not 商品说明) or 微信支付
        if (rowStr.contains('交易时间') &&
            (rowStr.contains('商户单号') ||
                (rowStr.contains('商品') && !rowStr.contains('商品说明')) ||
                rowStr.contains('微信支付'))) {
          headerIndex = i;
          break;
        }
      }
    }

    if (headerIndex == -1 || headerIndex >= rows.length - 1) return [];

    final header = rows[headerIndex].map((e) => e.toString().trim()).toList();
    final timeIdx = _findCol(header, ['交易时间']);
    final typeIdx = _findCol(header, ['交易类型']);
    final partyIdx = _findCol(header, ['交易对方']);
    final descIdx = _findCol(header, ['商品', '商品说明']);
    final flowIdx = _findCol(header, ['收/支']);
    final amountIdx = _findCol(header, ['金额(元)', '金额（元）', '金额']);
    final methodIdx = _findCol(header, ['支付方式', '收/付款方式']);
    final statusIdx = _findCol(header, ['当前状态', '交易状态']);
    final orderIdx = _findCol(header, ['交易单号', '交易订单号']);

    final items = <ParsedBillItem>[];

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= amountIdx || amountIdx == -1) continue;

      final timeStr = _getVal(row, timeIdx);
      final rawAmount = _getVal(row, amountIdx);
      final rawFlow = _getVal(row, flowIdx);
      final party = _getVal(row, partyIdx);
      final desc = _getVal(row, descIdx);
      final type = _getVal(row, typeIdx);
      final method = _getVal(row, methodIdx);
      final status = _getVal(row, statusIdx);
      final orderId = _getVal(row, orderIdx);

      final dt = _parseDateTime(timeStr);
      if (dt == null) continue;

      final amount = _parseAmountMinor(rawAmount);
      if (amount <= 0) continue;

      // Determine direction
      var direction = FinanceDirection.expense;
      if (rawFlow.contains('收入')) {
        direction = FinanceDirection.income;
      } else if (rawFlow.contains('其他') || rawFlow == '/' || rawFlow.isEmpty) {
        final combined = '$type $party $desc'.toLowerCase();
        final isBankInteraction = FinanceCategoryInferer.isGenuineBankCard(party) ||
            FinanceCategoryInferer.isGenuineBankCard(desc);

        if (isBankInteraction &&
            (combined.contains('充值') || combined.contains('提现'))) {
          // Bank card <-> WeChat transfer (零钱充值/零钱提现) => TRANSFER (不算收入也不算支出)
          direction = FinanceDirection.transfer;
        } else if (combined.contains('转到零钱') ||
            combined.contains('qq') ||
            combined.contains('收益') ||
            combined.contains('退款') ||
            combined.contains('奖励') ||
            combined.contains('羊毛') ||
            combined.contains('红包')) {
          // Outside money added to WeChat => INCOME (加入微信算收入)
          direction = FinanceDirection.income;
        } else if (combined.contains('零钱通') || combined.contains('理财通')) {
          direction = FinanceDirection.transfer;
        } else if (combined.contains('还款') || combined.contains('月付')) {
          direction = FinanceDirection.expense;
        } else if (combined.contains('充值')) {
          // Non-bank recharge (校园卡/一卡通/话费/电费等) => EXPENSE
          direction = FinanceDirection.expense;
        } else {
          continue; // Skip failed / refunded entries without amount flow
        }
      }

      // Check special transfer/withdraw scenarios (only if not explicitly income and not repayment)
      if (direction != FinanceDirection.income &&
          !type.contains('还款') &&
          !desc.contains('还款') &&
          !party.contains('还款') &&
          !type.contains('月付') &&
          !desc.contains('月付') &&
          !party.contains('月付') &&
          !party.contains('金融') &&
          !desc.contains('金融') &&
          (FinanceCategoryInferer.isGenuineBankCard(party) ||
              FinanceCategoryInferer.isGenuineBankCard(desc)) &&
          (type.contains('提现') ||
              party.contains('零钱通') ||
              desc.contains('零钱充值'))) {
        direction = FinanceDirection.transfer;
      }

      final inferResult = FinanceCategoryInferer.infer(
        direction: direction,
        counterparty: party,
        description: desc,
        rawType: type,
        transactionTime: dt,
        amountMinor: amount,
        customRules: customRules,
      );

      final tags = <String>[];
      if (type.contains('红包')) {
        tags.add('微信红包');
      }

      items.add(ParsedBillItem(
        sourceType: BillSourceType.wechat,
        transactionTime: dt,
        direction: inferResult.directionOverride ?? direction,
        amountMinor: amount,
        counterparty: party,
        description: desc.isNotEmpty ? desc : type,
        orderId: orderId,
        sourcePaymentMethod: method.isNotEmpty ? method : '微信支付',
        status: status,
        category: inferResult.category,
        subCategory: inferResult.subCategory,
        expenseNature: inferResult.expenseNature,
        suggestedAccountType: _inferAccountTypeFromMethod(method, isWechat: true),
        tags: tags,
      ));
    }

    return items;
  }

  static List<ParsedBillItem> _parseAlipayRows(List<List<dynamic>> rows,
      {Map<String, UserMerchantRule>? customRules}) {
    if (rows.isEmpty) return [];

    int headerIndex = -1;
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length >= 4) {
        final rowStr = row.map((e) => e.toString().trim()).join(' ');
        if (rowStr.contains('交易时间') &&
            (rowStr.contains('金额') ||
                rowStr.contains('金额（元）') ||
                rowStr.contains('收/支'))) {
          headerIndex = i;
          break;
        }
      }
    }

    if (headerIndex == -1 || headerIndex >= rows.length - 1) return [];

    final header = rows[headerIndex].map((e) => e.toString().trim()).toList();
    final timeIdx = _findCol(header, ['交易时间']);
    final catIdx = _findCol(header, ['交易分类']);
    final partyIdx = _findCol(header, ['交易对方']);
    final descIdx = _findCol(header, ['商品说明', '商品']);
    final dirIdx = _findCol(header, ['收/支']);
    final amountIdx = _findCol(header, ['金额（元）', '金额(元)', '金额']);
    final methodIdx = _findCol(header, ['收/付款方式', '收/付款', '支付方式']);
    final statusIdx = _findCol(header, ['交易状态', '当前状态']);
    final orderIdx = _findCol(header, ['交易订单号', '交易单号']);

    final items = <ParsedBillItem>[];

    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= 3) continue;

      final dt = _parseDateTime(_getVal(row, timeIdx));
      if (dt == null) continue;

      final alipayCat = _getVal(row, catIdx);
      final party = _getVal(row, partyIdx);
      final desc = _getVal(row, descIdx);
      final rawDir = _getVal(row, dirIdx);
      final amount = _parseAmountMinor(_getVal(row, amountIdx));
      final method = _getVal(row, methodIdx);
      final status = _getVal(row, statusIdx);
      final orderId = _getVal(row, orderIdx);

      // Skip closed / refunded transactions
      if (status.contains('关闭') ||
          status.contains('退款成功') ||
          status.contains('失败') ||
          status.contains('解冻')) {
        continue;
      }
      if (amount <= 0) continue;

      String direction = FinanceDirection.expense;
      if (rawDir.contains('不计') || rawDir == '/' || rawDir.isEmpty) {
        final combined = '$alipayCat $party $desc'.toLowerCase();
        // Activity rewards / withdrawals to wallet / platform income / interest => INCOME
        if (combined.contains('68元') ||
            combined.contains('奖励') ||
            combined.contains('收益') ||
            combined.contains('利息') ||
            combined.contains('分红') ||
            combined.contains('理财') ||
            combined.contains('红包') ||
            combined.contains('快手') ||
            combined.contains('抖音') ||
            combined.contains('已到账')) {
          direction = FinanceDirection.income;
        } else if (combined.contains('还款') || combined.contains('月付')) {
          direction = FinanceDirection.expense;
        } else if (combined.contains('提现')) {
          direction = FinanceDirection.transfer;
        } else if (combined.contains('充值') &&
            FinanceCategoryInferer.isGenuineBankCard(method)) {
          direction = FinanceDirection.transfer;
        } else if (combined.contains('充值') &&
            (method.isEmpty ||
                method == '/' ||
                method.contains('账户') ||
                method.contains('余额'))) {
          direction = FinanceDirection.transfer;
        } else if (combined.contains('充值')) {
          direction = FinanceDirection.expense;
        } else {
          direction = FinanceDirection.transfer;
        }
      } else if (rawDir.contains('收') || rawDir.contains('入')) {
        direction = FinanceDirection.income;
      } else if (rawDir.contains('支') || rawDir.contains('出')) {
        direction = FinanceDirection.expense;
      }

      // Check genuine bank transfer scenarios (only if not income and not repayment)
      if (direction != FinanceDirection.income &&
          !alipayCat.contains('还款') &&
          !desc.contains('还款') &&
          !party.contains('还款') &&
          !alipayCat.contains('月付') &&
          !desc.contains('月付') &&
          !party.contains('月付') &&
          !party.contains('金融') &&
          !desc.contains('金融') &&
          (desc.contains('普通充值') ||
              party.contains('普通充值') ||
              ((FinanceCategoryInferer.isGenuineBankCard(party) ||
                      FinanceCategoryInferer.isGenuineBankCard(desc)) &&
                  (alipayCat.contains('转账') ||
                      alipayCat.contains('充值') ||
                      alipayCat.contains('提现') ||
                      desc.contains('提现') ||
                      desc.contains('充值') ||
                      party.contains('余额宝'))))) {
        direction = FinanceDirection.transfer;
      }

      // Special check: Platform withdrawals and campaign rewards
      if (party.contains('快手') ||
          party.contains('北京达佳互联') ||
          desc.contains('快手提现') ||
          desc.contains('平台收益') ||
          party.contains('蚂蚁森林') ||
          desc.contains('现金红包')) {
        direction = FinanceDirection.income;
      }

      final inferResult = FinanceCategoryInferer.infer(
        direction: direction,
        counterparty: party,
        description: desc,
        rawType: alipayCat,
        transactionTime: dt,
        amountMinor: amount,
        customRules: customRules,
      );

      final tags = <String>[];
      if (alipayCat.contains('红包') || desc.contains('红包')) {
        tags.add('支付宝红包');
      }

      items.add(ParsedBillItem(
        sourceType: BillSourceType.alipay,
        transactionTime: dt,
        direction: inferResult.directionOverride ?? direction,
        amountMinor: amount,
        counterparty: party,
        description: desc.isNotEmpty ? desc : alipayCat,
        orderId: orderId,
        sourcePaymentMethod: method.isNotEmpty ? method : '支付宝',
        status: status,
        category: inferResult.category,
        subCategory: inferResult.subCategory,
        expenseNature: inferResult.expenseNature,
        suggestedAccountType: _inferAccountTypeFromMethod(method, isWechat: false),
        tags: tags,
      ));
    }

    return items;
  }

  static int _findCol(List<String> header, List<String> candidates) {
    for (int i = 0; i < header.length; i++) {
      final h = header[i];
      for (final c in candidates) {
        if (h == c || h.contains(c)) return i;
      }
    }
    return -1;
  }

  static String _getVal(List<dynamic> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].toString().trim();
  }

  static DateTime? _parseDateTime(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final normalized = clean.replaceAll('/', '-');
    final serial = double.tryParse(clean);
    if (serial != null && serial >= 30000 && serial <= 70000) {
      try {
        return DateTime(1899, 12, 30).add(Duration(milliseconds: (serial * 86400000).round()));
      } catch (_) {}
    }
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      try {
        final parts = normalized.split(' ');
        if (parts.length == 2) {
          final d = parts[0].split('-');
          final t = parts[1].split(':');
          if (d.length == 3 && t.length >= 2) {
            return DateTime(
              int.parse(d[0]),
              int.parse(d[1]),
              int.parse(d[2]),
              int.parse(t[0]),
              int.parse(t[1]),
              t.length > 2 ? int.parse(t[2]) : 0,
            );
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static int _parseAmountMinor(String text) {
    final clean = text.replaceAll('¥', '').replaceAll(',', '').trim();
    final val = double.tryParse(clean);
    if (val == null) return 0;
    return (val * 100).round();
  }

  static String? _inferAccountTypeFromMethod(String method,
      {required bool isWechat}) {
    final lower = method.toLowerCase();
    if (lower.contains('信用卡') || lower.contains('花呗')) {
      return FinanceAccountType.credit;
    }
    if (lower.contains('银行') ||
        lower.contains('储蓄卡') ||
        lower.contains('借记卡')) {
      return FinanceAccountType.debit;
    }
    if (lower.contains('零钱') || lower.contains('余额')) {
      return FinanceAccountType.wallet;
    }
    return isWechat ? FinanceAccountType.wallet : FinanceAccountType.wallet;
  }
}

class CategoryInferenceResult {
  CategoryInferenceResult({
    required this.category,
    required this.subCategory,
    required this.expenseNature,
    this.directionOverride,
  });

  final String category;
  final String? subCategory;
  final String expenseNature;
  final String? directionOverride;
}

class FinanceCategoryInferer {
  static bool isGenuineBankCard(String text) {
    final clean = text.toLowerCase();
    if (clean.contains('校园') ||
        clean.contains('一卡通') ||
        clean.contains('学生') ||
        clean.contains('饭卡') ||
        clean.contains('水卡') ||
        clean.contains('电卡') ||
        clean.contains('油卡') ||
        clean.contains('公交') ||
        clean.contains('会员') ||
        clean.contains('购物卡') ||
        clean.contains('礼品卡') ||
        clean.contains('充值卡')) {
      return false;
    }
    return clean.contains('银行') ||
        clean.contains('储蓄卡') ||
        clean.contains('借记卡') ||
        clean.contains('招商') ||
        clean.contains('农行') ||
        clean.contains('农业') ||
        clean.contains('建行') ||
        clean.contains('建设') ||
        clean.contains('工行') ||
        clean.contains('工商') ||
        clean.contains('中行') ||
        clean.contains('中国银行') ||
        clean.contains('交行') ||
        clean.contains('交通银行') ||
        clean.contains('邮储') ||
        clean.contains('邮政') ||
        clean.contains('浦发') ||
        clean.contains('民生') ||
        clean.contains('中信') ||
        clean.contains('光大') ||
        clean.contains('兴业') ||
        clean.contains('华夏') ||
        clean.contains('广发') ||
        clean.contains('平安') ||
        clean.contains('信用社') ||
        clean.contains('农商');
  }

  static CategoryInferenceResult infer({
    required String direction,
    required String counterparty,
    required String description,
    required String rawType,
    DateTime? transactionTime,
    int? amountMinor,
    Map<String, UserMerchantRule>? customRules,
  }) {
    // 0. Custom learned user merchant rules (highest priority)
    if (customRules != null && customRules.isNotEmpty && counterparty.trim().isNotEmpty) {
      final cp = counterparty.trim();
      final rule = customRules[cp] ??
          customRules.entries
              .where((e) => cp.contains(e.key) || e.key.contains(cp))
              .map((e) => e.value)
              .firstOrNull;
      if (rule != null) {
        return CategoryInferenceResult(
          category: rule.category,
          subCategory: rule.subCategory,
          expenseNature: rule.expenseNature ?? ExpenseNature.need,
        );
      }
    }

    final text = '$counterparty $description $rawType'.toLowerCase();

    // 1. Platform income / withdrawals (e.g. Kuaishou, Douyin)
    if ((text.contains('快手') ||
            text.contains('北京达佳互联') ||
            text.contains('抖音') ||
            text.contains('字节跳动') ||
            text.contains('平台收益')) &&
        (text.contains('提现') ||
            text.contains('收益') ||
            text.contains('分成') ||
            direction == FinanceDirection.income)) {
      return CategoryInferenceResult(
        category: 'PLATFORM_INCOME',
        subCategory: text.contains('快手') ? '快手提现' : '抖音收益',
        expenseNature: ExpenseNature.want,
        directionOverride: FinanceDirection.income,
      );
    }

    // 2. Strict Income Handling (When direction is already INCOME)
    if (direction == FinanceDirection.income) {
      if (text.contains('领68元') ||
          text.contains('活动') ||
          text.contains('奖励') ||
          text.contains('羊毛') ||
          text.contains('补贴') ||
          text.contains('领现金') ||
          text.contains('金币') ||
          text.contains('百度') ||
          text.contains('小说') ||
          text.contains('音乐') ||
          text.contains('剧场') ||
          text.contains('提现')) {
        String sub = '活动奖励';
        if (text.contains('百度') ||
            text.contains('小说') ||
            text.contains('音乐') ||
            text.contains('剧场')) {
          sub = '平台收益';
        }
        return CategoryInferenceResult(
          category: 'SIDE_INCOME',
          subCategory: sub,
          expenseNature: ExpenseNature.want,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('红包') || rawType.contains('红包')) {
        return CategoryInferenceResult(
          category: 'SOCIAL',
          subCategory: text.contains('微信') ? '微信红包' : '支付宝红包',
          expenseNature: ExpenseNature.want,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('转账') || rawType.contains('转账')) {
        return CategoryInferenceResult(
          category: 'SOCIAL',
          subCategory: '转账收款',
          expenseNature: ExpenseNature.need,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('退款') || rawType.contains('退款')) {
        return CategoryInferenceResult(
          category: 'OTHER_INCOME',
          subCategory: '售后退款',
          expenseNature: ExpenseNature.need,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('理财') ||
          text.contains('收益') ||
          text.contains('利息') ||
          text.contains('分红') ||
          text.contains('余额升级')) {
        return CategoryInferenceResult(
          category: 'INVESTMENT_INCOME',
          subCategory: '理财收益',
          expenseNature: ExpenseNature.need,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('工资') || text.contains('薪') || text.contains('代发')) {
        return CategoryInferenceResult(
          category: 'SALARY',
          subCategory: '基本工资',
          expenseNature: ExpenseNature.need,
          directionOverride: FinanceDirection.income,
        );
      }
      if (text.contains('兼职') || text.contains('劳务') || text.contains('稿酬')) {
        return CategoryInferenceResult(
          category: 'SIDE_INCOME',
          subCategory: '副业兼职',
          expenseNature: ExpenseNature.need,
          directionOverride: FinanceDirection.income,
        );
      }
      return CategoryInferenceResult(
        category: 'OTHER_INCOME',
        subCategory: '其他收入',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.income,
      );
    }

    // 3. Repayments and Credit Loans (还款 / 月付 / 金融借贷): ALWAYS EXPENSE!
    if (text.contains('还款') ||
        rawType.contains('还款') ||
        text.contains('月付') ||
        text.contains('美团金融') ||
        text.contains('京东金融') ||
        text.contains('度小满') ||
        text.contains('微粒贷') ||
        text.contains('分期乐') ||
        text.contains('借呗') ||
        text.contains('花呗') ||
        text.contains('白条') ||
        (text.contains('金融') && !text.contains('理财'))) {
      String sub = '信贷还款';
      if (text.contains('月付')) {
        sub = '月付还款';
      } else if (text.contains('信用卡')) {
        sub = '信用卡还款';
      } else if (text.contains('花呗')) {
        sub = '花呗还款';
      } else if (text.contains('白条') || text.contains('京东金融')) {
        sub = '白条还款';
      } else if (text.contains('分期')) {
        sub = '分期还款';
      }
      return CategoryInferenceResult(
        category: 'FINANCE_EXPENSE',
        subCategory: sub,
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }

    // 4. Campus Cards / One-Cards / School Recharges (校园一卡通 / 校园充值)
    final isCampusCard = text.contains('校园') ||
        text.contains('一卡通') ||
        text.contains('趣智') ||
        text.contains('饭卡') ||
        text.contains('水卡') ||
        (text.contains('大学') &&
            (text.contains('充值') ||
                text.contains('生活') ||
                text.contains('消费')));

    if (isCampusCard && !text.contains('住宿') && !text.contains('学费')) {
      return CategoryInferenceResult(
        category: 'EDUCATION',
        subCategory: '校园一卡通',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }

    // 5. Utilities & Merchant Recharges (Non-bank)
    if (text.contains('话费') ||
        text.contains('宽带') ||
        text.contains('移动') ||
        text.contains('联通') ||
        text.contains('电信')) {
      return CategoryInferenceResult(
        category: 'HOUSING',
        subCategory: '物业宽带',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }
    if (text.contains('电费') ||
        text.contains('水费') ||
        text.contains('燃气') ||
        text.contains('供热')) {
      return CategoryInferenceResult(
        category: 'HOUSING',
        subCategory: '水电燃气',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }
    if (text.contains('公交') ||
        text.contains('地铁') ||
        text.contains('交通卡') ||
        text.contains('琴岛通') ||
        text.contains('羊城通')) {
      return CategoryInferenceResult(
        category: 'TRANSPORT',
        subCategory: '公共交通',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }
    if (text.contains('游戏充值') ||
        text.contains('q币') ||
        text.contains('省钱卡')) {
      return CategoryInferenceResult(
        category: 'ENTERTAINMENT',
        subCategory: '游戏充值',
        expenseNature: ExpenseNature.want,
        directionOverride: FinanceDirection.expense,
      );
    }

    // 6. Genuine Bank Card Transfers (Only bank cards!)
    final isBankCard = isGenuineBankCard(text);
    if ((isBankCard &&
            (direction == FinanceDirection.transfer ||
                text.contains('提现') ||
                text.contains('充值'))) ||
        text.contains('普通充值') ||
        text.contains('零钱通') ||
        text.contains('理财通') ||
        text.contains('余额宝')) {
      String sub = '内部互转';
      if (text.contains('提现')) sub = '零钱提现';
      if (text.contains('充值') || text.contains('普通充值')) sub = '储蓄充值';
      return CategoryInferenceResult(
        category: 'TRANSFER',
        subCategory: sub,
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.transfer,
      );
    }

    // 7. Any other non-bank recharge -> EXPENSE
    if (text.contains('充值') && !isBankCard) {
      return CategoryInferenceResult(
        category: 'OTHER',
        subCategory: '商户储值',
        expenseNature: ExpenseNature.need,
        directionOverride: FinanceDirection.expense,
      );
    }

    // 4. Red packets for expense
    if (text.contains('红包') || rawType.contains('红包')) {
      return CategoryInferenceResult(
        category: 'SOCIAL',
        subCategory: text.contains('微信') ? '微信红包' : '支付宝红包',
        expenseNature: ExpenseNature.want,
      );
    }

    // 5. Personal Transfer / AA
    if (text.contains('群收款') || rawType.contains('群收款')) {
      return CategoryInferenceResult(
        category: 'FOOD',
        subCategory: '聚餐AA',
        expenseNature: ExpenseNature.need,
      );
    }
    if (text.contains('转账') || rawType.contains('转账')) {
      return CategoryInferenceResult(
        category: 'SOCIAL',
        subCategory: '人情转账',
        expenseNature: ExpenseNature.need,
      );
    }
    if (text.contains('还款') || rawType.contains('还款')) {
      return CategoryInferenceResult(
        category: 'FINANCE_EXPENSE',
        subCategory: '信贷还款',
        expenseNature: ExpenseNature.need,
      );
    }

    // 3. Expense Inferences
    // Food, Dining, Takeout, Groceries, Snacks
    final isConvenienceStore = text.contains('便利店') ||
        text.contains('罗森') ||
        text.contains('lawson') ||
        text.contains('全家') ||
        text.contains('family') ||
        text.contains('7-11') ||
        text.contains('7-eleven') ||
        text.contains('美宜佳') ||
        text.contains('喜士多') ||
        text.contains('见福') ||
        text.contains('超市') ||
        text.contains('永辉') ||
        text.contains('大润发') ||
        text.contains('华润') ||
        text.contains('沃尔玛') ||
        text.contains('盒马') ||
        text.contains('物美') ||
        text.contains('小卖部') ||
        text.contains('副食') ||
        text.contains('杂货') ||
        text.contains('日杂') ||
        text.contains('百货店');

    final isGroceryCooking = text.contains('买菜') ||
        text.contains('菜市场') ||
        text.contains('农贸') ||
        text.contains('生鲜') ||
        text.contains('叮咚') ||
        text.contains('朴朴') ||
        text.contains('菜店') ||
        text.contains('粮油');

    final isDrink = text.contains('咖啡') ||
        text.contains('星巴克') ||
        text.contains('starbucks') ||
        text.contains('瑞幸') ||
        text.contains('luckin') ||
        text.contains('喜茶') ||
        text.contains('heytea') ||
        text.contains('奈雪') ||
        text.contains('茶百道') ||
        text.contains('古茗') ||
        text.contains('蜜雪冰城') ||
        text.contains('一点点') ||
        text.contains('coco') ||
        text.contains('霸王茶姬') ||
        text.contains('沪上阿姨') ||
        text.contains('茶颜悦色') ||
        text.contains('饮品') ||
        text.contains('奶茶') ||
        text.contains('果汁');

    final isSnacksOrFruit = text.contains('水果') ||
        text.contains('鲜果') ||
        text.contains('百果园') ||
        text.contains('鲜丰') ||
        text.contains('果园') ||
        text.contains('零食') ||
        text.contains('坚果') ||
        text.contains('面包') ||
        text.contains('蛋糕') ||
        text.contains('西点') ||
        text.contains('烘焙') ||
        text.contains('点心') ||
        text.contains('糕点') ||
        text.contains('饼干') ||
        text.contains('糖') ||
        text.contains('鸭脖') ||
        text.contains('绝味') ||
        text.contains('周黑鸭') ||
        text.contains('卤味') ||
        text.contains('熟食') ||
        text.contains('鲍师傅') ||
        text.contains('好利来') ||
        text.contains('良品铺子') ||
        text.contains('三只松鼠') ||
        text.contains('丰 e 足食') ||
        text.contains('丰e足食') ||
        text.contains('自动售货') ||
        text.contains('智慧零售') ||
        text.contains('售货机') ||
        text.contains('友宝') ||
        text.contains('百草味');

    final isEcommerceFood = (text.contains('淘宝') ||
            text.contains('天猫') ||
            text.contains('京东') ||
            text.contains('拼多多') ||
            text.contains('电商') ||
            text.contains('商城') ||
            text.contains('专营店') ||
            text.contains('旗舰店')) &&
        (text.contains('食品') ||
            text.contains('零食') ||
            text.contains('特产') ||
            text.contains('速食') ||
            text.contains('烘焙') ||
            text.contains('冲饮') ||
            text.contains('奶粉') ||
            text.contains('麦片') ||
            text.contains('茶叶') ||
            text.contains('生鲜') ||
            text.contains('水果'));

    final isFoodOrDining = isDrink ||
        isEcommerceFood ||
        isSnacksOrFruit ||
        isGroceryCooking ||
        isConvenienceStore ||
        text.contains('美团') ||
        text.contains('饿了么') ||
        text.contains('麦当劳') ||
        text.contains('肯德基') ||
        text.contains('汉堡王') ||
        text.contains('德克士') ||
        text.contains('华莱士') ||
        text.contains('塔斯汀') ||
        text.contains('外卖') ||
        text.contains('餐饮') ||
        text.contains('美食') ||
        text.contains('闪购') ||
        text.contains('馄饨') ||
        text.contains('便当') ||
        text.contains('快餐') ||
        text.contains('烧烤') ||
        text.contains('火锅') ||
        text.contains('面馆') ||
        text.contains('饭店') ||
        text.contains('餐厅') ||
        text.contains('食堂') ||
        text.contains('档口') ||
        text.contains('餐饮中心') ||
        text.contains('食品');

    if (isFoodOrDining) {
      if (isDrink) {
        return CategoryInferenceResult(
          category: 'FOOD',
          subCategory: '咖啡奶茶',
          expenseNature: ExpenseNature.want,
        );
      }
      if (isEcommerceFood || isSnacksOrFruit) {
        return CategoryInferenceResult(
          category: 'FOOD',
          subCategory: '零食水果',
          expenseNature: ExpenseNature.want,
        );
      }
      if (isGroceryCooking) {
        return CategoryInferenceResult(
          category: 'FOOD',
          subCategory: '买菜做饭',
          expenseNature: ExpenseNature.need,
        );
      }
      if (isConvenienceStore) {
        return CategoryInferenceResult(
          category: 'FOOD',
          subCategory: '商超便利',
          expenseNature: ExpenseNature.need,
        );
      }

      // If large amount dine-out or hotpot / party
      if ((amountMinor != null && amountMinor >= 15000) ||
          text.contains('海底捞') ||
          text.contains('酒楼') ||
          text.contains('聚餐')) {
        return CategoryInferenceResult(
          category: 'FOOD',
          subCategory: '朋友聚餐',
          expenseNature: ExpenseNature.want,
        );
      }

      // Three meals / Takeout time-based inference
      final hour = transactionTime?.hour;
      String sub = '外卖便当';
      String nature = ExpenseNature.need;

      if (hour != null) {
        if (hour >= 5 && hour < 10) {
          sub = '早餐饮食';
          nature = ExpenseNature.need;
        } else if (hour >= 10 && hour < 15) {
          sub = '外卖午餐';
          nature = ExpenseNature.need;
        } else if (hour >= 15 && hour < 17) {
          sub = '外卖午餐';
          nature = ExpenseNature.need;
        } else if (hour >= 17 && hour < 21) {
          sub = '外卖晚餐';
          nature = ExpenseNature.need;
        } else {
          sub = '夜宵外卖';
          nature = ExpenseNature.want;
        }
      }

      return CategoryInferenceResult(
        category: 'FOOD',
        subCategory: sub,
        expenseNature: nature,
      );
    }

    // Transport
    if (text.contains('滴滴') ||
        text.contains('高德') ||
        text.contains('打车') ||
        text.contains('曹操') ||
        text.contains('t3') ||
        text.contains('地铁') ||
        text.contains('公交') ||
        text.contains('12306') ||
        text.contains('铁路') ||
        text.contains('火车') ||
        text.contains('航空') ||
        text.contains('机票') ||
        text.contains('加油') ||
        text.contains('石化') ||
        text.contains('石油') ||
        text.contains('特来电') ||
        text.contains('停车') ||
        text.contains('高速') ||
        text.contains('过路费') ||
        text.contains('喜德盛') ||
        text.contains('山地车') ||
        text.contains('公路车') ||
        text.contains('单车') ||
        text.contains('自行车') ||
        text.contains('挡泥板') ||
        text.contains('链条油') ||
        text.contains('除锈剂') ||
        text.contains('骑行') ||
        text.contains('修车')) {
      String sub = '公交地铁';
      String nature = ExpenseNature.need;
      if (text.contains('滴滴') || text.contains('打车') || text.contains('高德')) {
        sub = '打车出行';
        nature = ExpenseNature.want;
      } else if (text.contains('喜德盛') ||
          text.contains('山地车') ||
          text.contains('公路车') ||
          text.contains('单车') ||
          text.contains('自行车') ||
          text.contains('挡泥板') ||
          text.contains('链条油') ||
          text.contains('除锈剂') ||
          text.contains('骑行') ||
          text.contains('修车')) {
        sub = '车辆维保';
      } else if (text.contains('加油') ||
          text.contains('石化') ||
          text.contains('石油') ||
          text.contains('特来电')) {
        sub = '加油充电';
      } else if (text.contains('12306') ||
          text.contains('铁路') ||
          text.contains('机票') ||
          text.contains('航空')) {
        sub = '机票火车';
      } else if (text.contains('停车') || text.contains('高速')) {
        sub = '停车过路';
      }
      return CategoryInferenceResult(
        category: 'TRANSPORT',
        subCategory: sub,
        expenseNature: nature,
      );
    }

    // Housing & Utilities
    if (text.contains('房租') ||
        text.contains('自如') ||
        text.contains('电费') ||
        text.contains('水费') ||
        text.contains('燃气') ||
        text.contains('物业') ||
        text.contains('宽带') ||
        text.contains('电信') ||
        text.contains('移动') ||
        text.contains('联通') ||
        text.contains('话费') ||
        text.contains('五金') ||
        text.contains('建材') ||
        text.contains('顺丰') ||
        text.contains('快递') ||
        text.contains('圆通') ||
        text.contains('中通') ||
        text.contains('申通') ||
        text.contains('韵达') ||
        text.contains('极兔') ||
        text.contains('菜鸟') ||
        text.contains('散单运费')) {
      String sub = '水电燃气';
      if (text.contains('房租') || text.contains('自如')) sub = '房租房贷';
      if (text.contains('物业') || text.contains('宽带')) sub = '物业宽带';
      if (text.contains('五金') || text.contains('建材')) sub = '家居维修';
      if (text.contains('顺丰') ||
          text.contains('快递') ||
          text.contains('运费') ||
          text.contains('菜鸟')) {
        sub = '日用耗材';
      }
      return CategoryInferenceResult(
        category: 'HOUSING',
        subCategory: sub,
        expenseNature: ExpenseNature.need,
      );
    }

    // Charity & Social Donations
    if (text.contains('壹基金') ||
        text.contains('公益') ||
        text.contains('慈善') ||
        text.contains('困境儿童') ||
        text.contains('红十字') ||
        text.contains('爱心捐款')) {
      return CategoryInferenceResult(
        category: 'SOCIAL',
        subCategory: '公益慈善',
        expenseNature: ExpenseNature.want,
      );
    }

    // Cloud, Server & Developer Services
    if (text.contains('deepseek') ||
        text.contains('深度求索') ||
        text.contains('阿里云') ||
        text.contains('腾讯云') ||
        text.contains('华为云') ||
        text.contains('百度云') ||
        text.contains('api服务') ||
        text.contains('服务器') ||
        text.contains('域名')) {
      return CategoryInferenceResult(
        category: 'STUDY',
        subCategory: '培训课程',
        expenseNature: ExpenseNature.need,
      );
    }

    // Cosmetics & Skincare
    if (text.contains('面膜') ||
        text.contains('烟酰胺') ||
        text.contains('玻尿酸') ||
        text.contains('壬二酸') ||
        text.contains('祛痘') ||
        text.contains('乳霜') ||
        text.contains('面霜') ||
        text.contains('洁面') ||
        text.contains('防晒') ||
        text.contains('爽肤水') ||
        text.contains('精华') ||
        text.contains('唇膏') ||
        text.contains('口红') ||
        text.contains('护肤') ||
        text.contains('美妆')) {
      return CategoryInferenceResult(
        category: 'SHOPPING',
        subCategory: '美妆个护',
        expenseNature: ExpenseNature.want,
      );
    }

    // Daily Necessities & Shopping
    if (text.contains('淘宝') ||
        text.contains('天猫') ||
        text.contains('京东') ||
        text.contains('拼多多') ||
        text.contains('唯品会') ||
        text.contains('1688') ||
        text.contains('16688') ||
        text.contains('抖音电商') ||
        text.contains('快手电商') ||
        text.contains('牙刷') ||
        text.contains('名创优品') ||
        text.contains('肥皂') ||
        text.contains('香皂') ||
        text.contains('硫磺皂') ||
        text.contains('搓澡巾') ||
        text.contains('纸巾') ||
        text.contains('卫生纸') ||
        text.contains('抽纸') ||
        text.contains('餐巾纸') ||
        text.contains('厕纸') ||
        text.contains('置物架') ||
        text.contains('肥皂盒') ||
        text.contains('收纳') ||
        text.contains('垃圾袋') ||
        text.contains('洗衣液') ||
        text.contains('洗洁精') ||
        text.contains('洗发水') ||
        text.contains('沐浴露') ||
        text.contains('毛巾') ||
        text.contains('梳子') ||
        text.contains('服装') ||
        text.contains('服饰') ||
        text.contains('数码') ||
        text.contains('手机') ||
        text.contains('电脑') ||
        text.contains('优衣库')) {
      String sub = '日用百货';
      String nature = ExpenseNature.need;
      if (text.contains('数码') || text.contains('手机') || text.contains('电脑')) {
        sub = '数码电器';
        nature = ExpenseNature.want;
      } else if (text.contains('服装') || text.contains('服饰') || text.contains('优衣库')) {
        sub = '服饰鞋包';
        nature = ExpenseNature.want;
      }
      return CategoryInferenceResult(
        category: 'SHOPPING',
        subCategory: sub,
        expenseNature: nature,
      );
    }

    // Medical
    if (text.contains('医疗') ||
        text.contains('医院') ||
        text.contains('门诊') ||
        text.contains('药') ||
        text.contains('诊所') ||
        text.contains('软膏') ||
        text.contains('保健') ||
        text.contains('卫健')) {
      return CategoryInferenceResult(
        category: 'MEDICAL',
        subCategory: text.contains('挂号') || text.contains('门诊') ? '门诊挂号' : '药品购买',
        expenseNature: ExpenseNature.need,
      );
    }

    // Entertainment
    if (text.contains('电影') ||
        text.contains('影城') ||
        text.contains('万达') ||
        text.contains('游戏') ||
        text.contains('steam') ||
        text.contains('网易') ||
        text.contains('腾讯') ||
        text.contains('旅游') ||
        text.contains('携程') ||
        text.contains('去哪儿') ||
        text.contains('同程') ||
        text.contains('民宿') ||
        text.contains('酒店')) {
      String sub = '旅游度假';
      if (text.contains('电影') || text.contains('影城')) sub = '电影演出';
      if (text.contains('游戏') || text.contains('steam')) sub = '游戏娱乐';
      return CategoryInferenceResult(
        category: 'ENTERTAINMENT',
        subCategory: sub,
        expenseNature: ExpenseNature.want,
      );
    }

    // Campus & Education
    if (text.contains('大学') ||
        text.contains('学院') ||
        text.contains('学校') ||
        text.contains('校园') ||
        text.contains('学费') ||
        text.contains('住宿费') ||
        text.contains('趣智') ||
        text.contains('培训') ||
        text.contains('课程')) {
      String sub = '学杂费';
      if (text.contains('住宿费')) sub = '住宿费';
      if (text.contains('校园') ||
          text.contains('校园卡') ||
          text.contains('校园充值') ||
          text.contains('趣智')) {
        sub = '校园生活';
      }
      return CategoryInferenceResult(
        category: 'EDUCATION',
        subCategory: sub,
        expenseNature: ExpenseNature.need,
      );
    }

    // Default fallback
    return CategoryInferenceResult(
      category: 'OTHER',
      subCategory: '日常杂项',
      expenseNature: ExpenseNature.need,
    );
  }
}
