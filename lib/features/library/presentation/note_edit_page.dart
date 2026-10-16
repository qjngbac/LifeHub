import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/domain/markdown_editing.dart';
import 'package:lifehub/features/settings/presentation/app_lock_page.dart';

// 编辑内核（样式解析 / 切换 / 安全删除）统一由纯 Dart 模块承载，
// 这里保持再导出，便于既有引用方与测试直接 import 本文件。
export 'package:lifehub/features/library/domain/markdown_editing.dart';

const List<({String name, String hex, Color color})> noteColors = [
  (name: '默认白', hex: '#FFFFFF', color: Colors.white),
  (name: '温润鹅黄', hex: '#FFF9C4', color: Color(0xFFFFF9C4)),
  (name: '清新薄荷', hex: '#E8F5E9', color: Color(0xFFE8F5E9)),
  (name: '天空淡蓝', hex: '#E1F5FE', color: Color(0xFFE1F5FE)),
  (name: '浅樱柔粉', hex: '#FCE4EC', color: Color(0xFFFCE4EC)),
  (name: '薰衣草紫', hex: '#F3E5F5', color: Color(0xFFF3E5F5)),
  (name: '暖杏柔橙', hex: '#FFF3E0', color: Color(0xFFFFF3E0)),
];

const List<({String name, double size})> noteFontSizes = [
  (name: '紧凑 (小)', size: 15.0),
  (name: '标准 (默认)', size: 17.0),
  (name: '稍大 (舒服)', size: 19.5),
  (name: '大号 (清晰)', size: 22.5),
];

Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  } else if (clean.length == 8) {
    return Color(int.parse(clean, radix: 16));
  }
  return null;
}

/// 便签撤销/重做历史状态管理器
class NoteUndoController extends ChangeNotifier {
  final List<TextEditingValue> _undoStack = [];
  final List<TextEditingValue> _redoStack = [];
  bool _isPerformingUndoRedo = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void recordChange(TextEditingValue value) {
    if (_isPerformingUndoRedo) return;
    if (_undoStack.isNotEmpty && _undoStack.last.text == value.text) {
      _undoStack[_undoStack.length - 1] = value;
      return;
    }
    _undoStack.add(value);
    _redoStack.clear();
    if (_undoStack.length > 60) {
      _undoStack.removeAt(0);
    }
    notifyListeners();
  }

  TextEditingValue? undo(TextEditingValue current) {
    if (!canUndo) return null;
    _isPerformingUndoRedo = true;
    _redoStack.add(current);
    final previous = _undoStack.removeLast();
    _isPerformingUndoRedo = false;
    notifyListeners();
    return previous;
  }

  TextEditingValue? redo(TextEditingValue current) {
    if (!canRedo) return null;
    _isPerformingUndoRedo = true;
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    _isPerformingUndoRedo = false;
    notifyListeners();
    return next;
  }
}

/// 支持无符号无缝富文本渲染、丝滑多行长按拖选与安全退格删除的便签控制器
class NoteTextEditingController extends TextEditingController {
  // 注意：具名参数不能用 `this._fontSize`（私有具名参数属于实验特性，
  // 会让 flutter analyze 报 experiment/undefined_named_parameter），
  // 这里用普通具名参数在初始化列表里赋值。
  NoteTextEditingController({super.text, double fontSize = 17.0})
      // ignore: prefer_initializing_formals
      : _fontSize = fontSize;

  double _fontSize;
  double get fontSize => _fontSize;
  set fontSize(double value) {
    if (_fontSize != value) {
      _fontSize = value;
      notifyListeners();
    }
  }

  @override
  set value(TextEditingValue newValue) {
    final oldValue = value;

    // 仅选区 / 光标变化：100% 交给 Flutter 原生处理，绝不干涉长按拖选
    if (oldValue.text == newValue.text) {
      super.value = newValue;
      return;
    }

    final oldText = oldValue.text;
    final newText = newValue.text;

    // ① 删除：走"结构感知"的安全删除
    //    既不会把同一篇便签里其它 **加粗** 一起抹掉，也不会残留 **** 或让光标跳行
    if (oldText.length > newText.length) {
      final result = sanitizeMarkdownDeletion(
        oldText: oldText,
        newText: newText,
        caret: newValue.selection.baseOffset,
      );
      super.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.cursor),
      );
      return;
    }

    // ② 新增：在样式块内部按回车 / 粘贴多行时，自动把样式块按行拆分，
    //    否则会留下 `**甲\n乙**` 这种"编辑态当成样式、渲染态显示裸星号"的残缺块
    final insertedLength = newText.length - oldText.length;
    if (insertedLength > 0) {
      int commonPrefix = 0;
      while (commonPrefix < oldText.length &&
          commonPrefix < newText.length &&
          oldText[commonPrefix] == newText[commonPrefix]) {
        commonPrefix++;
      }
      final isPureInsertion = oldText ==
          newText.substring(0, commonPrefix) +
              newText.substring(commonPrefix + insertedLength);
      if (isPureInsertion) {
        final split = splitMarkdownSpanOnLineBreak(
          oldText: oldText,
          newText: newText,
          insertionStart: commonPrefix,
          insertedLength: insertedLength,
        );
        if (split != null) {
          super.value = TextEditingValue(
            text: split.text,
            selection: TextSelection.collapsed(offset: split.cursor),
          );
          return;
        }
      }
    }

    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = (style ?? const TextStyle()).copyWith(
      fontSize: _fontSize,
      height: 1.6,
    );

    final rawText = value.text;
    if (rawText.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final spans = <TextSpan>[];
    final lines = rawText.split('\n');

    // 隐藏标记样式的辅助微字号透明样式，长度完全保持一致以确保光标与选区精准对应
    // 关键：letterSpacing 为 0，杜绝负字距造成的排版引擎坐标反向偏移与拖选卡顿
    final hiddenTokenStyle = baseStyle.copyWith(
      fontSize: 0.001,
      color: Colors.transparent,
      letterSpacing: 0,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineEnding = i < lines.length - 1 ? '\n' : '';

      if (line.startsWith('# ')) {
        // 一级标题：加大 + 加粗，无痕隐藏 '# '
        spans.add(TextSpan(text: '# ', style: hiddenTokenStyle));
        _parseInline(
          line.substring(2) + lineEnding,
          baseStyle.copyWith(
            fontSize: _fontSize * 1.35,
            fontWeight: FontWeight.bold,
          ),
          hiddenTokenStyle,
          spans,
        );
      } else if (line.startsWith('## ')) {
        // 二级标题：稍大 + 加粗，无痕隐藏 '## '
        spans.add(TextSpan(text: '## ', style: hiddenTokenStyle));
        _parseInline(
          line.substring(3) + lineEnding,
          baseStyle.copyWith(
            fontSize: _fontSize * 1.18,
            fontWeight: FontWeight.bold,
          ),
          hiddenTokenStyle,
          spans,
        );
      } else {
        _parseInline(line + lineEnding, baseStyle, hiddenTokenStyle, spans);
      }
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  void _parseInline(
    String text,
    TextStyle baseStyle,
    TextStyle hiddenStyle,
    List<TextSpan> spans,
  ) {
    final regex = RegExp(
        r'(\*\*\*[^*]+?\*\*\*|\*\*[^*]+?\*\*|~~[^~]+?~~|\*[^*]+?\*)');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      final chunk = match.group(0)!;
      if (chunk.startsWith('***') &&
          chunk.endsWith('***') &&
          chunk.length >= 6) {
        // 粗斜体：无痕隐藏两边的 '***'
        final inner = chunk.substring(3, chunk.length - 3);
        spans.add(TextSpan(text: '***', style: hiddenStyle));
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ));
        spans.add(TextSpan(text: '***', style: hiddenStyle));
      } else if (chunk.startsWith('**') &&
          chunk.endsWith('**') &&
          chunk.length >= 4) {
        // 粗体：无痕隐藏两边的 '**'
        final inner = chunk.substring(2, chunk.length - 2);
        spans.add(TextSpan(text: '**', style: hiddenStyle));
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
        spans.add(TextSpan(text: '**', style: hiddenStyle));
      } else if (chunk.startsWith('~~') &&
          chunk.endsWith('~~') &&
          chunk.length >= 4) {
        // 删除线：无痕隐藏两边的 '~~'
        final inner = chunk.substring(2, chunk.length - 2);
        spans.add(TextSpan(text: '~~', style: hiddenStyle));
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
        spans.add(TextSpan(text: '~~', style: hiddenStyle));
      } else if (chunk.startsWith('*') &&
          chunk.endsWith('*') &&
          chunk.length >= 2) {
        // 斜体：无痕隐藏两边的 '*'
        final inner = chunk.substring(1, chunk.length - 1);
        spans.add(TextSpan(text: '*', style: hiddenStyle));
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
        spans.add(TextSpan(text: '*', style: hiddenStyle));
      } else {
        spans.add(TextSpan(text: chunk, style: baseStyle));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }
  }
}

class NoteEditPage extends ConsumerStatefulWidget {
  const NoteEditPage({
    super.key,
    this.noteId,
    this.initialNote,
  });

  final String? noteId;
  final SavedItemEntry? initialNote;

  @override
  ConsumerState<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends ConsumerState<NoteEditPage> {
  late final TextEditingController _titleController;
  late final NoteTextEditingController _contentController;
  late final NoteUndoController _undoController;
  final _articleScrollController = ScrollController();
  final _contentFocusNode = FocusNode();

  String? _noteId;
  bool _isPinned = false;
  String? _colorHex;
  double _fontSize = 17.0;
  bool _sensitive = false;
  List<String> _tags = [];
  DateTime _updatedAt = DateTime.now();

  // 初始状态快照，用于严格检测用户是否产生实质修改，杜绝只读查看时误更新时间
  String _initialTitle = '';
  String _initialContent = '';
  bool _initialPinned = false;
  String? _initialColorHex;
  double _initialFontSize = 17.0;
  bool _initialSensitive = false;
  List<String> _initialTags = [];

  bool _isSaving = false;
  bool _hasModified = false;

  // 上一次渲染所用的样式激活态与正文快照，用于抑制拖选过程中的无谓重建
  bool _boldActive = false;
  bool _italicActive = false;
  bool _strikeActive = false;
  String _lastRecordedContent = '';

  @override
  void initState() {
    super.initState();
    _undoController = NoteUndoController();
    _undoController.addListener(() {
      if (mounted) setState(() {});
    });

    _noteId = widget.noteId ?? widget.initialNote?.id;

    final initial = widget.initialNote;
    if (initial != null) {
      final meta = NoteMetadata.fromSourceUri(initial.sourceUri);
      _isPinned = meta.isPinned;
      _colorHex = meta.colorHex;
      _fontSize = meta.fontSize ?? 17.0;
      _sensitive = initial.sensitive;
      _updatedAt = DateTime.fromMillisecondsSinceEpoch(initial.updatedAt);

      final content = initial.content ?? '';
      final title = initial.title;

      // 如果标题与正文首行相同，说明是自动标题，将标题框留空，方便用户直接写正文
      final firstLine = content.split('\n').firstWhere(
            (l) => l.trim().isNotEmpty,
            orElse: () => '',
          ).trim();
      final cleanFirstLine = firstLine
          .replaceFirst(RegExp(r'^(#+\s*|[-*•]\s*|\[[\sxX]\]\s*)'), '')
          .trim();

      if (title.isNotEmpty && title != cleanFirstLine && title != '无标题便签') {
        _titleController = TextEditingController(text: title);
      } else {
        _titleController = TextEditingController();
      }

      _contentController = NoteTextEditingController(
        text: content,
        fontSize: _fontSize,
      );
    } else {
      _titleController = TextEditingController();
      _contentController = NoteTextEditingController(fontSize: _fontSize);
    }

    _initialTitle = _titleController.text;
    _initialContent = _contentController.text;
    _initialPinned = _isPinned;
    _initialColorHex = _colorHex;
    _initialFontSize = _fontSize;
    _initialSensitive = _sensitive;
    _initialTags = [];

    _titleController.addListener(_onTitleChanged);
    _contentController.addListener(_onContentChanged);
    _lastRecordedContent = _contentController.text;

    if (_contentController.text.isNotEmpty) {
      _undoController.recordChange(_contentController.value);
    }

    if (_noteId != null) {
      _loadTags();
    }

    // 首帧后校准一次工具栏样式激活态（初始选区在样式块内时也能正确高亮）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncStateIfNeeded(force: true);
    });
  }

  /// 严密检测便签是否发生任何实质性改动
  bool get _hasRealModifications {
    if (_noteId == null) {
      return _titleController.text.trim().isNotEmpty ||
          _contentController.text.trim().isNotEmpty;
    }
    final titleChanged = _titleController.text.trim() != _initialTitle.trim();
    final contentChanged = _contentController.text != _initialContent;
    final pinnedChanged = _isPinned != _initialPinned;
    final colorChanged = _colorHex != _initialColorHex;
    final fontChanged = _fontSize != _initialFontSize;
    final sensitiveChanged = _sensitive != _initialSensitive;
    final tagsChanged = !listEquals(_tags, _initialTags);

    return titleChanged ||
        contentChanged ||
        pinnedChanged ||
        colorChanged ||
        fontChanged ||
        sensitiveChanged ||
        tagsChanged;
  }

  void _onTitleChanged() {
    _syncStateIfNeeded();
  }

  void _onContentChanged() {
    final text = _contentController.text;
    if (text != _lastRecordedContent) {
      // 正文真的变了：写入撤销栈，并强制刷新（字数、脏标记都要跟着更新）
      _lastRecordedContent = text;
      _undoController.recordChange(_contentController.value);
      _syncStateIfNeeded(force: true);
      return;
    }
    // 仅光标 / 选区变化：只有加粗、斜体、删除线高亮态变化时才重建，
    // 这样长按拖选时不会每帧重刷整页。
    _syncStateIfNeeded();
  }

  /// 只在影响界面显示的状态真正变化时才 setState。
  ///
  /// 长按拖选时选区每帧都在变，但加粗/斜体/删除线的激活态多数帧并不变，
  /// 无差别 setState 会让整页（含两个输入框与整条工具栏）每帧重建，
  /// 这正是"拖选很卡、拖不动几行"的元凶之一。
  void _syncStateIfNeeded({bool force = false}) {
    final modified = _hasRealModifications;
    final bold = _isBoldActive;
    final italic = _isItalicActive;
    final strike = _isStrikeActive;
    if (!force &&
        _hasModified == modified &&
        _boldActive == bold &&
        _italicActive == italic &&
        _strikeActive == strike) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _hasModified = modified;
      _boldActive = bold;
      _italicActive = italic;
      _strikeActive = strike;
    });
  }

  bool get _isBoldActive {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (!sel.isValid || text.isEmpty) return false;
    final checkPos = sel.isCollapsed ? sel.start : (sel.start + sel.end) ~/ 2;
    final m = findEnclosingMarkdownSpan(text, checkPos);
    if (m == null) return false;
    final s = m.group(0)!;
    return s.startsWith('***') || (s.startsWith('**') && !s.startsWith('***'));
  }

  bool get _isItalicActive {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (!sel.isValid || text.isEmpty) return false;
    final checkPos = sel.isCollapsed ? sel.start : (sel.start + sel.end) ~/ 2;
    final m = findEnclosingMarkdownSpan(text, checkPos);
    if (m == null) return false;
    final s = m.group(0)!;
    return s.startsWith('***') || (s.startsWith('*') && !s.startsWith('**'));
  }

  bool get _isStrikeActive {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (!sel.isValid || text.isEmpty) return false;
    final checkPos = sel.isCollapsed ? sel.start : (sel.start + sel.end) ~/ 2;
    final m = findEnclosingMarkdownSpan(text, checkPos);
    if (m == null) return false;
    final s = m.group(0)!;
    return s.contains('~~');
  }

  void _handleUndo() {
    final prev = _undoController.undo(_contentController.value);
    if (prev != null) {
      _contentController.value = prev;
      _syncStateIfNeeded(force: true);
    }
  }

  void _handleRedo() {
    final next = _undoController.redo(_contentController.value);
    if (next != null) {
      _contentController.value = next;
      _syncStateIfNeeded(force: true);
    }
  }

  void _showCapsuleToast({
    required IconData icon,
    required String message,
    double width = 200,
  }) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primaryContainer;
    final fg = isDark
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onPrimaryContainer;
    final border = theme.colorScheme.primary.withValues(alpha: 0.25);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        width: width,
        shape: StadiumBorder(
          side: BorderSide(color: border, width: 1),
        ),
        backgroundColor: bg,
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Future<void> _loadTags() async {
    if (_noteId == null) return;
    final repo = SavedItemRepository(ref.read(databaseProvider));
    final tagEntries = await repo.tagsFor(_noteId!);
    if (mounted) {
      setState(() {
        _tags = tagEntries.map((t) => t.name).toList();
        _initialTags = List<String>.from(_tags);
      });
    }
  }

  @override
  void dispose() {
    if (_sensitive) {
      ref.read(appLockProvider.notifier).lock();
    }
    _articleScrollController.dispose();
    _contentFocusNode.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  /// 可见字数：剔除 Markdown 标记、换行与空白后的字符数
  int get _wordCount => markdownCharacterCount(_contentController.text);

  String get _fontSizeLabel {
    if (_fontSize <= 15.5) return '小';
    if (_fontSize <= 18.0) return '标准';
    if (_fontSize <= 20.5) return '稍大';
    return '大号';
  }

  Color _pageBackground(BuildContext context) {
    final customColor = parseHexColor(_colorHex);
    if (customColor != null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return isDark ? Color.lerp(customColor, Colors.black, 0.75)! : customColor;
    }
    return Theme.of(context).scaffoldBackgroundColor;
  }

  Future<void> _saveNote() async {
    if (_isSaving) return;

    // 核心逻辑修复：如果没有任何实质修改，绝不触发更新，杜绝点进退出误刷新更新时间
    if (_noteId != null && !_hasRealModifications) {
      return;
    }

    final userTitle = _titleController.text.trim();
    // 正文原样保存：首尾空行属于排版（代码块、行尾双空格换行），
    // 只用 trim 判断“是否真的写了内容”，绝不动原文。
    final content = _contentController.text;
    final hasContent = content.trim().isNotEmpty;

    // 如果标题和正文全为空，不保存空便签
    if (_noteId == null && userTitle.isEmpty && !hasContent) {
      return;
    }

    _isSaving = true;
    final repo = SavedItemRepository(ref.read(databaseProvider));
    // 提前捕获通知器：PopScope 触发的保存可能在 await 期间失去 widget，
    // 之后再 read(ref) 会抛异常；通知器本身不依赖 widget 生命周期。
    final refresh = ref.read(refreshProvider.notifier);
    final meta = NoteMetadata(
      isPinned: _isPinned,
      colorHex: _colorHex,
      fontSize: _fontSize,
    );

    // 智能提取标题：如果用户没写标题，直接选用正文第一行作为标题
    String finalTitle = userTitle;
    if (finalTitle.isEmpty && content.isNotEmpty) {
      final firstLine = content.split('\n').firstWhere(
            (l) => l.trim().isNotEmpty,
            orElse: () => '',
          ).trim();
      final cleanFirstLine = firstLine
          .replaceFirst(RegExp(r'^(#+\s*|[-*•]\s*|\[[\sxX]\]\s*)'), '')
          .trim();
      finalTitle = cleanFirstLine.isNotEmpty
          ? (cleanFirstLine.length > 50
              ? '${cleanFirstLine.substring(0, 50)}...'
              : cleanFirstLine)
          : '无标题便签';
    } else if (finalTitle.isEmpty) {
      finalTitle = '无标题便签';
    }

    try {
      if (_noteId == null) {
        final created = await repo.create(
          SavedItemDraft(
            title: finalTitle,
            itemType: SavedItemType.note,
            content: hasContent ? content : null,
            sourceUri: meta.toSourceUri(),
            sensitive: _sensitive,
          ),
        );
        _noteId = created.id;
        if (_tags.isNotEmpty) {
          await repo.replaceTags(created.id, _tags);
        }
      } else {
        await repo.update(
          _noteId!,
          SavedItemDraft(
            title: finalTitle,
            itemType: SavedItemType.note,
            content: hasContent ? content : null,
            sourceUri: meta.toSourceUri(),
            sensitive: _sensitive,
          ),
        );
        await repo.replaceTags(_noteId!, _tags);
      }
      refresh.state++;

      _initialTitle = _titleController.text;
      _initialContent = _contentController.text;
      _initialPinned = _isPinned;
      _initialColorHex = _colorHex;
      _initialFontSize = _fontSize;
      _initialSensitive = _sensitive;
      _initialTags = List<String>.from(_tags);
      _updatedAt = DateTime.now();
      _hasModified = false;
      _lastRecordedContent = _contentController.text;
      if (mounted) _syncStateIfNeeded(force: true);
    } finally {
      _isSaving = false;
    }
  }

  void _toggleInlineStyle(MarkdownInlineStyle style) {
    final text = _contentController.text;
    final selection = _contentController.selection;

    if (!selection.isValid) {
      _showCapsuleToast(
        icon: Icons.text_fields_rounded,
        message: '请先选择需要设置格式的文字',
        width: 230,
      );
      return;
    }

    int targetStart;
    int targetEnd;

    if (!selection.isCollapsed) {
      targetStart = selection.start;
      targetEnd = selection.end;
      // 框选时不小心包含尾部换行符时，裁除尾部换行符
      while (targetEnd > targetStart &&
          (text[targetEnd - 1] == '\n' || text[targetEnd - 1] == '\r')) {
        targetEnd--;
      }
      if (targetStart >= targetEnd) {
        _showCapsuleToast(
          icon: Icons.text_fields_rounded,
          message: '请先选择需要设置格式的文字',
          width: 230,
        );
        return;
      }
    } else {
      // 未选中文本：检查光标处是否有格式块或文字单词
      final cursor = selection.start;
      final spanMatch = findEnclosingMarkdownSpan(text, cursor);

      if (spanMatch != null) {
        targetStart = spanMatch.start;
        targetEnd = spanMatch.end;
      } else {
        final wordRange = findWordRangeAt(text, cursor);
        if (wordRange != null) {
          targetStart = wordRange.start;
          targetEnd = wordRange.end;
        } else {
          // 光标在纯空白处或空行，绝不产生裸露 **** 或 ** 垃圾符号
          _showCapsuleToast(
            icon: Icons.text_fields_rounded,
            message: '请先选择需要设置格式的文字',
            width: 230,
          );
          return;
        }
      }
    }

    _undoController.recordChange(_contentController.value);

    final result = toggleMarkdownStyle(
      text: text,
      targetStart: targetStart,
      targetEnd: targetEnd,
      style: style,
    );

    _contentController.value = TextEditingValue(
      text: result.newText,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
    _syncStateIfNeeded(force: true);
  }

  void _insertLinePrefix(String prefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final offset = selection.isValid ? selection.start : text.length;

    _undoController.recordChange(_contentController.value);

    final lastNewline = text.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
    final lineStart = (lastNewline == -1 || text.isEmpty) ? 0 : lastNewline + 1;
    final lineEnd = text.indexOf('\n', lineStart);
    final currentLine =
        text.substring(lineStart, lineEnd == -1 ? text.length : lineEnd);

    String newText;
    int newOffset = offset;

    if (currentLine.startsWith(prefix)) {
      newText = text.replaceRange(lineStart, lineStart + prefix.length, '');
      newOffset = (offset - prefix.length).clamp(lineStart, newText.length);
    } else {
      final prefixList = ['# ', '## ', '- [ ] ', '- [x] ', '• '];
      String? matchedExisting;
      for (final p in prefixList) {
        if (currentLine.startsWith(p)) {
          matchedExisting = p;
          break;
        }
      }

      if (matchedExisting != null) {
        newText = text.replaceRange(
            lineStart, lineStart + matchedExisting.length, prefix);
        newOffset = offset - matchedExisting.length + prefix.length;
      } else {
        newText = text.replaceRange(lineStart, lineStart, prefix);
        newOffset = offset + prefix.length;
      }
    }

    _contentController.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: newOffset.clamp(0, newText.length)),
    );
    _syncStateIfNeeded(force: true);
  }

  void _showFontSizeDialog() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正文字体大小',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              for (final item in noteFontSizes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.format_size,
                    size: item.size + 2,
                    color: (_fontSize == item.size)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).hintColor,
                  ),
                  title: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: item.size,
                      fontWeight: (_fontSize == item.size)
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: (_fontSize == item.size)
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _fontSize = item.size;
                      _contentController.fontSize = item.size;
                      _hasModified = true;
                    });
                    Navigator.pop(ctx);
                    _saveNote();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }


  Future<void> _scrollToTags() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_articleScrollController.hasClients) return;
    await _articleScrollController.animateTo(
      _articleScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _addTagDialog() async {
    await _scrollToTags();
    if (!mounted) return;
    final controller = TextEditingController();
    final route = DialogRoute<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加便签标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名（如：工作、灵感、待办）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim().replaceAll('#', '');
              if (text.isNotEmpty && !_tags.contains(text)) {
                setState(() {
                  _tags.add(text);
                  _hasModified = true;
                });
                _saveNote();
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    controller.dispose();
    if (mounted) await _scrollToTags();
  }

  void _copyAll() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final full = [
      if (title.isNotEmpty) title,
      if (content.isNotEmpty) stripMarkdownDecorators(content),
    ].join('\n\n');

    if (full.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: full));
      _showCapsuleToast(
        icon: Icons.copy_rounded,
        message: '已复制便签全文',
        width: 170,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = _pageBackground(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _saveNote();
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: '返回并保存',
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _saveNote();
              if (context.mounted) Navigator.pop(context);
            },
          ),
          actions: [
            // 撤销
            IconButton(
              tooltip: '撤销',
              icon: Icon(
                Icons.undo_rounded,
                color: _undoController.canUndo
                    ? theme.colorScheme.onSurface
                    : theme.disabledColor.withValues(alpha: 0.35),
              ),
              onPressed: _undoController.canUndo ? _handleUndo : null,
            ),
            // 重做
            IconButton(
              tooltip: '重做',
              icon: Icon(
                Icons.redo_rounded,
                color: _undoController.canRedo
                    ? theme.colorScheme.onSurface
                    : theme.disabledColor.withValues(alpha: 0.35),
              ),
              onPressed: _undoController.canRedo ? _handleRedo : null,
            ),
            IconButton(
              tooltip: _isPinned ? '取消置顶' : '置顶便签',
              icon: Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _isPinned ? theme.colorScheme.primary : null,
              ),
              onPressed: () {
                setState(() {
                  _isPinned = !_isPinned;
                  _hasModified = true;
                });
                _saveNote();
                _showCapsuleToast(
                  icon: _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  message: _isPinned ? '已置顶该便签' : '已取消置顶',
                  width: 170,
                );
              },
            ),
            PopupMenuButton<String>(
              tooltip: '选择便签纸色',
              icon: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorHex != null ? (parseHexColor(_colorHex) ?? Colors.white) : Colors.white,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.palette_outlined,
                  size: 13,
                  color: Colors.black87,
                ),
              ),
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '便签纸色',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in noteColors)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _colorHex =
                                      item.hex == '#FFFFFF' ? null : item.hex;
                                  _hasModified = true;
                                });
                                Navigator.pop(ctx);
                                _saveNote();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (_colorHex == item.hex ||
                                            (_colorHex == null &&
                                                item.hex == '#FFFFFF'))
                                        ? theme.colorScheme.primary
                                        : Colors.black12,
                                    width: (_colorHex == item.hex ||
                                            (_colorHex == null &&
                                                item.hex == '#FFFFFF'))
                                        ? 2.5
                                        : 1,
                                  ),
                                ),
                                child: (_colorHex == item.hex ||
                                        (_colorHex == null &&
                                            item.hex == '#FFFFFF'))
                                    ? Icon(
                                        Icons.check,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () async {
                FocusScope.of(context).unfocus();
                await _saveNote();
                _showCapsuleToast(
                  icon: Icons.check_circle_outline_rounded,
                  message: '已保存',
                  width: 130,
                );
              },
              child: const Text(
                '完成',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '更多操作',
              onSelected: (value) async {
                if (value == 'fontSize') {
                  _showFontSizeDialog();
                } else if (value == 'copy') {
                  _copyAll();
                } else if (value == 'sensitive') {
                  // 开启私密前必须先有二级密码，否则"私密"只是个摆设
                  if (!_sensitive && !ref.read(appLockProvider).configured) {
                    if (!context.mounted) return;
                    final agreed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('先设置二级密码'),
                        content: const Text(
                            '标记为私密的内容需要用二级密码保护，现在去设置吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('暂不'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('去设置'),
                          ),
                        ],
                      ),
                    );
                    if (agreed != true) return;
                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AppLockPage()),
                    );
                    if (!context.mounted) return;
                    if (!ref.read(appLockProvider).configured) {
                      _showCapsuleToast(
                        icon: Icons.lock_open_rounded,
                        message: '未设置二级密码，内容未受保护',
                        width: 230,
                      );
                      return;
                    }
                  }
                  setState(() {
                    _sensitive = !_sensitive;
                    _hasModified = true;
                  });
                  await _saveNote();
                  _showCapsuleToast(
                    icon: _sensitive ? Icons.lock_rounded : Icons.lock_open_rounded,
                    message: _sensitive ? '已开启私密保护' : '已关闭私密保护',
                    width: 180,
                  );
                } else if (value == 'archive') {
                  if (_noteId != null) {
                    final repo = SavedItemRepository(ref.read(databaseProvider));
                    final refresh = ref.read(refreshProvider.notifier);
                    await repo.archive(_noteId!);
                    refresh.state++;
                  }
                  if (context.mounted) Navigator.pop(context);
                } else if (value == 'delete') {
                  if (_noteId != null) {
                    final repo = SavedItemRepository(ref.read(databaseProvider));
                    final refresh = ref.read(refreshProvider.notifier);
                    await repo.delete(_noteId!);
                    refresh.state++;
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'fontSize',
                  child: Row(
                    children: [
                      Icon(Icons.format_size, size: 20),
                      SizedBox(width: 8),
                      Text('字号设置'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('复制全文'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sensitive',
                  child: Row(
                    children: [
                      Icon(
                        _sensitive ? Icons.lock : Icons.lock_open,
                        size: 20,
                        color: _sensitive ? theme.colorScheme.primary : null,
                      ),
                      const SizedBox(width: 8),
                      Text(_sensitive ? '取消私密' : '设为私密'),
                    ],
                  ),
                ),
                if (_noteId != null) ...[
                  const PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('归档'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // 标题和元信息保持固定；正文与末尾标签一起滚动。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题输入框：强制 filled: false，紧凑选区
                  TextField(
                    controller: _titleController,
                    selectionWidthStyle: ui.BoxWidthStyle.tight,
                    selectionHeightStyle: ui.BoxHeightStyle.tight,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: '标题（选填）',
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 元数据信息行
                  Row(
                    children: [
                      Text(
                        DateFormat('yyyy年M月d日 HH:mm').format(_updatedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                          fontSize: 11.5,
                        ),
                      ),
                      Text(
                        ' · $_wordCount 字',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                          fontSize: 11.5,
                        ),
                      ),
                      if (_sensitive) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.lock, size: 13, color: theme.colorScheme.primary),
                        Text(
                          ' 私密',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // 正文输入框：无痕富文本高亮、智能选区吸附、纯净复制。
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => ScrollNotificationObserver(
                  child: SingleChildScrollView(
                    controller: _articleScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _contentFocusNode.requestFocus,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _contentController,
                              focusNode: _contentFocusNode,
                              minLines: null,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              selectionWidthStyle: ui.BoxWidthStyle.tight,
                              selectionHeightStyle: ui.BoxHeightStyle.tight,
                              contextMenuBuilder: (context, editableTextState) {
                                final List<ContextMenuButtonItem> buttonItems =
                                    editableTextState.contextMenuButtonItems;
                                final copyIndex = buttonItems.indexWhere(
                                  (item) =>
                                      item.type == ContextMenuButtonType.copy,
                                );
                                if (copyIndex != -1) {
                                  final original = buttonItems[copyIndex];
                                  buttonItems[copyIndex] =
                                      ContextMenuButtonItem(
                                        type: ContextMenuButtonType.copy,
                                        label: original.label,
                                        onPressed: () {
                                          final val = editableTextState
                                              .textEditingValue;
                                          final selected = val.selection
                                              .textInside(val.text);
                                          final clean = stripMarkdownDecorators(
                                            selected,
                                          );
                                          Clipboard.setData(
                                            ClipboardData(text: clean),
                                          );
                                          editableTextState.hideToolbar();
                                          _showCapsuleToast(
                                            icon: Icons.copy_rounded,
                                            message: '已复制',
                                            width: 130,
                                          );
                                        },
                                      );
                                }
                                return AdaptiveTextSelectionToolbar.buttonItems(
                                  anchors: editableTextState.contextMenuAnchors,
                                  buttonItems: buttonItems,
                                );
                              },
                              style: TextStyle(
                                fontSize: _fontSize,
                                height: 1.6,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                              decoration: InputDecoration(
                                hintText: '开始写点什么吧...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.outlineVariant,
                                  fontSize: _fontSize,
                                ),
                                filled: false,
                                fillColor: Colors.transparent,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            // 标签胶囊列表
                            if (_tags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 12,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    for (final tag in _tags)
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        label: Text(
                                          '# $tag',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 14,
                                        ),
                                        onDeleted: () {
                                          setState(() {
                                            _tags.remove(tag);
                                            _hasModified = true;
                                          });
                                          _saveNote();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 贴合软键盘/停驻底部的格式工具栏
            _buildFormatToolbar(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatToolbar(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final barBg = isDark
        ? Colors.grey.shade900.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.96);

    return SafeArea(
      top: false,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: barBg,
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.12),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 撤销 (Undo)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '撤销',
                icon: Icon(
                  Icons.undo_rounded,
                  size: 20,
                  color: _undoController.canUndo
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor.withValues(alpha: 0.35),
                ),
                onPressed: _undoController.canUndo ? _handleUndo : null,
              ),
              // 2. 重做 (Redo)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '重做',
                icon: Icon(
                  Icons.redo_rounded,
                  size: 20,
                  color: _undoController.canRedo
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor.withValues(alpha: 0.35),
                ),
                onPressed: _undoController.canRedo ? _handleRedo : null,
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 16,
                width: 1,
                color: theme.dividerColor.withValues(alpha: 0.25),
              ),
              // 3. 字号设置按钮
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showFontSizeDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_size, size: 18),
                      const SizedBox(width: 2),
                      Text(
                        _fontSizeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 4. 加粗 B
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '加粗',
                icon: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _boldActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.format_bold,
                    size: 21,
                    color: _boldActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onPressed: () => _toggleInlineStyle(MarkdownInlineStyle.bold),
              ),
              // 5. 斜体 I
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '斜体',
                icon: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _italicActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.format_italic,
                    size: 21,
                    color: _italicActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onPressed: () => _toggleInlineStyle(MarkdownInlineStyle.italic),
              ),
              // 6. 删除线 S
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '删除线',
                icon: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _strikeActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.format_strikethrough,
                    size: 21,
                    color: _strikeActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onPressed: () => _toggleInlineStyle(MarkdownInlineStyle.strikethrough),
              ),
              // 7. 大字标题 H
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '大字标题',
                icon: const Icon(Icons.title, size: 21),
                onPressed: () => _insertLinePrefix('# '),
              ),
              // 8. 待办清单 ☑
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '待办清单',
                icon: const Icon(Icons.check_box_outlined, size: 20),
                onPressed: () => _insertLinePrefix('- [ ] '),
              ),
              // 9. 项目符号 •
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '项目符号',
                icon: const Icon(Icons.format_list_bulleted, size: 20),
                onPressed: () => _insertLinePrefix('• '),
              ),
              // 10. 标签 🏷
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '添加标签',
                icon: const Icon(Icons.label_outline, size: 20),
                onPressed: _addTagDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
