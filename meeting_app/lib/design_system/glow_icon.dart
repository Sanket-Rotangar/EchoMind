import 'package:flutter/material.dart';
import 'colors.dart';

class GlowIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final bool animate;

  const GlowIcon({
    super.key,
    required this.icon,
    this.size = 32,
    this.color = AppColors.primaryAccent,
    this.animate = false,
  });

  @override
  State<GlowIcon> createState() => _GlowIconState();
}

class _GlowIconState extends State<GlowIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(widget.animate ? _animation.value * 0.6 : 0.4),
                blurRadius: widget.animate ? _animation.value * 30 : 20,
                spreadRadius: widget.animate ? _animation.value * 5 : 2,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color,
          ),
        );
      },
    );
  }
}
