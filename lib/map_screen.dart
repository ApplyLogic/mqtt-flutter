import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  dynamic _client;
  final Set<Marker> _markers = {};
  final Completer<GoogleMapController> _controller = Completer();

  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _setupMqttClient() async {
    debugPrint('_setupMqttClient');

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    if (kIsWeb) {
      // Web-specific configuration
      _client = MqttBrowserClient.withPort('ws://localhost', 't1-sub2', 1884);
      debugPrint('Set up websocket protocol');
    } else {
      _client = MqttServerClient.withPort('ws://localhost', 't1-sub2', 1884);
      _client?.useWebSocket = true;
    }
    debugPrint('Set up websocket protocol');
    // Set up websocket protocol
    _client?.keepAlivePeriod = 20;
    _client?.onDisconnected = _onDisconnected;
    _client?.onConnected = _onConnected;
    _client?.onSubscribed = _onSubscribed;
    _client?.pongCallback = _pong;
    _client?.onSubscribeFail = _onSubscribeFail;
    _client?.onFailedConnectionAttempt = _onFailedConnectionAttempt;
    _client?.connectionMessage = connMessage;
  }

  Future<void> _connect() async {
    debugPrint('_connect');
    if (_client == null) {
      await _setupMqttClient();
      debugPrint('MQTT client setup completed');
    }
    try {
      debugPrint('MQTT client connection...');
      _client?.connect().then((value) {
        debugPrint('MQTT connection value ${value.toString()}');
      });
    } catch (e) {
      _disconnect();
    }
  }

  void _disconnect() {
    if (_client != null &&
        _client?.connectionStatus!.state != MqttConnectionState.disconnected) {
      _client?.disconnect();
    }
  }

  void _onConnected() {
    debugPrint('MQTT client connected');
    _subscribe();
  }

  void _subscribe() {
    if (_client != null &&
        _client?.connectionStatus!.state == MqttConnectionState.connected) {
      _client?.subscribe('topic/data', MqttQos.atLeastOnce);
    }

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (var msg in messages) {
        final recMess = messages[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        debugPrint('${msg.topic}: $payload');
        try {
          final Map<String, dynamic> parsedJson = jsonDecode(payload);
          final double? lat = parsedJson['lat'];
          final double? lng = parsedJson['lng'];
          if (lat != null && lng != null) {
            var point = LatLng(lat, lng);
            setState(() {
              _currentLocation = point;
              if (!kIsWeb) {
                _animateCameraToLocation(point);
              }
              _displayMarker(point);
            });
          }
        } catch (e) {
          debugPrint("error decoding $e");
        }
      }
    });
  }

  void _onDisconnected() {
    debugPrint('MQTT client disconnected');

    final connectionState = _client?.connectionStatus?.state;
    final returnCode = _client?.connectionStatus?.returnCode;
    final reasonCode = _client?.connectionStatus?.returnCode;

    // Log detailed connection information
    debugPrint('==== MQTT disconnected Details ====');
    debugPrint('Connection State: $connectionState');
    debugPrint('Return Code: $returnCode');
    debugPrint('Reason Code: $reasonCode');
    debugPrint('Using WebSocket: ${_client?.useWebSocket}');
    debugPrint('===================================');
  }

  void _onSubscribed(String topic) {
    debugPrint('Subscribed topic: $topic');
  }

  void _onSubscribeFail(String topic) {
    debugPrint('Failed to subscribe $topic');
  }

  void _onFailedConnectionAttempt(int attemptNumber) {
    debugPrint('MQTT Connection failed - attempt $attemptNumber');
  }

  void _pong() {
    debugPrint('Ping response client callback invoked');
  }

  void _disconnectMQTT() {
    _client!.disconnect();
  }

  Future<void> _animateCameraToLocation(LatLng point) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(point, 14));
  }

  void _displayMarker(LatLng point) {
    var now = DateTime.now().toIso8601String();
    if (!kIsWeb) {
      _markers.clear();
    }
    _markers.add(Marker(position: point, markerId: MarkerId('m-$now')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT Location Tracker'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? const LatLng(51.5072, 0.1276),
              zoom: 10,
            ),
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            markers: _markers,
          ),
          Visibility(
              visible: _currentLocation == null,
              child: const Center(child: CircularProgressIndicator()))
        ],
      ),
    );
  }

  @override
  void dispose() {
    _disconnectMQTT();
    super.dispose();
  }
}
