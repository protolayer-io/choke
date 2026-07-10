import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Duration a button must be held before [HoldButton.onHoldComplete] fires
const kHoldDuration = Duration(seconds: 1);

/// A button with two actions: a quick tap fires [onTap], while pressing and
/// holding for [kHoldDuration] fires [onHoldComplete] instead (with a
/// progress fill so the operator can see the hold registering).
///
/// Used for scoring buttons (tap adds, hold subtracts) and for
/// hold-to-confirm actions like finishing or canceling a match
/// (where [onTap] is null).
class HoldButton extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onHoldComplete;
  final bool enabled;

  /// Main color for border and content
  final Color accentColor;

  /// Background color; defaults to [accentColor] at low opacity
  final Color? backgroundColor;

  /// Progress fill color while holding; defaults to [accentColor]
  final Color? holdFillColor;

  final BorderRadius borderRadius;
  final BoxBorder? border;
  final Widget child;

  const HoldButton({
    super.key,
    this.onTap,
    this.onHoldComplete,
    this.enabled = true,
    required this.accentColor,
    this.backgroundColor,
    this.holdFillColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.border,
    required this.child,
  });

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _holdFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: kHoldDuration)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _holdFired = true;
    HapticFeedback.mediumImpact();
    widget.onHoldComplete?.call();
    _controller.reset();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled || widget.onHoldComplete == null) return;
    _holdFired = false;
    _controller.forward(from: 0);
  }

  void _onTapUp(TapUpDetails _) {
    final wasHold = _holdFired;
    _cancelHold();
    if (!widget.enabled || wasHold) return;
    widget.onTap?.call();
  }

  void _onTapCancel() => _cancelHold();

  void _cancelHold() {
    _controller.stop();
    _controller.reset();
    _holdFired = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final background = widget.backgroundColor ??
        accent.withOpacity(widget.enabled ? .13 : .05);
    final fill = widget.holdFillColor ?? accent.withOpacity(.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      // Fallback for buttons without a hold action: plain tap
      onTap:
          widget.onHoldComplete == null && widget.enabled ? widget.onTap : null,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: widget.borderRadius,
            border: widget.border,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _controller.value,
                  child: ColoredBox(color: fill),
                ),
              ),
              Opacity(
                opacity: widget.enabled ? 1 : .4,
                child: Center(child: widget.child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
