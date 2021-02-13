import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:io';

typedef void StreamStateCallback(Session session, MediaStream stream);

class Session {
  Session({this.sid, this.pid});
  String pid;
  String sid;
  RTCPeerConnection pc;
  RTCDataChannel dc;
  List<RTCIceCandidate> remoteCandidates = [];
}

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video conference app',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: WebRTCPage(),
    );
  }
}

class WebRTCPage extends StatefulWidget {
  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _inView = false;
  StreamStateCallback _onLocalStream;

  @override
  void initState() {
    _onLocalStream = ((_, stream) {
      _localRenderer.srcObject = stream;
      setState(() {
        _inView = !_inView;
      });
    });
    initRenderers();
  }

  initRenderers() async {
    await _localRenderer.initialize();
  }

  @override
  void dispose() {
    super.dispose();
    _localRenderer.srcObject = null;
    _localRenderer.dispose();
  }

  Future<MediaStream> createStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        ...WebRTC.platformIsDesktop ? {} : {'facingMode': 'user'},
        'optional': [],
      }
    };

    MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      print(e.toString());
    }
    return stream;
  }

  @override
  Widget build(BuildContext context) {
    void _createVideo() async {
      _localRenderer.srcObject = null;
      MediaStream stream = await createStream();
      _onLocalStream?.call(null, stream);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Video conference app'),
      ),
      body: _localRenderer.srcObject != null
          ? RTCVideoView(_localRenderer, mirror: true)
          : Text('Videoを開始してください。'),
      floatingActionButton: FloatingActionButton(
        onPressed: _createVideo,
        tooltip: 'Camera',
        child: Icon(Icons.camera),
      ),
    );
  }
}
