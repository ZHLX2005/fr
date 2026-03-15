import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/storage_helper.dart';

class MockDataService {
  static const Uuid _uuid = Uuid();

  static Future<void> generateTestData() async {
    // Check if data already exists
    final existingUsers = await StorageHelper.getUsers();
    if (existingUsers.isNotEmpty) return;

    // Create test users
    final users = <User>[
      User(
        id: 'user1',
        nickname: '我',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=me',
        status: 'online',
        signature: '生活就是编码',
        createdAt: DateTime.now(),
      ),
      User(
        id: 'user2',
        nickname: '张三',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=zhangsan',
        status: 'online',
        signature: 'Flutter开发者',
        createdAt: DateTime.now(),
      ),
      User(
        id: 'user3',
        nickname: '李四',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=lisi',
        status: 'offline',
        signature: 'Dart爱好者',
        createdAt: DateTime.now(),
      ),
      User(
        id: 'user4',
        nickname: '王五',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=wangwu',
        status: 'away',
        signature: '移动开发专家',
        createdAt: DateTime.now(),
      ),
      User(
        id: 'user5',
        nickname: '赵六',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=zhaoliu',
        status: 'online',
        signature: '全栈工程师',
        createdAt: DateTime.now(),
      ),
    ];

    // Create test messages
    final messages = <Message>[
      Message(
        id: _uuid.v4(),
        senderId: 'user2',
        receiverId: 'user1',
        content: '你好！最近在做什么项目？',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        readAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      Message(
        id: _uuid.v4(),
        senderId: 'user1',
        receiverId: 'user2',
        content: '在做一个Flutter聊天应用',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
        readAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
      ),
      Message(
        id: _uuid.v4(),
        senderId: 'user2',
        receiverId: 'user1',
        content: '太棒了！Flutter确实很强大',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
        readAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      Message(
        id: _uuid.v4(),
        senderId: 'user3',
        receiverId: 'user1',
        content: '周末有空一起去打球吗？',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      Message(
        id: _uuid.v4(),
        senderId: 'user4',
        receiverId: 'user1',
        content: '代码review过了，很棒！',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      Message(
        id: _uuid.v4(),
        senderId: 'user5',
        receiverId: 'user1',
        content: '新需求下来了，记得看邮件',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    ];

    // Create test friends
    final friends = <Friend>[
      Friend(
        id: _uuid.v4(),
        user: users[1], // 张三
        status: FriendStatus.accepted,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      Friend(
        id: _uuid.v4(),
        user: users[2], // 李四
        status: FriendStatus.accepted,
        createdAt: DateTime.now().subtract(const Duration(days: 25)),
      ),
      Friend(
        id: _uuid.v4(),
        user: users[3], // 王五
        status: FriendStatus.accepted,
        remark: '王工',
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      Friend(
        id: _uuid.v4(),
        user: users[4], // 赵六
        status: FriendStatus.accepted,
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
    ];

    // Create test sessions
    final sessions = <ChatSession>[
      ChatSession(
        id: _uuid.v4(),
        userId: 'user1',
        friendId: 'user2',
        lastMessage: messages[2],
        unreadCount: 0,
        updatedAt: messages[2].createdAt,
      ),
      ChatSession(
        id: _uuid.v4(),
        userId: 'user1',
        friendId: 'user3',
        lastMessage: messages[3],
        unreadCount: 1,
        updatedAt: messages[3].createdAt,
      ),
      ChatSession(
        id: _uuid.v4(),
        userId: 'user1',
        friendId: 'user4',
        lastMessage: messages[4],
        unreadCount: 1,
        updatedAt: messages[4].createdAt,
      ),
      ChatSession(
        id: _uuid.v4(),
        userId: 'user1',
        friendId: 'user5',
        lastMessage: messages[5],
        unreadCount: 1,
        updatedAt: messages[5].createdAt,
      ),
    ];

    // Save all data
    await StorageHelper.saveUsers(users.map((u) => u.toJson()).toList());
    await StorageHelper.saveMessages(messages.map((m) => m.toJson()).toList());
    await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
    await StorageHelper.saveSessions(sessions.map((s) => s.toJson()).toList());
    await StorageHelper.setCurrentUser('user1');
  }
}
