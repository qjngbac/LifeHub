import 'package:flutter/material.dart';

class KeyboardSafeFormDialog extends StatelessWidget {
  const KeyboardSafeFormDialog({
    required this.title,
    required this.body,
    required this.actions,
    super.key,
  });

  final Widget title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height -
        media.viewInsets.bottom -
        media.padding.vertical -
        32;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: availableHeight.clamp(240, 720).toDouble(),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.headlineSmall!,
                child: title,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(top: 8),
                child: body,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions
                  .expand((action) => [const SizedBox(width: 8), action])
                  .toList(),
            ),
          ]),
        ),
      ),
    );
  }
}
