import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/theme.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      text: "Hi! I'm your assistant for the '${widget.groupName}' group. Ask me anything about the meetings in this group!",
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
      final response = await ApiService.sendGroupChatMessage(widget.groupId, message);
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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Group Chat',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.groupName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _ChatBubble(message: message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  SizedBox(width: 16),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(
                top: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Ask about this group...',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.arrow_upward,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: AppColors.background,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primaryPeach,
          unselectedItemColor: AppColors.textSecondary,
          currentIndex: 2, // Groups tab
          onTap: (index) {
            // Navigate to the appropriate tab
            if (index == 0) {
              // Record - go back to home
              Navigator.popUntil(context, (route) => route.isFirst);
            } else if (index == 1) {
              // Meetings - go back and switch to meetings
              Navigator.popUntil(context, (route) => route.isFirst);
            } else if (index == 2) {
              // Groups - go back to groups list
              Navigator.pop(context);
            } else if (index == 3) {
              // Assistant - go back and switch to assistant
              Navigator.popUntil(context, (route) => route.isFirst);
            } else if (index == 4) {
              // Settings - go back and switch to settings
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Record'),
            BottomNavigationBarItem(
              icon: Icon(Icons.format_list_bulleted),
              label: 'Meetings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome),
              label: 'Assistant',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.smart_toy,
                color: AppColors.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? AppColors.accent
                        : (message.isError
                            ? Colors.red.withOpacity(0.1)
                            : AppColors.cardBackground),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser
                          ? Colors.black
                          : (message.isError
                              ? Colors.red
                              : AppColors.textPrimary),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
                if (!message.isUser && message.meetingsSearched != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Searched ${message.meetingsSearched} meeting${message.meetingsSearched == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.person,
                color: Colors.black,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
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
