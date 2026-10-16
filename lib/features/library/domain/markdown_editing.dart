/// 便签（Notes）使用的轻量 Markdown 行内编辑内核。
///
/// 该文件**不依赖 Flutter**，只处理纯字符串与下标运算，因此可以被
/// `dart run` 直接驱动的脚本或单元测试快速验证，避免编辑逻辑与 UI 纠缠。
///
/// 设计背景：便签把用户输入原样保存为 Markdown 源码（`**加粗**`、`*斜体*`、
/// `~~删除线~~`、`# 标题`），编辑器通过"零宽隐藏分隔符"的方式做无痕渲染。
/// 这套机制必须保证：**任何一次写 / 删 / 改格式都不允许破坏其它样式块、
/// 也不允许残留孤立分隔符**。本文件集中承载这些规则。
library;

/// 行内样式类型。
enum MarkdownInlineStyle { bold, italic, strikethrough }

/// 一个行内 Markdown 样式块在源码中的位置。
class MarkdownSpanRange {
  const MarkdownSpanRange({
    required this.start,
    required this.end,
    required this.delimLen,
  });

  /// 起始分隔符首字符下标。
  final int start;

  /// 结束分隔符末尾之后的下标（不含）。
  final int end;

  /// 单侧分隔符长度：1 = 斜体，2 = 粗体 / 删除线，3 = 粗斜体。
  final int delimLen;

  int get openStart => start;
  int get openEnd => start + delimLen;
  int get closeStart => end - delimLen;
  int get closeEnd => end;

  int get contentStart => start + delimLen;
  int get contentEnd => end - delimLen;

  bool get hasContent => contentEnd > contentStart;
}

/// 行内样式识别正则。**必须与渲染、格式切换共用同一份**，否则会出现
/// "编辑态认为是样式、渲染态却退化成裸星号"的不一致。
final RegExp markdownSpanPattern =
    RegExp(r'(\*\*\*[^*]+?\*\*\*|\*\*[^*]+?\*\*|~~[^~]+?~~|\*[^*]+?\*)');

const int _asterisk = 0x2A;
const int _tilde = 0x7E;

/// 解析出文本中所有行内样式块（互不重叠，按出现顺序）。
List<MarkdownSpanRange> parseMarkdownSpans(String text) {
  final spans = <MarkdownSpanRange>[];
  for (final match in markdownSpanPattern.allMatches(text)) {
    final chunk = match.group(0)!;
    final int delimLen;
    if (chunk.startsWith('***')) {
      delimLen = 3;
    } else if (chunk.startsWith('**') || chunk.startsWith('~~')) {
      delimLen = 2;
    } else {
      delimLen = 1;
    }
    spans.add(
      MarkdownSpanRange(
        start: match.start,
        end: match.end,
        delimLen: delimLen,
      ),
    );
  }
  return spans;
}

/// 查找光标处包裹的样式块。
Match? findEnclosingMarkdownSpan(String text, int cursor) {
  if (text.isEmpty) return null;
  for (final match in markdownSpanPattern.allMatches(text)) {
    if (cursor >= match.start && cursor <= match.end) {
      return match;
    }
  }
  return null;
}

bool _isWhitespaceChar(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

bool _isMarkdownDelimChar(String ch) =>
    ch == '*' || ch == '~' || ch == '#' || ch == '`';

/// 在指定光标位置提取相邻的连续单词 / 词组区间（支持中文、英文、数字）。
({int start, int end})? findWordRangeAt(String text, int cursor) {
  if (text.isEmpty) return null;
  final clampedCursor = cursor.clamp(0, text.length);

  final lineStart =
      clampedCursor > 0 ? text.lastIndexOf('\n', clampedCursor - 1) + 1 : 0;
  final nextNewline = text.indexOf('\n', clampedCursor);
  final lineEnd = nextNewline == -1 ? text.length : nextNewline;
  if (lineStart >= lineEnd) return null;

  final lineText = text.substring(lineStart, lineEnd);
  if (lineText.trim().isEmpty) return null;

  int testPos = clampedCursor;
  if (testPos == lineEnd && testPos > lineStart) {
    testPos--;
  } else if (testPos < lineEnd &&
      _isWhitespaceChar(text[testPos]) &&
      testPos > lineStart &&
      !_isWhitespaceChar(text[testPos - 1])) {
    testPos--;
  }

  if (testPos < lineStart ||
      testPos >= lineEnd ||
      _isWhitespaceChar(text[testPos])) {
    return null;
  }

  int s = testPos;
  while (s > lineStart &&
      !_isWhitespaceChar(text[s - 1]) &&
      !_isMarkdownDelimChar(text[s - 1])) {
    s--;
  }

  int e = testPos + 1;
  while (e < lineEnd &&
      !_isWhitespaceChar(text[e]) &&
      !_isMarkdownDelimChar(text[e])) {
    e++;
  }

  if (s < e) {
    return (start: s, end: e);
  }
  return null;
}

/// 去除文本中的 Markdown 装饰标记符号，提供纯净的显示与复制。
String stripMarkdownDecorators(String text) {
  return text
      .replaceAllMapped(RegExp(r'\*\*\*([^*]+?)\*\*\*'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'\*\*([^*]+?)\*\*'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'~~([^~]+?)~~'), (m) => m[1] ?? '')
      .replaceAllMapped(RegExp(r'\*([^*]+?)\*'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .trimRight();
}

/// 统计"可见字数"：剔除 Markdown 标记、换行与空白后的字符数。
///
/// 用户看到的 `**库迪**` 是「库迪」两个字，字数就应该是 2 而不是 6。
int markdownCharacterCount(String text) {
  return stripMarkdownDecorators(text).replaceAll(RegExp(r'\s+'), '').length;
}

/// 针对目标区间执行无损、可嵌套、精准反转的 Markdown 样式切换。
({String newText, int selectionStart, int selectionEnd}) toggleMarkdownStyle({
  required String text,
  required int targetStart,
  required int targetEnd,
  required MarkdownInlineStyle style,
}) {
  if (text.isEmpty ||
      targetStart > targetEnd ||
      targetStart < 0 ||
      targetEnd > text.length) {
    return (newText: text, selectionStart: targetStart, selectionEnd: targetEnd);
  }

  int fullStart = targetStart;
  int fullEnd = targetEnd;
  Match? matchedSpan;

  for (final match in markdownSpanPattern.allMatches(text)) {
    if (match.start <= targetStart && match.end >= targetEnd) {
      matchedSpan = match;
      break;
    }
  }

  if (matchedSpan != null) {
    fullStart = matchedSpan.start;
    fullEnd = matchedSpan.end;
  }

  final rawChunk = text.substring(fullStart, fullEnd);

  bool isBold = false;
  bool isItalic = false;
  bool isStrike = false;

  String content = rawChunk;

  if (content.startsWith('~~') &&
      content.endsWith('~~') &&
      content.length >= 4) {
    isStrike = true;
    content = content.substring(2, content.length - 2);
  }

  if (content.startsWith('***') &&
      content.endsWith('***') &&
      content.length >= 6) {
    isBold = true;
    isItalic = true;
    content = content.substring(3, content.length - 3);
  } else if (content.startsWith('**') &&
      content.endsWith('**') &&
      content.length >= 4) {
    isBold = true;
    content = content.substring(2, content.length - 2);
  } else if (content.startsWith('*') &&
      content.endsWith('*') &&
      content.length >= 2) {
    isItalic = true;
    content = content.substring(1, content.length - 1);
  }

  if (!isStrike &&
      content.startsWith('~~') &&
      content.endsWith('~~') &&
      content.length >= 4) {
    isStrike = true;
    content = content.substring(2, content.length - 2);
  }

  switch (style) {
    case MarkdownInlineStyle.bold:
      isBold = !isBold;
      break;
    case MarkdownInlineStyle.italic:
      isItalic = !isItalic;
      break;
    case MarkdownInlineStyle.strikethrough:
      isStrike = !isStrike;
      break;
  }

  String formatted = content;
  if (isBold && isItalic) {
    formatted = '***$formatted***';
  } else if (isBold) {
    formatted = '**$formatted**';
  } else if (isItalic) {
    formatted = '*$formatted*';
  }

  if (isStrike) {
    formatted = '~~$formatted~~';
  }

  final newText = text.replaceRange(fullStart, fullEnd, formatted);
  final innerOffset = formatted.indexOf(content);
  final newSelStart = fullStart + (innerOffset != -1 ? innerOffset : 0);
  final newSelEnd = newSelStart + content.length;

  return (
    newText: newText,
    selectionStart: newSelStart,
    selectionEnd: newSelEnd,
  );
}

/// 删除操作的结果。
class MarkdownDeletionResult {
  const MarkdownDeletionResult(this.text, this.cursor);

  final String text;
  final int cursor;
}

/// 把下标 [index] 从旧文本坐标系映射到删除后的新文本坐标系。
///
/// 落在被删除区间内部的坐标统一收敛到删除起点。
int _mapIndex(int index, int deleteStart, int deleteEnd) {
  if (index <= deleteStart) return index;
  if (index >= deleteEnd) return index - (deleteEnd - deleteStart);
  return deleteStart;
}

/// 计算 newText 相对 oldText 的差量区间。
({int start, int end}) _diffRange(String oldText, String newText) {
  int prefix = 0;
  while (prefix < newText.length &&
      prefix < oldText.length &&
      newText[prefix] == oldText[prefix]) {
    prefix++;
  }
  int suffix = 0;
  while (suffix < newText.length - prefix &&
      suffix < oldText.length - prefix &&
      newText[newText.length - 1 - suffix] ==
          oldText[oldText.length - 1 - suffix]) {
    suffix++;
  }
  return (start: prefix, end: oldText.length - suffix);
}

/// 核心：**安全地**处理一次删除，保证不破坏无关样式块、不残留孤立分隔符。
///
/// 规则（按优先级）：
/// 1. 删除动作只吃掉了**某个样式块的分隔符**（例如在 `**库迪**` 末尾按退格，
///    键盘删掉的是闭合 `*`）→ 视为"想删掉一个可见字符"，于是删掉对应侧的最后一个
///    内容字符并保留样式；内容被删空则整块干净移除。**绝不留下 `****`**。
/// 2. 删除动作触及了内容 → 先做字面删除，然后**只修复真正被破坏的样式块**：
///    内容被删空则移除整块；分隔符被删残缺则补回成完整分隔符。其余样式块一律不动。
///
/// 关键点：**绝不使用"全局清洗孤立星号"的正则**——那会把同一篇便签里其它
/// 正常的 `**加粗**` 一起抹掉，并让光标错位跳到下一行。
MarkdownDeletionResult sanitizeMarkdownDeletion({
  required String oldText,
  required String newText,
  required int caret,
}) {
  int clampCaret(int value, String text) => value.clamp(0, text.length);

  if (oldText.length <= newText.length) {
    return MarkdownDeletionResult(newText, clampCaret(caret, newText));
  }

  final range = _diffRange(oldText, newText);
  final deleteStart = range.start;
  final deleteEnd = range.end;
  if (deleteStart >= deleteEnd) {
    return MarkdownDeletionResult(newText, clampCaret(caret, newText));
  }

  final spans = parseMarkdownSpans(oldText);
  if (spans.isEmpty) {
    return MarkdownDeletionResult(newText, clampCaret(caret, newText));
  }

  final deleted = oldText.substring(deleteStart, deleteEnd);
  final onlyDelimiters = deleted.isNotEmpty &&
      deleted.codeUnits.every((c) => c == _asterisk || c == _tilde);

  // —— 规则 1：只删到了分隔符 ——
  if (onlyDelimiters) {
    for (final span in spans) {
      final hitOpen =
          deleteStart >= span.openStart && deleteEnd <= span.openEnd;
      final hitClose =
          deleteStart >= span.closeStart && deleteEnd <= span.closeEnd;
      if (!hitOpen && !hitClose) continue;

      final delimiter = oldText.substring(span.openStart, span.openEnd);
      final content = oldText.substring(span.contentStart, span.contentEnd);
      if (content.isEmpty) {
        final removed = oldText.replaceRange(span.openStart, span.closeEnd, '');
        return MarkdownDeletionResult(removed, span.openStart);
      }

      final kept = hitClose
          ? content.substring(0, content.length - 1)
          : content.substring(1);
      if (kept.isEmpty) {
        final removed = oldText.replaceRange(span.openStart, span.closeEnd, '');
        return MarkdownDeletionResult(removed, span.openStart);
      }

      final rebuilt = oldText.replaceRange(
        span.openStart,
        span.closeEnd,
        '$delimiter$kept$delimiter',
      );
      final cursor =
          hitClose ? span.openEnd + kept.length : span.openEnd;
      return MarkdownDeletionResult(rebuilt, cursor);
    }
    // 落在样式块之外的分隔符（用户手打的裸星号）→ 按字面删除继续走规则 2
  }

  // —— 规则 2：字面删除 + 只修复被破坏的样式块 ——
  var text = newText;
  var cursor = clampCaret(caret, newText);

  for (final span in spans.reversed) {
    // 与删除区间完全没有交集（含"紧邻其后"的边界情形）→ 必须保持原样
    if (span.end <= deleteStart || span.start >= deleteEnd) continue;

    final survived = StringBuffer();
    for (var i = span.contentStart; i < span.contentEnd; i++) {
      if (i >= deleteStart && i < deleteEnd) continue;
      survived.write(oldText[i]);
    }

    final newStart = _mapIndex(span.openStart, deleteStart, deleteEnd);
    final newEnd = _mapIndex(span.closeEnd, deleteStart, deleteEnd);
    if (newStart >= newEnd) continue;
    if (newEnd > text.length) continue;

    final delimiter = oldText.substring(span.openStart, span.openEnd);
    final replacement =
        survived.isEmpty ? '' : '$delimiter$survived$delimiter';
    text = text.replaceRange(newStart, newEnd, replacement);

    if (cursor > newStart) {
      if (survived.isEmpty) {
        cursor = newStart;
      } else {
        final blockEnd = newStart + replacement.length;
        if (cursor > blockEnd) {
          cursor = blockEnd;
        } else if (cursor < newStart + delimiter.length) {
          cursor = newStart + delimiter.length;
        }
      }
    }
  }

  return MarkdownDeletionResult(text, cursor.clamp(0, text.length));
}

/// 在样式块内部插入换行时的自动拆分结果。
class MarkdownInsertionResult {
  const MarkdownInsertionResult(this.text, this.cursor);

  final String text;
  final int cursor;
}

/// 处理"在 `**加粗**` 内部按回车 / 粘贴多行"的情形。
///
/// 如果不处理，源码会变成 `**甲\n乙**`：编辑逻辑仍按样式块对待，渲染却因为
/// 逐行解析而退化成裸露的 `**`。这里把样式块按行重新包好：
/// `**甲**\n**乙**`，既保持视觉连续，也让每一行都是合法样式块。
///
/// 返回 `null` 表示本次插入不涉及样式块内换行，无需处理。
MarkdownInsertionResult? splitMarkdownSpanOnLineBreak({
  required String oldText,
  required String newText,
  required int insertionStart,
  required int insertedLength,
}) {
  if (insertedLength <= 0) return null;
  if (insertionStart < 0 ||
      insertionStart + insertedLength > newText.length) {
    return null;
  }
  final inserted =
      newText.substring(insertionStart, insertionStart + insertedLength);
  if (!inserted.contains('\n')) return null;

  for (final span in parseMarkdownSpans(oldText)) {
    if (insertionStart < span.contentStart || insertionStart > span.contentEnd) {
      continue;
    }

    final delimiter = oldText.substring(span.openStart, span.openEnd);
    final before = oldText.substring(span.contentStart, insertionStart);
    final after = oldText.substring(insertionStart, span.contentEnd);
    final content = '$before$inserted$after';

    final lines = content.split('\n');
    final blocks = [for (final line in lines) line.isEmpty ? '' : '$delimiter$line$delimiter'];
    final replacement = blocks.join('\n');

    final spanEndInNew = span.closeEnd + insertedLength;
    if (spanEndInNew > newText.length) return null;
    final rebuilt =
        newText.replaceRange(span.openStart, spanEndInNew, replacement);

    // 光标落到"插入内容结束处"在该行内的对应位置
    var offsetInContent = before.length + insertedLength;
    var accumulated = 0;
    var cursor = span.openStart + replacement.length;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (offsetInContent <= line.length) {
        final lead = line.isEmpty ? 0 : delimiter.length;
        cursor = span.openStart + accumulated + lead + offsetInContent;
        break;
      }
      offsetInContent -= line.length + 1;
      accumulated += blocks[i].length + 1;
    }

    return MarkdownInsertionResult(
      rebuilt,
      cursor.clamp(0, rebuilt.length),
    );
  }
  return null;
}
