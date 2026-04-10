import 'package:flutter/material.dart';
import 'colors.dart';

class NeumorphicButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final double borderRadius;

  const NeumorphicButton({
    super.key,
    required this.child,
    this.onPressed,
    this.width = 200,
    this.height = 56,
    this.borderRadius = 16,
  });

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(8, 8),
                    blurRadius: 16,
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.05),
                    offset: const Offset(-4, -4),
                    blurRadius: 8,
                  ),
                ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}
