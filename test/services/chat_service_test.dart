import 'package:flutter_test/flutter_test.dart';
import 'package:swaply/models/chat_message.dart';
import 'package:swaply/repositories/chats_repository.dart';
import 'package:swaply/repositories/messages_repository.dart';
import 'package:swaply/services/chat_service.dart';

class _FakeChatsRepository extends ChatsRepository {}

class _FakeMessagesRepository extends MessagesRepository {
  int? lastChatId;
  int? lastSenderId;
  String? lastContent;

  @override
  Future<ChatMessage> send({
    required int chatId,
    required int senderId,
    required String content,
  }) async {
    lastChatId = chatId;
    lastSenderId = senderId;
    lastContent = content;

    return ChatMessage(
      id: 101,
      chatId: chatId,
      senderId: senderId,
      content: content,
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  group('ChatService identity resolution', () {
    test('returns null when auth user is missing', () async {
      final service = ChatService(
        chatsRepository: _FakeChatsRepository(),
        messagesRepository: _FakeMessagesRepository(),
        authUserIdProvider: () => null,
        appUserIdResolver: (_) async => 7,
      );

      final userId = await service.refreshCurrentUserId();

      expect(userId, isNull);
      expect(service.currentUserId, isNull);
    });

    test('resolves and caches app user id from auth user id', () async {
      var resolverCalls = 0;
      final service = ChatService(
        chatsRepository: _FakeChatsRepository(),
        messagesRepository: _FakeMessagesRepository(),
        authUserIdProvider: () => 'auth-abc',
        appUserIdResolver: (_) async {
          resolverCalls += 1;
          return 42;
        },
      );

      final first = await service.refreshCurrentUserId();
      final second = await service.refreshCurrentUserId();

      expect(first, 42);
      expect(second, 42);
      expect(service.currentUserId, 42);
      expect(resolverCalls, 1);
    });
  });

  group('ChatService sendMessage', () {
    test('uses resolved app user id as sender and trims content', () async {
      final fakeMessages = _FakeMessagesRepository();
      final service = ChatService(
        chatsRepository: _FakeChatsRepository(),
        messagesRepository: fakeMessages,
        authUserIdProvider: () => 'auth-xyz',
        appUserIdResolver: (_) async => 9,
      );

      final sent = await service.sendMessage(
        chatId: 15,
        content: '  hello there  ',
      );

      expect(fakeMessages.lastChatId, 15);
      expect(fakeMessages.lastSenderId, 9);
      expect(fakeMessages.lastContent, 'hello there');
      expect(sent.senderId, 9);
      expect(sent.content, 'hello there');
    });

    test('throws when no mapped app user is available', () async {
      final service = ChatService(
        chatsRepository: _FakeChatsRepository(),
        messagesRepository: _FakeMessagesRepository(),
        authUserIdProvider: () => 'auth-no-profile',
        appUserIdResolver: (_) async => null,
      );

      expect(
        () => service.sendMessage(chatId: 1, content: 'hi'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
