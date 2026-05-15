import '../../base_logic.dart';
import '../local_storage/local_seen_service.dart';
import '../users/user_model.dart';

class Chat {
  int conversationId;
  DateTime createdAt;
  String currentUserId;
  String partnerId;
  String partnerName;
  String partnerProfileImageUrl;
  DateTime? lastMessageAt;
  String lastMessage;
  bool lastMessageByMe;
  bool partnerIsAi;
  String conversationType;

  Chat({
    required this.conversationId,
    String? currentUserReplacementId,
    required this.partnerId,
    required this.partnerProfileImageUrl,
    required this.partnerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageByMe,
    required this.createdAt,
    required this.partnerIsAi,
    this.conversationType = 'direct',
  }) : currentUserId = currentUserReplacementId ?? currentUser.id;

  bool get isAiConversation => conversationType == 'direct-ai';

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'currentUserId': currentUserId,
    'partnerId': partnerId,
    'partnerName': partnerName,
    'partnerProfileImageUrl': partnerProfileImageUrl,
    'lastMessageAt': lastMessageAt,
    'lastMessage': lastMessage,
    'lastMessageByMe': lastMessageByMe,
    'createdAt': createdAt,
    'partnerIsAi': partnerIsAi,
    'conversationType': conversationType,
  };

  factory Chat.fromJson(Map<dynamic, dynamic> json, {String? customPartnerId}) {
    String currentUserId = json['currentUserId'] ?? currentUser.id;
    String partnerId = json['partnerId'] ?? customPartnerId ?? '';
    String partnerName = json['partnerName'];
    String partnerProfileImageUrl = json['partnerProfileImageUrl'];
    DateTime? lastMessageAt = _parseDateTimeNullable(json['lastMessageAt']);
    String lastMessage = json['lastMessage'];
    bool lastMessageByMe = json['lastMessageByMe'] ?? true;
    DateTime createdAt = _parseDateTime(json['createdAt']);
    return Chat(
      conversationId: json['conversationId'] as int,
      partnerId: partnerId,
      partnerProfileImageUrl: partnerProfileImageUrl,
      partnerName: partnerName,
      currentUserReplacementId: currentUserId,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      lastMessageByMe: lastMessageByMe,
      createdAt: createdAt,
      partnerIsAi: json['partnerIsAi'] ?? (json['conversationType'] != null && json['conversationType'] == 'direct-ai') ?? false,
      conversationType: json['conversationType'] ?? 'direct',
    );
  }

  @override
  String toString() =>
      'Chat(conversationId: $conversationId, currentUserId: $currentUserId, partnerId: $partnerId, partnerName: $partnerName, lastMessageAt: $lastMessageAt, lastMessage: $lastMessage, lastMessageByMe: $lastMessageByMe, createdAt: $createdAt)';
}

class ChatManager {
  static ChatManager? _currentInstance;

  factory ChatManager() {
    if (_currentInstance?.userId != currentUser.id || _currentInstance == null) {
      _currentInstance = ChatManager._internal(currentUser.id);
    }
    return _currentInstance!;
  }

  ChatManager._internal(this.userId) : chats = localSeenService.getChats();
  String userId;
  List<Chat> chats;

  void addChat(Chat chat, {bool replaceExisting = true}) {
    if (!chats.any((element) => element.partnerId == chat.partnerId)) {
      chats.add(chat);
    } else if (replaceExisting) {
      chats.remove(chat);
      chats.add(chat);
    }
  }
}

ChatManager get chatManager => ChatManager();

DateTime _parseDateTime(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.parse(value).toLocal();
  return DateTime.now().toLocal();
}

DateTime? _parseDateTimeNullable(Object? value) {
  if (value == null) return null;
  return _parseDateTime(value);
}
