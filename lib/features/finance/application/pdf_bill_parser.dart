import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

/// Parses Bank and Financial Statement PDF exports (including China Merchants Bank, etc.)
class PdfBillParser {
  /// Checks whether the raw bytes start with the PDF signature `%PDF` (0x25, 0x50, 0x44, 0x46).
  static bool isPdf(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  /// Parses raw PDF bytes and returns recognized bill items.
  static List<ParsedBillItem> parseBytes(
    List<int> bytes, {
    String? password,
    Map<String, UserMerchantRule>? customRules,
  }) {
    if (bytes.isEmpty || !isPdf(bytes)) return [];

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes, password: password);
      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        buffer.writeln(extractor.extractText(startPageIndex: i, endPageIndex: i));
        buffer.writeln();
      }
      final text = buffer.toString();
      return parseText(text, customRules: customRules);
    } catch (_) {
      return [];
    } finally {
      document?.dispose();
    }
  }

  /// Parses the extracted text representation of the PDF.
  static List<ParsedBillItem> parseText(
    String text, {
    Map<String, UserMerchantRule>? customRules,
  }) {
    if (text.trim().isEmpty) return [];

    // 1. Check for China Merchants Bank (招商银行交易流水)
    if (_isChinaMerchantsBank(text)) {
      final cmbItems = _parseChinaMerchantsBank(text, customRules: customRules);
      if (cmbItems.isNotEmpty) return cmbItems;
    }

    // 2. Generic bank / statement text parser fallback
    return _parseGenericBankStatement(text, customRules: customRules);
  }

  static bool _isChinaMerchantsBank(String text) {
    return text.contains('招商银行') ||
        text.contains('China Merchants Bank') ||
        (text.contains('联机余额') && text.contains('交易摘要'));
  }

  /// Specialized parser for China Merchants Bank (招商银行交易流水 PDF).
  static List<ParsedBillItem> _parseChinaMerchantsBank(
    String text, {
    Map<String, UserMerchantRule>? customRules,
  }) {
    final items = <ParsedBillItem>[];

    // Extract Account Metadata
    String? ownerName;
    final ownerMatch = RegExp(r'户\s*名[：:]\s*([^\r\n]*)').firstMatch(text);
    if (ownerMatch != null) {
      final val = ownerMatch.group(1)?.trim();
      if (val != null && val.isNotEmpty && val != 'Name') {
        ownerName = val;
      } else {
        // Next line might contain the actual name
        final rest = text.substring(ownerMatch.end).trimLeft();
        final firstLine = rest.split(RegExp(r'[\r\n]+')).firstOrNull?.trim();
        if (firstLine != null &&
            firstLine.isNotEmpty &&
            firstLine != 'Name' &&
            !firstLine.contains('账户类型')) {
          ownerName = firstLine;
        }
      }
    }

    // Extract Card / Account Number
    String? cardLastFour;
    final accMatch = RegExp(r'账号[：:]\s*([0-9*]+)').firstMatch(text);
    if (accMatch != null) {
      final fullAcc = accMatch.group(1) ?? '';
      final digits = fullAcc.replaceAll('*', '').trim();
      if (digits.length >= 4) {
        cardLastFour = digits.substring(digits.length - 4);
      }
    }

    // Process lines
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final dateRegex = RegExp(r'^(\d{4}-\d{2}-\d{2})$');
    final amountRegex = RegExp(r'^-?[\d,]+(\.\d{2})?$');
    final currencyRegex = RegExp(r'^[A-Z]{3}$');

    int index = 0;
    int recordIndex = 0;

    while (index < lines.length) {
      final line = lines[index];
      final dateMatch = dateRegex.firstMatch(line);

      if (dateMatch == null) {
        index++;
        continue;
      }

      // Found row start: line is date
      final dateStr = dateMatch.group(1)!;
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate == null) {
        index++;
        continue;
      }

      index++;
      if (index >= lines.length) break;

      // Currency line (e.g. CNY)
      String currency = 'CNY';
      if (currencyRegex.hasMatch(lines[index])) {
        currency = lines[index];
        index++;
      }
      if (index >= lines.length) break;

      // Amount line (e.g. 102.00 or -0.01 or 2,000.00)
      if (!amountRegex.hasMatch(lines[index])) {
        continue;
      }
      final rawAmountStr = lines[index].replaceAll(',', '');
      final amountVal = double.tryParse(rawAmountStr);
      if (amountVal == null) {
        index++;
        continue;
      }
      index++;
      if (index >= lines.length) break;

      // Balance line (e.g. 102.00 or 2,109.81)
      if (amountRegex.hasMatch(lines[index])) {
        index++;
      }
      if (index >= lines.length) break;

      // Transaction Type / Summary line (e.g. 网联收款, 快捷支付, 享定存开户起息)
      String transactionType = '';
      if (index < lines.length && !dateRegex.hasMatch(lines[index])) {
        transactionType = lines[index];
        index++;
      }

      // Counterparty lines: gather until next date or footer
      final counterPartyParts = <String>[];
      while (index < lines.length) {
        final cur = lines[index];
        if (dateRegex.hasMatch(cur)) {
          break; // Next transaction start
        }
        if (_isPageFooterOrHeader(cur)) {
          index++;
          continue;
        }
        counterPartyParts.add(cur);
        index++;
      }

      final counterParty = counterPartyParts.join(' ').trim();
      final item = _buildCmbBillItem(
        date: parsedDate,
        amountVal: amountVal,
        transactionType: transactionType,
        counterParty: counterParty,
        currency: currency,
        ownerName: ownerName,
        cardLastFour: cardLastFour,
        recordIndex: ++recordIndex,
        customRules: customRules,
      );

      if (item != null) {
        items.add(item);
      }
    }

    return items;
  }

  static bool _isPageFooterOrHeader(String line) {
    if (line.startsWith('温馨提示') ||
        line.contains('交易流水验真') ||
        line.contains('电子回单专用章') ||
        line.contains('招商银行股份有限公司') ||
        RegExp(r'^\d+\s*/\s*\d+$').hasMatch(line) ||
        line == '记账日期' ||
        line == '货币' ||
        line == '交易金额' ||
        line == '联机余额' ||
        line == '交易摘要' ||
        line == '对手信息' ||
        line == 'Date' ||
        line == 'Currency' ||
        line == 'Transaction' ||
        line == 'Amount' ||
        line == 'Balance' ||
        line == 'Transaction Type' ||
        line == 'Counter Party') {
      return true;
    }
    return false;
  }

  static ParsedBillItem? _buildCmbBillItem({
    required DateTime date,
    required double amountVal,
    required String transactionType,
    required String counterParty,
    required String currency,
    required String? ownerName,
    required String? cardLastFour,
    required int recordIndex,
    Map<String, UserMerchantRule>? customRules,
  }) {
    final amountMinor = (amountVal.abs() * 100).round();
    if (amountMinor == 0) return null;

    final dateKey = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final cardSuffix = cardLastFour ?? 'CMB';
    final orderId = 'CMB_${cardSuffix}_${dateKey}_${amountMinor}_$recordIndex';

    // 核心判定规则：
    // 用户明确指定：如果对手信息是“李小辉”（或户名本人），判定为不同账号之间的转账（TRANSFER），
    // 既不是收入也不是支出！
    final isSelfTransfer = _isCounterpartySelf(counterParty, ownerName);

    String direction;
    String category;
    String? subCategory;
    String expenseNature = ExpenseNature.need;

    if (isSelfTransfer) {
      direction = FinanceDirection.transfer;
      category = 'TRANSFER';
      if (transactionType.contains('定存') || transactionType.contains('享定存')) {
        subCategory = amountVal < 0 ? '定存理财' : '定存支取';
      } else if (transactionType.contains('网联收款')) {
        subCategory = '账户转入';
      } else if (transactionType.contains('快捷支付')) {
        subCategory = '账户转出';
      } else {
        subCategory = '内部转账';
      }
    } else {
      if (amountVal < 0) {
        // 支出 (EXPENSE)
        direction = FinanceDirection.expense;
        final inferred = FinanceCategoryInferer.infer(
          direction: direction,
          counterparty: counterParty,
          description: transactionType,
          rawType: transactionType,
          transactionTime: date,
          amountMinor: amountMinor,
          customRules: customRules,
        );
        category = inferred.category;
        subCategory = inferred.subCategory;
        expenseNature = inferred.expenseNature;

        // CMB 特色对手补充清洗
        if (category == 'OTHER' || subCategory == null || subCategory == '未分类') {
          final cpLower = counterParty.toLowerCase();
          if (cpLower.contains('拉扎斯')) {
            category = 'FOOD';
            subCategory = '外卖午餐';
          } else if (cpLower.contains('餐饮') || cpLower.contains('索丰')) {
            category = 'FOOD';
            subCategory = '外卖午餐';
          } else if (cpLower.contains('理工大学') || cpLower.contains('大学')) {
            category = 'EDUCATION';
            subCategory = '校园一卡通';
          } else if (cpLower.contains('chatgpt') || cpLower.contains('google')) {
            category = 'OTHER';
            subCategory = '软件服务';
          } else if (cpLower.contains('昶鑫') || cpLower.contains('淘宝')) {
            category = 'SHOPPING';
            subCategory = '日用百货';
          }
        }
      } else {
        // 收入 (INCOME)
        direction = FinanceDirection.income;
        if (transactionType.contains('鼓励金') || counterParty.contains('鼓励金')) {
          category = 'SIDE_INCOME';
          subCategory = '活动奖励';
        } else if (transactionType.contains('结息') || counterParty.contains('利息')) {
          category = 'INVESTMENT_INCOME';
          subCategory = '利息入账';
        } else if (transactionType.contains('退货') ||
            transactionType.contains('退款') ||
            counterParty.contains('退货') ||
            counterParty.contains('退款')) {
          category = 'OTHER_INCOME';
          subCategory = '退款返还';
        } else {
          final inferred = FinanceCategoryInferer.infer(
            direction: direction,
            counterparty: counterParty,
            description: transactionType,
            rawType: transactionType,
            transactionTime: date,
            amountMinor: amountMinor,
            customRules: customRules,
          );
          category = inferred.category;
          subCategory = inferred.subCategory;
          expenseNature = inferred.expenseNature;
        }
      }
    }

    final cardDisplay = cardLastFour != null ? '招商银行借记卡($cardLastFour)' : '招商银行卡';

    return ParsedBillItem(
      sourceType: BillSourceType.bank,
      transactionTime: date,
      direction: direction,
      amountMinor: amountMinor,
      counterparty: counterParty.isNotEmpty ? counterParty : (isSelfTransfer ? '本人账户' : '招商银行'),
      description: transactionType.isNotEmpty ? transactionType : '银行流水',
      orderId: orderId,
      sourcePaymentMethod: cardDisplay,
      status: '交易成功',
      category: category,
      subCategory: subCategory,
      expenseNature: expenseNature,
      suggestedAccountType: FinanceAccountType.debit,
      selected: true,
    );
  }

  /// Checks if the counterparty refers to the account owner itself.
  static bool _isCounterpartySelf(String counterParty, String? ownerName) {
    final cp = counterParty.trim();
    if (cp.isEmpty) return false;

    // Direct match with 李小辉
    if (cp == '李小辉' || cp.contains('李小辉')) {
      return true;
    }

    // Match with extracted owner name if available
    if (ownerName != null && ownerName.trim().isNotEmpty) {
      final name = ownerName.trim();
      if (cp == name || cp.contains(name) || name.contains(cp)) {
        return true;
      }
    }

    return false;
  }

  /// Fallback for generic tabular bank statements.
  static List<ParsedBillItem> _parseGenericBankStatement(
    String text, {
    Map<String, UserMerchantRule>? customRules,
  }) {
    final items = <ParsedBillItem>[];
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final dateRegex = RegExp(r'^(\d{4}[-/.]\d{2}[-/.]\d{2})');
    final amountRegex = RegExp(r'(-?[\d,]+(\.\d{2})?)');

    int rowIdx = 0;
    for (final line in lines) {
      final dateMatch = dateRegex.firstMatch(line);
      if (dateMatch == null) continue;

      final dateStr = dateMatch.group(1)!.replaceAll('.', '-').replaceAll('/', '-');
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final remaining = line.substring(dateMatch.end).trim();
      final amtMatch = amountRegex.firstMatch(remaining);
      if (amtMatch == null) continue;

      final amtStr = amtMatch.group(1)!.replaceAll(',', '');
      final amtVal = double.tryParse(amtStr);
      if (amtVal == null || amtVal == 0) continue;

      final desc = remaining.replaceAll(amtMatch.group(0)!, '').trim();
      final amountMinor = (amtVal.abs() * 100).round();
      final direction = amtVal < 0 ? FinanceDirection.expense : FinanceDirection.income;

      final isSelf = _isCounterpartySelf(desc, null);
      final finalDirection = isSelf ? FinanceDirection.transfer : direction;
      final category = isSelf ? 'TRANSFER' : (amtVal < 0 ? 'OTHER' : 'OTHER_INCOME');
      final subCategory = isSelf ? '内部转账' : (amtVal < 0 ? '银行支出' : '银行入账');

      items.add(
        ParsedBillItem(
          sourceType: BillSourceType.bank,
          transactionTime: date,
          direction: finalDirection,
          amountMinor: amountMinor,
          counterparty: isSelf ? '本人账户' : (desc.isNotEmpty ? desc : '银行流水'),
          description: desc.isNotEmpty ? desc : '银行交易',
          orderId: 'BANK_${dateStr}_${amountMinor}_${++rowIdx}',
          sourcePaymentMethod: '银行卡',
          status: '交易成功',
          category: category,
          subCategory: subCategory,
          expenseNature: ExpenseNature.need,
          suggestedAccountType: FinanceAccountType.debit,
          selected: true,
        ),
      );
    }

    return items;
  }
}
