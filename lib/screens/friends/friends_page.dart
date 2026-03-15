import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../chat/chat_detail_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all'; // all, online, offline

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddFriendDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: Consumer<FriendProvider>(
              builder: (context, friendProvider, child) {
                if (friendProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                List<Friend> filteredFriends = friendProvider.friends;
                if (_selectedFilter == 'online') {
                  filteredFriends = friendProvider.onlineFriends;
                } else if (_selectedFilter == 'offline') {
                  filteredFriends = friendProvider.friends
                      .where((f) => f.user.status != 'online')
                      .toList();
                }

                if (filteredFriends.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.separated(
                  itemCount: filteredFriends.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _buildFriendItem(context, filteredFriends[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索好友',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    context.read<FriendProvider>().setSearchQuery('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          filled: true,
        ),
        onChanged: (value) {
          context.read<FriendProvider>().setSearchQuery(value);
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _selectedFilter == 'all',
            onSelected: (selected) {
              setState(() => _selectedFilter = 'all');
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('在线'),
            selected: _selectedFilter == 'online',
            onSelected: (selected) {
              setState(() => _selectedFilter = 'online');
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('离线'),
            selected: _selectedFilter == 'offline',
            onSelected: (selected) {
              setState(() => _selectedFilter = 'offline');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无好友',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendItem(BuildContext context, Friend friend) {
    return InkWell(
      onTap: () => _showFriendOptions(context, friend),
      onLongPress: () => _showFriendOptions(context, friend),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: friend.user.avatar != null
                      ? NetworkImage(friend.user.avatar!)
                      : null,
                  child: friend.user.avatar == null
                      ? Text(friend.user.nickname.substring(0, 1))
                      : null,
                ),
                if (friend.user.status == 'online')
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    friend.user.signature ?? '这个人很懒，什么都没写',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _showFriendOptions(BuildContext context, Friend friend) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('发消息'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatDetailPage(friend: friend.user),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('设置备注'),
              onTap: () {
                Navigator.pop(context);
                _showEditRemarkDialog(context, friend);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除好友', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteFriendDialog(context, friend);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFriendDialog(BuildContext context) {
    final TextEditingController userIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加好友'),
        content: TextField(
          controller: userIdController,
          decoration: const InputDecoration(
            labelText: '用户ID',
            hintText: '请输入要添加的用户ID',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final userId = userIdController.text.trim();
              if (userId.isNotEmpty) {
                Navigator.pop(context);
                // Send friend request
                await context
                    .read<FriendProvider>()
                    .sendFriendRequest(userId, '我想加你为好友');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('好友请求已发送')),
                  );
                }
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  void _showEditRemarkDialog(BuildContext context, Friend friend) {
    final TextEditingController remarkController =
        TextEditingController(text: friend.remark);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置备注'),
        content: TextField(
          controller: remarkController,
          decoration: const InputDecoration(
            labelText: '备注名',
            hintText: '请输入备注名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final remark = remarkController.text.trim();
              await context
                  .read<FriendProvider>()
                  .updateRemark(friend.id, remark);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('备注已更新')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFriendDialog(BuildContext context, Friend friend) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除 ${friend.displayName} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<FriendProvider>().removeFriend(friend.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('好友已删除')),
                );
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
