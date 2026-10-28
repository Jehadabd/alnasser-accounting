import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/ai_chat_service.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';

/// شاشة الدردشة مع الذكاء الاصطناعي
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({Key? key}) : super(key: key);

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  late AIChatService _chatService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _addWelcomeMessage();
  }

  Future<void> _initializeService() async {
    debugPrint('🚀 AI Chat Screen: تهيئة الخدمة...');
    
    final dbService = DatabaseService();
    await dbService.database;
    
    // قراءة مفاتيح Gemini من .env
    final geminiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final geminiKey2 = dotenv.env['GEMINI_API_KEY_2'] ?? '';
    final geminiKey3 = dotenv.env['GEMINI_API_KEY_3'] ?? '';
    
    final geminiKeysCount = [geminiKey, geminiKey2, geminiKey3].where((k) => k.isNotEmpty).length;
    debugPrint('🔑 Gemini API Keys: $geminiKeysCount مفتاح/مفاتيح ${geminiKeysCount > 0 ? "✅" : "❌"}');
    
    GeminiService? geminiService;
    if (geminiKeysCount > 0) {
      geminiService = GeminiService(
        apiKey: geminiKey.isNotEmpty ? geminiKey : (geminiKey2.isNotEmpty ? geminiKey2 : geminiKey3),
        apiKey2: geminiKey2.isNotEmpty ? geminiKey2 : null,
        apiKey3: geminiKey3.isNotEmpty ? geminiKey3 : null,
      );
      debugPrint('✅ تم تفعيل Gemini ($geminiKeysCount مفاتيح)');
    }
    
    _chatService = AIChatService(
      dbService,
      geminiService: geminiService,
    );
    
    debugPrint('✅ AI Chat Service جاهز!');
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(ChatMessage(
        text: "مرحبًا! أنا مساعدك الذكي 🤖\n\n"
              "يمكنني مساعدتك في:\n"
              "• تدقيق جميع الحسابات والأرصدة\n"
              "• فحص صحة الفواتير والمعاملات\n"
              "• التحقق من المخزون والوحدات\n"
              "• كشف الأخطاء المحاسبية\n"
              "• إنشاء التقارير والملخصات\n\n"
              "اختر من الاقتراحات أو اكتب طلبك:",
        isUser: false,
        suggestions: AIChatService.defaultSuggestions,
      ));
    });
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: message, isUser: true));
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final response = await _chatService.processMessage(
        message,
        conversationHistory: _messages.map((m) => m.text).toList(),
      );

      setState(() {
        _messages.add(ChatMessage(
          text: response.text,
          isUser: false,
          suggestions: response.followups,
          status: response.status,
          data: response.data,
        ));
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: "عذرًا، حدث خطأ: ${e.toString()}",
          isUser: false,
          status: 'error',
        ));
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الدردشة مع الذكاء الاصطناعي'),
          backgroundColor: Colors.blue[700],
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _addWelcomeMessage();
                });
              },
              tooltip: 'بدء محادثة جديدة',
            ),
          ],
        ),
        body: Column(
          children: [
            // قائمة الرسائل
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),

            // مؤشر التحميل
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('جاري التحليل...'),
                  ],
                ),
              ),

            // حقل الإدخال
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    spreadRadius: 1,
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendMessage(_messageController.text),
                    color: Colors.blue[700],
                    iconSize: 28,
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
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          // فقاعة الرسالة
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser
                  ? Colors.blue[100]
                  : _getStatusColor(message.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 15,
                color: message.isUser ? Colors.black87 : Colors.black,
              ),
            ),
          ),

          // الاقتراحات السريعة
          if (message.suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: message.suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () => _sendMessage(suggestion),
                  backgroundColor: Colors.blue[50],
                  labelStyle: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green[50]!;
      case 'warning':
        return Colors.orange[50]!;
      case 'error':
        return Colors.red[50]!;
      default:
        return Colors.grey[100]!;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}


