import 'dart:ui';
import 'package:flutter/material.dart';
import 'colors.dart';

class BentoTile extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool showGradientBorder;
  final Gradient? gradient;

  const BentoTile({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.onTap,
    this.showGradientBorder = false,
    this.gradient,
  });

  @override
  State<BentoTile> createState() => _BentoTileState();
}

class _BentoTileState extends State<BentoTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.width,
          height: widget.height,
          transform: _isHovered
              ? (Matrix4.identity()..translate(0.0, -4.0, 0.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? AppColors.primaryAccent.withOpacity(0.2)
                    : Colors.black.withOpacity(0.2),
                blurRadius: _isHovered ? 30 : 20,
                offset: Offset(0, _isHovered ? 15 : 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.glassSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.showGradientBorder
                        ? AppColors.borderAccent
                        : AppColors.borderGlass,
                    width: 1,
                  ),
                  gradient: widget.gradient,
                ),
                padding: widget.padding ?? const EdgeInsets.all(20),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
