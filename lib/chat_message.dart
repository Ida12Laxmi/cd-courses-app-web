import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'secure_content_viewer_screen.dart';
import "config/api_config.dart";

class ChatMessage {
  final int messageId;
  final String senderType; // 'teacher' or 'student'
  final String text;
  final String? attachment; // relative or absolute file path from backend
  final List<String> reactions;

  ChatMessage({
    required this.messageId,
    required this.senderType,
    required this.text,
    required this.attachment,
    required this.reactions,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    List<String> reactionEmojis = [];
    if (json['reactions'] != null) {
      for (var r in json['reactions']) {
        reactionEmojis.add(r['emoji']);
      }
    }
    return ChatMessage(
      messageId: json['message_id'],
      senderType: json['sender_type'],
      text: json['text'] ?? '',
      attachment: json['attachment'],
      reactions: reactionEmojis,
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String topicTitle; // e.g., "Messages" or "Leave and Delays"
  final String currentUserType; // 'student' or 'teacher'
  final int teacherId;
  final int studentId;

  const ChatScreen({
    super.key,
    required this.topicTitle,
    required this.currentUserType,
    required this.teacherId,
    required this.studentId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();

  List<ChatMessage> _messages = [];
  int? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  File? _pickedFile;

  // API calls live under /accounts/
  static const String _apiBaseUrl = ApiConfig.baseUrl;
  // Uploaded files (media) are served from the server root
  static const String _mediaBaseUrl = ApiConfig.mediaBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadConversationAndMessages();
  }

  Future<void> _loadConversationAndMessages() async {
    final url = Uri.parse('$_apiBaseUrl/conversations/get-or-create/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teacher': widget.teacherId,
          'student': widget.studentId,
          'topic': widget.topicTitle.toLowerCase().replaceAll(' ', '_'),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _conversationId = data['conversation']['convid'];

        final loadedMessages = (data['messages'] as List)
            .map((msg) => ChatMessage.fromJson(msg))
            .toList();

        setState(() {
          _messages = loadedMessages;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load chat (${response.statusCode}): ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to server: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _pickedFile = File(result.files.single.path!));
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _pickedFile == null) return;
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not ready yet, please wait a moment')),
      );
      return;
    }

    setState(() => _isSending = true);

    final url = Uri.parse('$_apiBaseUrl/messages/send/');
    final request = http.MultipartRequest('POST', url);
    request.fields['convid'] = _conversationId.toString();
    request.fields['sender_type'] = widget.currentUserType;
    request.fields['text'] = text;

    if (_pickedFile != null) {
      request.files.add(await http.MultipartFile.fromPath('attachment', _pickedFile!.path));
    }

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        setState(() {
          _messages.add(ChatMessage.fromJson(data));
          _textController.clear();
          _pickedFile = null;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

Future<void> _openAttachment(String attachment) async {
  final urlToOpen = attachment.startsWith('http') ? attachment : '$_mediaBaseUrl$attachment';
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => SecureContentViewerScreen.forAttachment(
        url: urlToOpen,
        fileName: attachment.split('/').last,
      ),
      fullscreenDialog: true,
    ),
  );
}

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    // 1. Optimistic UI update for immediate response
    setState(() {
      final existingIndex = message.reactions.indexOf(emoji);

      if (existingIndex != -1) {
        // Tapping the same emoji removes it (toggle off)
        message.reactions.removeAt(existingIndex);
      } else {
        // Replace any existing reaction with the new one
        message.reactions.clear();
        message.reactions.add(emoji);
      }
    });

    final url = Uri.parse('$_apiBaseUrl/messages/react/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message_id': message.messageId,
          'user_type': widget.currentUserType,
          'emoji': emoji,
        }),
      );

      // 2. Sync state with the ground-truth list returned by Django
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> updatedReactions = data['reactions'] ?? [];

        if (mounted) {
          setState(() {
            message.reactions.clear();
            for (var r in updatedReactions) {
              message.reactions.add(r['emoji'].toString());
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error toggling reaction: $e");
    }
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || newText == message.text) return;

    final url = Uri.parse('$_apiBaseUrl/messages/edit/${message.messageId}/');
    try {
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': newText}),
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = _messages.indexWhere((m) => m.messageId == message.messageId);
          if (index != -1) {
            _messages[index] = ChatMessage(
              messageId: message.messageId,
              senderType: message.senderType,
              text: newText,
              attachment: message.attachment,
              reactions: message.reactions,
            );
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not edit message: $e')),
        );
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsend message'),
        content: const Text('This message will be removed for everyone. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final url = Uri.parse('$_apiBaseUrl/messages/delete/${message.messageId}/');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        setState(() {
          _messages.removeWhere((m) => m.messageId == message.messageId);
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete message: $e')),
        );
      }
    }
  }

  void _showMoreOptions(BuildContext context, ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Pin'),
              subtitle: const Text('Coming soon'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageActions(BuildContext context, ChatMessage message) {
    final isMe = message.senderType == widget.currentUserType;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              
              // Reaction Emojis Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                  final isSelected = message.reactions.contains(emoji);
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _toggleReaction(message, emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.deepPurple.shade50 : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),

              // Messenger-like "Tap to remove" section
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    // Pass current emoji to toggle it off
                    _toggleReaction(message, message.reactions.first);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          message.reactions.first,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Tap to remove reaction",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const Divider(height: 16),
              if (message.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(message);
                  },
                ),
              if (isMe && message.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editMessage(message);
                  },
                ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Unsend', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.more_horiz),
                title: const Text('More'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoreOptions(context, message);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topicTitle),
        backgroundColor: const Color(0xFF013768),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(child: Text("No messages yet. Say hi!"))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isMe = msg.senderType == widget.currentUserType;

                                return Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: GestureDetector(
                                    onLongPress: () => _showMessageActions(context, msg),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isMe ? Colors.deepPurple.shade400 : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (msg.attachment != null && msg.attachment!.isNotEmpty)
                                                  GestureDetector(
                                                    onTap: () => _openAttachment(msg.attachment!),
                                                    child: Container(
                                                      margin: const EdgeInsets.only(bottom: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                      decoration: BoxDecoration(
                                                        color: isMe
                                                            ? Colors.white.withValues(alpha: 0.15)
                                                            : Colors.white,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.insert_drive_file,
                                                            size: 18,
                                                            color: isMe ? Colors.white : Colors.deepPurple,
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Flexible(
                                                            child: Text(
                                                              msg.attachment!.split('/').last,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: isMe ? Colors.white : Colors.deepPurple,
                                                                decoration: TextDecoration.underline,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                if (msg.text.isNotEmpty)
                                                  Text(
                                                    msg.text,
                                                    style: TextStyle(
                                                      color: isMe ? Colors.white : Colors.black87,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),

                                          // TAPPABLE REACTION BADGE
                                          if (msg.reactions.isNotEmpty)
                                            Positioned(
                                              bottom: -10,
                                              right: isMe ? null : -5,
                                              left: isMe ? -5 : null,
                                              child: GestureDetector(
                                                onTap: () {
                                                  // Directly tap reaction on bubble to remove it
                                                  _toggleReaction(msg, msg.reactions.first);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                    boxShadow: const [
                                                      BoxShadow(color: Colors.black12, blurRadius: 2)
                                                    ],
                                                  ),
                                                  child: Text(
                                                    msg.reactions.join(' '),
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (_pickedFile != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.grey.shade100,
                        child: Row(
                          children: [
                            const Icon(Icons.attach_file, size: 16, color: Colors.purple),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _pickedFile!.path.split('/').last,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _pickedFile = null),
                            ),
                          ],
                        ),
                      ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        color: Colors.white,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: Colors.purple),
                              onPressed: _pickFile,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                decoration: InputDecoration(
                                  hintText: "Type a message...",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  fillColor: Colors.grey.shade100,
                                  filled: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              backgroundColor: Colors.deepPurple,
                              child: _isSending
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                                      onPressed: _sendMessage,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}