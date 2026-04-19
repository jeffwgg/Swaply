import 'package:flutter_test/flutter_test.dart';
import 'package:swaply/models/chat_message.dart';
import 'package:swaply/repositories/chats_repository.dart';
import 'package:swaply/repositories/messages_repository.dart';
import 'package:swaply/services/chat_service.dart';

class _FakeChatsRepository extends ChatsRepository {}

class _FakeMessagesRepository extends MessagesRepository {
  int? lastChatId;
  String? lastSenderId;
  String? lastContent;

  @override
  Future<ChatMessage> send({
    required int chatId,
    required String senderId,
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
        appUserIdResolver: (_) async => '7b3f4f40-73b1-4cd0-aedf-f5f8f36fd6c8',
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
          return '5a265f7e-2724-4bc6-9136-c3ed1d5bd798';
        },
      );

      final first = await service.refreshCurrentUserId();
      final second = await service.refreshCurrentUserId();

      expect(first, '5a265f7e-2724-4bc6-9136-c3ed1d5bd798');
      expect(second, '5a265f7e-2724-4bc6-9136-c3ed1d5bd798');
      expect(service.currentUserId, '5a265f7e-2724-4bc6-9136-c3ed1d5bd798');
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
        appUserIdResolver: (_) async => 'e6d7a5c1-545f-4caf-bf11-b4f594341f0a',
      );

      final sent = await service.sendMessage(
        chatId: 15,
        content: '  hello there  ',
      );

      expect(fakeMessages.lastChatId, 15);
      expect(fakeMessages.lastSenderId, 'e6d7a5c1-545f-4caf-bf11-b4f594341f0a');
      expect(fakeMessages.lastContent, 'hello there');
      expect(sent.senderId, 'e6d7a5c1-545f-4caf-bf11-b4f594341f0a');
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
