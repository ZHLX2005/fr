import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../lab/lab_container.dart';

class WebRTCCallDemo extends DemoPage {
  @override
  String get title => '视频通话';

  @override
  String get description => 'WebRTC 视频通话测试';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const WebRTCCallPage();
  }
}

void registerWebRTCCallDemo() {
  demoRegistry.register(WebRTCCallDemo());
}

class WebRTCCallPage extends StatefulWidget {
  const WebRTCCallPage({super.key});

  @override
  State<WebRTCCallPage> createState() => _WebRTCCallPageState();
}

class _WebRTCCallPageState extends State<WebRTCCallPage> {
  // 信令服务器地址
  static const String _wsUrl = 'ws://47.110.80.47:8988/ws/rtc';

  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _targetUserController = TextEditingController();

  WebSocketChannel? _wsChannel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  String? _myUserId;
  String? _currentRoom;
  List<UserInfo> _roomMembers = [];
  bool _isConnected = false;
  bool _isInCall = false;
  bool _isMakingCall = false;
  String? _errorMessage;

  // STUN/TURN 配置
  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer!.initialize();
    await _remoteRenderer!.initialize();
  }

  @override
  void dispose() {
    _roomController.dispose();
    _targetUserController.dispose();
    _hangUp();
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final roomId = _roomController.text.trim();
    if (roomId.isEmpty) {
      setState(() => _errorMessage = '请输入房间ID');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isConnected = false;
    });

    try {
      // 连接 WebSocket
      _wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _wsChannel!.stream.listen(
        (message) => _handleSignalingMessage(jsonDecode(message)),
        onError: (error) {
          setState(() => _errorMessage = '连接错误: $error');
        },
        onDone: () {
          setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      setState(() => _errorMessage = '连接失败: $e');
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> msg) {
    final id = msg['id'] as int?;

    switch (id) {
      case 1100: // Connected - 保存自己的用户ID
        final user = msg['userInfo'];
        setState(() {
          _myUserId = user['id'];
          _isConnected = true;
        });
        // 加入房间
        _joinRoom(_roomController.text.trim());
        break;

      case 1000: // JoinedGroup - 加入成功
        setState(() {
          _currentRoom = msg['group'];
          _roomMembers = (msg['members'] as List)
              .map((m) => UserInfo.fromJson(m))
              .toList();
        });
        break;

      case 1001: // UserJoinedGroup
        final user = UserInfo.fromJson(msg['userInfo']);
        setState(() {
          _roomMembers.add(user);
        });
        break;

      case 1002: // UserLeftGroup
        final userId = msg['userInfo']['id'];
        setState(() {
          _roomMembers.removeWhere((u) => u.id == userId);
        });
        break;

      case 1200: // RTCSessionDescription (offer/answer)
        _handleSessionDescription(msg);
        break;

      case 1201: // RTCICECandidate
        _handleICECandidate(msg);
        break;
    }
  }

  Future<void> _joinRoom(String roomId) async {
    final joinMsg = {
      'id': 100,
      'group': roomId,
    };
    _wsChannel?.sink.add(jsonEncode(joinMsg));
  }

  Future<void> _makeCall() async {
    final targetId = _targetUserController.text.trim();
    if (targetId.isEmpty || _myUserId == null) return;

    setState(() => _isMakingCall = true);

    try {
      // 获取本地媒体流
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
        },
      });
      _localRenderer!.srcObject = _localStream;

      // 创建 PeerConnection
      _peerConnection = await createPeerConnection(_rtcConfig);

      // 添加本地轨道
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // 监听远程轨道
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer!.srcObject = event.streams[0];
        }
      };

      // 监听 ICE 候选
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _sendICECandidate(candidate, targetId);
      };

      // 创建 Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // 发送 Offer
      _sendSessionDescription(offer, targetId, 'offer');

      setState(() {
        _isInCall = true;
        _isMakingCall = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '创建通话失败: $e';
        _isMakingCall = false;
      });
    }
  }

  void _sendSessionDescription(RTCSessionDescription sd, String targetId, String type) {
    final msg = {
      'id': 1200,
      'source': _myUserId,
      'target': targetId,
      'data': {
        'type': type,
        'sdp': sd.sdp,
      },
    };
    _wsChannel?.sink.add(jsonEncode(msg));
  }

  void _sendICECandidate(RTCIceCandidate candidate, String targetId) {
    final msg = {
      'id': 1201,
      'source': _myUserId,
      'target': targetId,
      'data': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    };
    _wsChannel?.sink.add(jsonEncode(msg));
  }

  Future<void> _handleSessionDescription(Map<String, dynamic> msg) async {
    final source = msg['source'] as String?;
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null || source == null) return;

    final type = data['type'] as String?;
    final sdp = data['sdp'] as String?;

    if (type == null || sdp == null) return;

    // 如果收到的是offer，需要回复answer
    if (type == 'offer') {
      // 获取本地媒体流
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
        },
      });
      _localRenderer!.srcObject = _localStream;

      // 创建 PeerConnection
      _peerConnection = await createPeerConnection(_rtcConfig);

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer!.srcObject = event.streams[0];
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        _sendICECandidate(candidate, source);
      };

      // 设置远程描述
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );

      // 创建 Answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _sendSessionDescription(answer, source, 'answer');

      setState(() => _isInCall = true);
    } else if (type == 'answer') {
      // 收到answer，设置远程描述
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
    }
  }

  Future<void> _handleICECandidate(Map<String, dynamic> msg) async {
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final candidate = RTCIceCandidate(
      data['candidate'] ?? '',
      data['sdpMid'] ?? '',
      data['sdpMLineIndex'] ?? 0,
    );
    await _peerConnection?.addCandidate(candidate);
  }

  void _hangUp() {
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _localRenderer?.srcObject = null;
    _remoteRenderer?.srcObject = null;
    _wsChannel?.sink.close();
    _wsChannel = null;

    setState(() {
      _isInCall = false;
      _isConnected = false;
      _currentRoom = null;
      _roomMembers = [];
      _myUserId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频通话'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.call_end),
              onPressed: _hangUp,
              color: Colors.red,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isConnected) {
      return _buildConnectView();
    }

    if (_isInCall) {
      return _buildCallView();
    }

    return _buildRoomView();
  }

  Widget _buildConnectView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _roomController,
            decoration: const InputDecoration(
              labelText: '房间ID',
              hintText: '输入房间ID加入',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
          ],
          ElevatedButton(
            onPressed: _connect,
            child: const Text('连接服务器'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomView() {
    return Column(
      children: [
        // 当前房间信息
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade100,
          child: Row(
            children: [
              const Icon(Icons.group),
              const SizedBox(width: 8),
              Text('房间: $_currentRoom'),
              const Spacer(),
              Text('我的ID: $_myUserId'),
            ],
          ),
        ),
        // 错误信息
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade100,
            child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ),
        // 发起通话
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetUserController,
                  decoration: const InputDecoration(
                    labelText: '目标用户ID',
                    hintText: '输入要呼叫的用户ID',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isMakingCall ? null : _makeCall,
                icon: const Icon(Icons.call),
                label: const Text('呼叫'),
              ),
            ],
          ),
        ),
        // 房间成员列表
        Expanded(
          child: ListView.builder(
            itemCount: _roomMembers.length,
            itemBuilder: (ctx, index) {
              final member = _roomMembers[index];
              return ListTile(
                leading: CircleAvatar(child: Text(member.username[0])),
                title: Text(member.username),
                subtitle: Text(member.id),
                trailing: member.id != _myUserId
                    ? IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () {
                          _targetUserController.text = member.id;
                          _makeCall();
                        },
                      )
                    : const Chip(label: Text('我')),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCallView() {
    return Stack(
      children: [
        // 远端视频 (全屏)
        Positioned.fill(
          child: _remoteRenderer != null
              ? RTCVideoView(_remoteRenderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Container(color: Colors.black),
        ),
        // 本地视频 (右上角小窗口)
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            width: 120,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _localRenderer != null
                  ? RTCVideoView(_localRenderer!, mirror: true)
                  : Container(color: Colors.grey),
            ),
          ),
        ),
        // 通话信息
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text('通话中...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        // 挂断按钮
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton(
              onPressed: _hangUp,
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class UserInfo {
  final String id;
  final String username;

  UserInfo({required this.id, required this.username});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] ?? '',
      username: json['name'] ?? '',
    );
  }
}
