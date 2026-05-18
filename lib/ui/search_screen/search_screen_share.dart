part of 'search_screen.dart';

extension _SearchScreenShare on _SearchScreenState {
  Future<void> _prepareShareContacts() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final chats = localSeenService.getChats();
    final contacts = <ShareContact>[];
    final chatMap = <String, Chat>{};
    final lastSharedLinkByPartnerId = <String, Map<String, DateTime>>{};

    for (final chat in chats) {
      final messages = await localSeenService.getMessagesWithLocal(chat.partnerId, limit: 180, startOffset: now.add(const Duration(seconds: 1)));
      final myRecentMessages = messages.where((message) => message.isMe && message.timestamp.isAfter(thirtyDaysAgo)).toList();
      final lastSharedAt = myRecentMessages.isEmpty ? chat.lastMessageAt : myRecentMessages.last.timestamp;

      final sharedLinks = <String, DateTime>{};
      for (final message in messages) {
        if (!message.isMe) continue;
        final link = message.text.trim();
        if (link.isEmpty) continue;
        final existing = sharedLinks[link];
        if (existing == null || message.timestamp.isAfter(existing)) {
          sharedLinks[link] = message.timestamp;
        }
      }
      lastSharedLinkByPartnerId[chat.partnerId] = sharedLinks;

      contacts.add(
        ShareContact(
          id: chat.partnerId,
          name: chat.partnerName,
          avatarUrl: chat.partnerProfileImageUrl,
          recentShareCount: myRecentMessages.length,
          lastSharedAt: lastSharedAt,
        ),
      );
      chatMap[chat.partnerId] = chat;
    }

    if (!mounted) return;
    setState(() {
      _shareContacts = contacts;
      _lastSharedLinkByPartnerId
        ..clear()
        ..addAll(lastSharedLinkByPartnerId);
      _chatByPartnerId
        ..clear()
        ..addAll(chatMap);
    });
  }

  Set<ShareContact> _contactsForEntry(DictionaryEntry entry) {
    final link = entry.route;
    return _shareContacts.map((contact) {
      final lastSharedAt = _lastSharedLinkByPartnerId[contact.id]?[link];
      return ShareContact(
        id: contact.id,
        name: contact.name,
        avatarUrl: contact.avatarUrl,
        recentShareCount: contact.recentShareCount,
        lastSharedAt: contact.lastSharedAt,
        alreadySharedWithThisVideo: lastSharedAt != null,
        lastSharedThisVideoAt: lastSharedAt,
      );
    }).toSet();
  }

  Future<void> _shareToContact(ShareContact contact, DictionaryEntry entry) async {
    final chat = _chatByPartnerId[contact.id];
    if (chat == null) return;

    final message = ChatMessage(id: '${contact.id}-${DateTime.now().microsecondsSinceEpoch}', text: entry.route, isMe: true, timestamp: DateTime.now());

    await chatRepository.sendNotification(chat: chat, message: message, onUserBanned: () {
      if (context.mounted) {
        routerConfig.go('/login-force');
      }
    });
    await localSeenService.sendMessageLocal(chat, message);
    if (!mounted) return;
    print("PREPARING!");
    await _prepareShareContacts();
    print("PREPARED!");
  }
}

