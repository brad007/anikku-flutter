import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Every actionable surface shares the same keyboard/remote activation and focus ring.
class TvButton extends StatefulWidget {
  const TvButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.selected = false,
    this.primary = false,
    this.quiet = false,
    this.card = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    this.label,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool selected;
  final bool primary;
  final bool quiet;
  final bool card;
  final EdgeInsets padding;
  final String? label;
  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  bool focused = false;
  final _ownedNode = FocusNode();
  FocusNode get node => widget.focusNode ?? _ownedNode;
  @override
  void dispose() {
    _ownedNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    enabled: widget.onPressed != null,
    focused: focused,
    child: FocusableActionDetector(
      focusNode: node,
      autofocus: widget.autofocus,
      enabled: widget.onPressed != null,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      onFocusChange: (value) {
        setState(() => focused = value);
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 180),
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            }
          });
        }
      },
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed == null
              ? null
              : () {
                  node.requestFocus();
                  widget.onPressed!();
                },
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.card
                  ? Colors.transparent
                  : focused
                  ? Colors.white
                  : widget.primary
                  ? Colors.white
                  : widget.quiet
                  ? Colors.transparent
                  : panel.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(widget.card ? 6 : 4),
              border: Border.all(
                color: focused
                    ? (widget.primary ? brandRed : Colors.white)
                    : widget.selected
                    ? brandRed
                    : Colors.transparent,
                width: 3,
              ),
              boxShadow: focused && widget.card
                  ? [const BoxShadow(color: Colors.black54, blurRadius: 18)]
                  : null,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: !widget.card && (focused || widget.primary)
                    ? ink
                    : Colors.white,
                size: 22,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: widget.onPressed == null
                      ? muted
                      : !widget.card && (focused || widget.primary)
                      ? ink
                      : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.text, {
    super.key,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.selected = false,
    this.primary = false,
  });
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool selected;
  final bool primary;
  @override
  Widget build(BuildContext context) => TvButton(
    onPressed: onPressed,
    autofocus: autofocus,
    focusNode: focusNode,
    selected: selected,
    primary: primary,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Flexible(child: Text(text)),
      ],
    ),
  );
}
