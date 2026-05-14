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
  }) : currentUserId = currentUserReplacementId ?? currentUser.id;

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
    );
  }

  factory Chat.fromSupabase({
    required Map<String, dynamic> conversation,
    required UserProfile partner,
    required String currentUserId,
    String? lastMessage,
    bool lastMessageByMe = false,
  }) {
    final createdAtValue = conversation['created_at'];
    final updatedAtValue = conversation['updated_at'];
    final createdAt = _parseDateTime(createdAtValue);
    final updatedAt = _parseDateTime(updatedAtValue);

    print(
      "Creating chat from supabase data: conversationId=${conversation['id']}, partnerId=${partner.id}, createdAt=$createdAt, updatedAt=$updatedAt, lastMessage=$lastMessage, lastMessageByMe=$lastMessageByMe",
    );

    return Chat(
      conversationId: conversation['id'] as int,
      currentUserReplacementId: currentUserId,
      partnerId: partner.id,
      partnerProfileImageUrl: partner.profileImageUrl,
      partnerName: partner.username,
      lastMessage: lastMessage ?? '',
      lastMessageAt: updatedAt,
      lastMessageByMe: lastMessageByMe,
      createdAt: createdAt,
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
