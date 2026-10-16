import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

/// 查看私密内容前的统一门禁。
///
/// 未设置二级密码 → 直接放行（此时私密标记还没有密码可保护）；
/// 已解锁（窗口内）→ 放行；否则要求输入二级密码，最多重试 3 次。
/// 返回 true 表示现在可以查看。
Future<bool> ensureAppUnlocked(
  BuildContext context,
  WidgetRef ref, {
  String title = '查看私密内容',
}) async {
  final lock = ref.read(appLockProvider);
  if (!lock.configured) return true;
  if (lock.isUnlocked) return true;
  return showPinPrompt(context, ref, title: title);
}

/// 弹出二级密码输入框；验证通过返回 true，并刷新解锁窗口。
Future<bool> showPinPrompt(
  BuildContext context,
  WidgetRef ref, {
  String title = '输入二级密码',
}) async {
  var hint = '';
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!context.mounted) return false;
    final pin = await _requestText(
      context,
      title: title,
      label: '二级密码',
      helper: '用于查看私密便签等内容',
      errorText: hint.isEmpty ? null : hint,
    );
    if (pin == null) return false;
    final ok = await ref.read(appLockProvider.notifier).verify(pin);
    if (ok) return true;
    hint = '二级密码不正确，请重试';
  }
  return false;
}

/// 设置 / 修改二级密码（在设置页调用）。
/// 返回是否设置成功。
Future<bool> changeAppPin(BuildContext context, WidgetRef ref) async {
  final service = ref.read(appLockServiceProvider);
  final hadPin = service.isConfigured;

  String? currentPin;
  if (hadPin) {
    if (!context.mounted) return false;
    currentPin = await _requestText(
      context,
      title: '输入当前二级密码',
      label: '当前二级密码',
      helper: '修改前需要先验证身份',
    );
    if (currentPin == null) return false;
    final ok = await service.verify(currentPin);
    if (!ok) {
      if (context.mounted) {
        _toast(context, '当前二级密码不正确');
      }
      return false;
    }
  }

  if (!context.mounted) return false;
  final first = await _requestText(
    context,
    title: hadPin ? '设置新的二级密码' : '设置二级密码',
    label: '新二级密码（4-16 位）',
    helper: '忘记密码只能清除这层锁，私密内容不会丢失',
  );
  if (first == null) return false;
  if (first.length < AppLockService.minLength ||
      first.length > AppLockService.maxLength) {
    if (context.mounted) {
      _toast(context, '二级密码需要 4-16 位字符');
    }
    return false;
  }
  if (!context.mounted) return false;
  final second = await _requestText(
    context,
    title: '再输入一次确认',
    label: '再次输入新二级密码',
  );
  if (second == null) return false;
  if (second != first) {
    if (context.mounted) {
      _toast(context, '两次输入不一致');
    }
    return false;
  }

  if (!context.mounted) return false;
  await ref.read(appLockProvider.notifier).setPin(first);
  if (context.mounted) {
    _toast(context, hadPin ? '二级密码已更新' : '二级密码已开启');
  }
  return true;
}

/// 关闭二级密码（需要先验证当前密码）。
Future<bool> disableAppPin(BuildContext context, WidgetRef ref) async {
  final service = ref.read(appLockServiceProvider);
  if (!service.isConfigured) return true;
  if (!context.mounted) return false;
  final pin = await _requestText(
    context,
    title: '关闭二级密码',
    label: '当前二级密码',
    helper: '关闭后私密便签将不再受保护',
  );
  if (pin == null) return false;
  final ok = await service.verify(pin);
  if (!ok) {
    if (context.mounted) {
      _toast(context, '二级密码不正确');
    }
    return false;
  }
  await ref.read(appLockProvider.notifier).clearPin();
  if (context.mounted) {
    _toast(context, '二级密码已关闭');
  }
  return true;
}

Future<String?> _requestText(
  BuildContext context, {
  required String title,
  required String label,
  String? helper,
  String? errorText,
}) async {
  final controller = TextEditingController();
  final route = DialogRoute<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => KeyboardSafeFormDialog(
      title: Text(title),
      body: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        maxLength: AppLockService.maxLength,
        inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: errorText,
          counterText: '',
        ),
        onSubmitted: (text) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) return;
          Navigator.pop(dialogContext, trimmed);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) return;
            Navigator.pop(dialogContext, trimmed);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final value = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  controller.dispose();
  return value;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
