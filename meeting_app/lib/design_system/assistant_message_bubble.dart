import 'dart:ui';
import 'package:flutter/material.dart';
import 'colors.dart';

class AssistantMessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final bool isTyping;

  const AssistantMessageBubble({
    super.key,
    required this.message,
    this.isUser = false,
    this.isTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 16),
        child: isUser ? _buildUserMessage() : _buildAssistantMessage(),
      ),
    );
  }

  Widget _buildUserMessage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.glassSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.borderGlass,
              width: 1,
            ),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient.scale(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.borderAccent,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isTyping
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 6),
                _buildTypingDot(1),
                const SizedBox(width: 6),
                _buildTypingDot(2),
              ],
            )
          : Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, -4 * (value * (index % 2 == 0 ? 1 : -1))),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
