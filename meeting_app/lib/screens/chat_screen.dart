import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';

class ChatScreen extends StatefulWidget {
  final String? meetingId;
  final String? meetingTitle;

  const ChatScreen({
    super.key,
    this.meetingId,
    this.meetingTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  bool get _isMeetingMode =>
      widget.meetingId != null && widget.meetingId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final welcomeText = _isMeetingMode
        ? "Hi! I'm your EchoMind assistant for this meeting. Ask about this transcript, summary, decisions, action items, or deadlines."
        : "Hi! I'm your EchoMind assistant. Ask me anything about your meetings - like \"What did we discuss with the marketing team?\" or \"When is the annual review?\"";

    _messages.add(ChatMessage(
      text: welcomeText,
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await ApiService.sendChatMessage(
        message,
        meetingId: widget.meetingId,
      );
      final assistantMessage = response['response'] as String? ?? 'Sorry, I couldn\'t process that request.';
      final meetingsSearched = response['meetings_searched'] as int? ?? 0;

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: assistantMessage,
            isUser: false,
            timestamp: DateTime.now(),
            meetingsSearched: meetingsSearched,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: 'Sorry, something went wrong. Please try again.',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // App Logo Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'EchoMind',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isMeetingMode ? 'Meeting Assistant' : 'Assistant',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isMeetingMode
                              ? 'Ask questions about this meeting only'
                              : 'Ask questions about your meetings',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryPeach.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.primaryPeach,
                    ),
                  ),
                ],
              ),
            ),

            if (_isMeetingMode &&
                widget.meetingTitle != null &&
                widget.meetingTitle!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPeach.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primaryPeach.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      'Context: ${widget.meetingTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryPeach,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isLoading) {
                    return _buildTypingIndicator();
                  }
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: _isMeetingMode
                              ? 'Ask about this meeting...'
                              : 'Ask about your meetings...',
                          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isLoading ? AppColors.border : AppColors.primaryPeach,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: _isLoading ? AppColors.textSecondary : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryPeach.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppColors.primaryPeach,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(message.isUser ? 14 : 16),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? AppColors.primaryPeach
                        : message.isError
                            ? Colors.red.withOpacity(0.1)
                            : AppColors.surface,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: message.isUser ? const Radius.circular(4) : null,
                      bottomLeft: !message.isUser ? const Radius.circular(4) : null,
                    ),
                    border: message.isUser
                        ? null
                        : Border.all(color: message.isError ? Colors.red.withOpacity(0.2) : AppColors.border),
                  ),
                  child: message.isUser
                      ? Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        )
                      : _FormattedText(
                          text: message.text,
                          isError: message.isError,
                        ),
                ),
                if (message.meetingsSearched != null && message.meetingsSearched! > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search,
                        size: 12,
                        color: AppColors.textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${message.meetingsSearched} meeting${message.meetingsSearched == 1 ? '' : 's'} searched',
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryPeach.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person,
                color: AppColors.primaryPeach,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryPeach.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppColors.primaryPeach,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Thinking',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const _AnimatedDots(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated dots for typing indicator
class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value + delay) % 1.0);
            final opacity = value < 0.5 ? value * 2 : 2 - value * 2;
            return Container(
              margin: EdgeInsets.only(left: index > 0 ? 3 : 0),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.primaryPeach.withOpacity(0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Renders formatted text with visual hierarchy
/// - Section headers: larger, bold, peach accent
/// - Bullets: indented with peach dots
/// - Regular text: clean and readable
class _FormattedText extends StatelessWidget {
  final String text;
  final bool isError;

  const _FormattedText({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    // Clean up any markdown symbols that might have slipped through
    final cleanedText = _cleanMarkdown(text);
    final lines = cleanedText.split('\n');
    final widgets = <Widget>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Empty line = spacing
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }
      
      // Section header: line ending with colon (not a bullet, reasonable length)
      // e.g., "Marketing Discussion (March 15th):" or "Next Steps:"
      final isHeader = line.trim().endsWith(':') && 
          !line.trim().startsWith('-') && 
          !line.trim().startsWith('•') &&
          !line.trim().contains(' - ') && // Not "Item - description:"
          line.trim().length < 80;
      
      if (isHeader) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: i > 0 ? 14 : 0, bottom: 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primaryPeach,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.trim(),
                  style: TextStyle(
                    color: isError ? Colors.red : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      
      // Bullet point: starts with "- " or "• "
      if (line.trim().startsWith('- ') || line.trim().startsWith('• ')) {
        final bulletText = line.trim().substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPeach.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bulletText,
                  style: TextStyle(
                    color: isError ? Colors.red : AppColors.textPrimary.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      
      // Numbered list: starts with "1. ", "2. ", etc.
      final numberedMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line.trim());
      if (numberedMatch != null) {
        final number = numberedMatch.group(1)!;
        final content = numberedMatch.group(2)!;
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$number.',
                  style: TextStyle(
                    color: AppColors.primaryPeach,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  content,
                  style: TextStyle(
                    color: isError ? Colors.red : AppColors.textPrimary.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      
      // Regular paragraph text
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          line,
          style: TextStyle(
            color: isError ? Colors.red : AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Cleans markdown symbols while preserving readable text
  String _cleanMarkdown(String text) {
    var cleaned = text;
    
    // Remove # headers (keep text)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^#{1,6}\s*(.*)$', multiLine: true),
      (match) => match.group(1) ?? '',
    );
    
    // Remove **bold** markers (keep text)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*'),
      (match) => match.group(1) ?? '',
    );
    
    // Remove *italic* markers (keep text)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^\*\n]+?)\*(?!\*)'),
      (match) => match.group(1) ?? '',
    );
    
    // Convert "* " bullets to "- "
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^\*\s+', multiLine: true),
      (match) => '- ',
    );
    
    // Remove backticks (code markers)
    cleaned = cleaned.replaceAll('`', '');
    
    // Clean up multiple consecutive newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    return cleaned.trim();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final int? meetingsSearched;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.meetingsSearched,
    this.isError = false,
  });
}
