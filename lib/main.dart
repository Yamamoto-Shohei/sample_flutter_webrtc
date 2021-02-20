import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'src/environments.dart';
import './src/webrtc_unit.dart';

JsonEncoder _encoder = JsonEncoder();
JsonDecoder _decoder = JsonDecoder();

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

class WebRTCStatus {
  bool isUserName = false;
  bool isCall = false;
  bool isReceive = false;
  String myId = '';
  String myUserName = '';
}

class _WebRTCPageState extends State<WebRTCPage> {
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  ConnectWebRTC _connectWebRTC = ConnectWebRTC();
  WebRTCStatus _status = WebRTCStatus();
  List<dynamic> _users = [];
  StreamStateCallback _onLocalStream;
  WebSocketChannel _channel;

  @override
  void initState() {
    _onLocalStream = ((_, stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    });
    initRenderers();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _connectWebRTC.onAddRemoteStream = ((_, stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    });

    _connectWebRTC.onRemoveRemoteStream = ((_, stream) {
      setState(() {
        _remoteRenderer.srcObject = null;
      });
    });

    _channel = IOWebSocketChannel.connect(Uri.parse(Environments.WsServer));
    _channel.stream.listen((message) async {
      Map messageMap = _decoder.convert(message);
      print(messageMap);
      if (messageMap.containsKey('myId')) {
        _status.myId = messageMap['myId'];
      }
      if (messageMap.containsKey('users')) {
        setState(() {
          _users = messageMap['users']
              .where((element) => element['id'] != _status.myId)
              .toList();
        });
      }
      if (messageMap.containsKey('offer')) {
        MediaStream stream = await _createStream();
        _onLocalStream?.call(null, stream);
        Map offer = messageMap['offer'];
        _connectWebRTC.receiveOffer(_status.myId, messageMap['requestId'],
            stream, _channel, offer['sdp'], offer['type']);
        setState(() {
          _status.isReceive = true;
        });
      }
      if (messageMap.containsKey('answer')) {
        Map answer = messageMap['answer'];
        _connectWebRTC.returnAnswer(answer['sdp'], answer['type']);
      }
      if (messageMap.containsKey('candidate')) {
        Map candidate = messageMap['candidate'];
        _connectWebRTC.setCandidate(
            _status.myId,
            messageMap['requestId'],
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex']);
      }
      if (messageMap.containsKey('disconnect')) {
        _disconnect(true);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void _handleUsername(String e) {
    setState(() {
      _status.myUserName = e;
    });
  }

  void _setUsername() async {
    Map sendUserName = {'setUsername': _status.myUserName};
    print(sendUserName);
    _channel.sink.add(_encoder.convert(sendUserName));
    _status.isUserName = true;
  }

  Future<MediaStream> _createStream() async {
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

  void _onCall(id) async {
    MediaStream stream = await _createStream();
    _onLocalStream?.call(null, stream);
    _connectWebRTC.invite(_status.myId, id, stream, _channel);
    setState(() {
      _status.isCall = true;
    });
  }

  void _disconnect(bool isByeReceive) async {
    await _connectWebRTC.disconnect(isByeReceive);
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _localRenderer.initialize();
    _remoteRenderer.initialize();
    setState(() {
      _status.isCall = false;
      _status.isReceive = false;
    });
    _connectWebRTC = ConnectWebRTC();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video conference app'),
      ),
      body: !_status.isUserName
          ? TextFormField(
              decoration: const InputDecoration(
                icon: Icon(Icons.account_box),
                hintText: 'ユーザ名を入力してください',
                labelText: 'user name',
              ),
              onChanged: _handleUsername,
              validator: (String value) {
                return null;
              })
          : OrientationBuilder(builder: (context, orientation) {
              return Container(
                child: Stack(children: <Widget>[
                  Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 0.0,
                      bottom: 0.0,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        child: _remoteRenderer.srcObject == null
                            ? _status.isCall || _status.isReceive
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      CircularProgressIndicator(),
                                    ],
                                  )
                                : Container(
                                    child: _users.length > 0
                                        ? GridView.count(
                                            crossAxisCount: 2,
                                            mainAxisSpacing: 5,
                                            crossAxisSpacing: 5,
                                            childAspectRatio: 2.5,
                                            padding: EdgeInsets.all(16.0),
                                            children: <Widget>[
                                              ..._users.map((element) =>
                                                  ElevatedButton.icon(
                                                    icon: const Icon(
                                                      Icons.tag_faces,
                                                      color: Colors.white,
                                                    ),
                                                    label: Text(
                                                        element['username']),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      primary: Colors.green,
                                                      onPrimary: Colors.white,
                                                    ),
                                                    onPressed: () =>
                                                        _onCall(element['id']),
                                                  ))
                                            ],
                                          )
                                        : Text('通話できる人がいません。'),
                                  )
                            : RTCVideoView(_remoteRenderer),
                        decoration: BoxDecoration(color: Colors.black54),
                      )),
                  Positioned(
                    left: 20.0,
                    top: 20.0,
                    child: _localRenderer.srcObject != null
                        ? Container(
                            width: orientation == Orientation.portrait
                                ? 90.0
                                : 120.0,
                            height: orientation == Orientation.portrait
                                ? 120.0
                                : 90.0,
                            child: RTCVideoView(_localRenderer, mirror: true),
                            decoration: BoxDecoration(color: Colors.black54),
                          )
                        : Container(),
                  ),
                ]),
              );
            }),
      floatingActionButton: _status.myUserName != '' && !_status.isUserName
          ? FloatingActionButton(
              onPressed: _setUsername,
              tooltip: 'Camera',
              child: Icon(Icons.camera),
            )
          : _remoteRenderer.srcObject != null
              ? FloatingActionButton(
                  onPressed: () => _disconnect(false),
                  tooltip: 'disconnect',
                  backgroundColor: Colors.pink,
                  child: Icon(Icons.call_end),
                )
              : Container(),
    );
  }
}
