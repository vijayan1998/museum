import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Connection lifecycle states for the link to the Raspberry Pi.
enum PiStatus { disconnected, searching, connecting, connected, error }

/// A network-free MQTT link to a Raspberry Pi over the phone's **mobile
/// hotspot**, built on the `mqtt_client` package.
///
/// Topology (no router, no internet):
///
///   ┌──────────────────────────┐         ┌──────────────────────────┐
///   │ Phone / tablet           │  Wi-Fi  │ Raspberry Pi             │
///   │  • shares mobile hotspot │◀───────▶│  joins the hotspot       │
///   │  • runs the Museum app   │  (LAN)  │  runs Mosquitto (broker) │
///   │    = MQTT client         │         │  + museum_mqtt.py        │
///   └──────────────────────────┘         └──────────────────────────┘
///
/// The **broker runs on the Pi**. The app publishes commands and subscribes to
/// status; a small Python subscriber on the Pi drives the hardware.
///
///   app -> broker : topic "museum/command"  {"cmd":"select_stage","stage":1}
///   pi  -> broker : topic "museum/status"   {"playing":true}
///   pi  -> broker : topic "museum/announce" {"device":"museum-pi"} (retained)
///
/// Because the hotspot hands the Pi a **dynamic** IP (Android ≈ 192.168.43.x,
/// iOS ≈ 172.20.10.x), the app can't hard-code the broker address — it
/// [discover]s it by probing the hotspot subnet for an open MQTT port, then
/// connects there.
///
/// It is a [ChangeNotifier] so widgets rebuild via a plain [ListenableBuilder].
class PiConnection extends ChangeNotifier {
  PiConnection({this.port = defaultPort});

  static const int defaultPort = 1883; // Mosquitto default

  // MQTT topics shared with the Pi (see museum_mqtt.py).
  static const String commandTopic = 'museum/command';
  static const String statusTopic = 'museum/status';
  static const String announceTopic = 'museum/announce';

  /// Identifies our device in the retained announce message.
  static const String deviceId = 'museum-pi';

  /// A shared instance so the whole app talks to one Pi link.
  static final PiConnection instance = PiConnection();

  int port;

  /// The broker's address, once found. Tried first on the next (re)connect so
  /// we skip the scan when the IP hasn't changed.
  String? host;

  MqttServerClient? _client;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  PiStatus _status = PiStatus.disconnected;
  PiStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  bool get isConnected => _status == PiStatus.connected;

  /// Broadcast stream of decoded messages, tagged with the topic they arrived
  /// on (e.g. `museum/status`).
  final _incoming = StreamController<({String topic, Map<String, dynamic> data})>.broadcast();
  Stream<({String topic, Map<String, dynamic> data})> get messages =>
      _incoming.stream;

  Map<String, dynamic>? _lastStatus;
  Map<String, dynamic>? get lastStatus => _lastStatus;

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Find the Pi's MQTT broker on the hotspot subnet and connect. Tries the last
  /// known address first (instant), then scans. This is the UI entry point.
  Future<void> discover({int? port}) async {
    if (port != null) this.port = port;
    if (_status == PiStatus.searching ||
        _status == PiStatus.connecting ||
        _status == PiStatus.connected) {
      return;
    }
    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    // Fast path: the broker is probably still where we last found it.
    if (host != null && await _probe(host!, this.port)) {
      return _connectBroker(host!);
    }

    _setStatus(PiStatus.searching);
    final candidates = await _candidateHosts();
    final found = await _scan(candidates, this.port);
    if (_manualDisconnect) return;
    if (found != null) {
      return _connectBroker(found);
    }
    _lastError =
        'No MQTT broker found on your hotspot. Make sure the Pi is powered on, '
        'joined to this phone\'s hotspot, and running Mosquitto, then retry.';
    _setStatus(PiStatus.error);
    _scheduleReconnect();
  }

  /// Every host on each private /24 this device is attached to (the hotspot
  /// interface), minus our own addresses.
  Future<List<String>> _candidateHosts() async {
    final own = <String>{};
    final hosts = <String>{};
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        own.add(addr.address);
        final parts = addr.address.split('.');
        if (parts.length != 4 || !_isPrivateV4(parts)) continue;
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var i = 1; i < 255; i++) {
          hosts.add('$prefix.$i');
        }
      }
    }
    return hosts.where((h) => !own.contains(h)).toList();
  }

  /// Only scan RFC-1918 space so we never hammer a real network by accident.
  /// Covers Android (192.168.43.x) and iOS (172.20.10.x) hotspot ranges.
  bool _isPrivateV4(List<String> parts) {
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  /// Probe hosts in batches so a whole /24 resolves in a few seconds.
  Future<String?> _scan(List<String> hosts, int port) async {
    const batchSize = 40;
    for (var i = 0; i < hosts.length; i += batchSize) {
      if (_manualDisconnect) return null;
      final batch = hosts.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((h) => _probe(h, port).then((ok) => ok ? h : null)),
      );
      for (final r in results) {
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Cheap reachability check: is the MQTT port open on this host?
  Future<bool> _probe(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // MQTT connection
  // ---------------------------------------------------------------------------

  /// Connect directly to a known broker [host] (e.g. from a manual settings
  /// field), skipping discovery.
  Future<void> connect({required String host, int? port}) async {
    if (port != null) this.port = port;
    if (_status == PiStatus.connecting || _status == PiStatus.connected) return;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    await _connectBroker(host);
  }

  Future<void> _connectBroker(String host) async {
    _setStatus(PiStatus.connecting);
    // A unique-ish client id so several tablets don't clash on the broker.
    final clientId =
        'museum_app_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final client = MqttServerClient.withPort(host, clientId, port)
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 4000
      ..autoReconnect = false
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..connectionMessage = (MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean());
    _client = client;
    this.host = host;

    try {
      await client.connect();
    } catch (e) {
      _lastError = _friendlyError(e, host);
      client.disconnect();
      _client = null;
      _setStatus(PiStatus.error);
      _scheduleReconnect();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _lastError = 'Broker at $host:$port refused the connection.';
      client.disconnect();
      _client = null;
      _setStatus(PiStatus.error);
      _scheduleReconnect();
      return;
    }

    // Listen for anything published on the topics we care about.
    client.updates?.listen(_onData);
    client.subscribe(statusTopic, MqttQos.atLeastOnce);
    client.subscribe(announceTopic, MqttQos.atLeastOnce);

    _lastError = null;
    _setStatus(PiStatus.connected);
  }

  void _onData(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      ).trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          if (event.topic == statusTopic) _lastStatus = decoded;
          _incoming.add((topic: event.topic, data: decoded));
          notifyListeners();
        }
      } catch (_) {
        // Ignore non-JSON payloads.
      }
    }
  }

  /// Publish a raw JSON map to the command topic. Returns `false` if the link is
  /// down.
  bool publish(Map<String, dynamic> command) {
    final client = _client;
    if (client == null || _status != PiStatus.connected) return false;
    try {
      final builder = MqttClientPayloadBuilder()..addString(jsonEncode(command));
      client.publishMessage(
        commandTopic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      return true;
    } catch (e) {
      _handleDrop('publish failed: $e');
      return false;
    }
  }

  /// Convenience helper for the common "run this command" shape.
  bool sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) =>
      publish({'cmd': cmd, ...extra});

  /// Close the link on purpose and stop auto-reconnecting.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _client = null;
    _setStatus(PiStatus.disconnected);
  }

  void _onConnected() {
    // State is finalised in _connectBroker once subscriptions are set up.
  }

  void _onDisconnected() {
    if (_manualDisconnect) return;
    _handleDrop('broker connection lost');
  }

  void _handleDrop(String reason) {
    if (_manualDisconnect) return;
    _lastError = reason;
    _client?.disconnect();
    _client = null;
    if (_status != PiStatus.error) _setStatus(PiStatus.error);
    _scheduleReconnect();
  }

  /// After a drop, re-run discovery (the Pi may have been handed a new IP when
  /// it rejoined the hotspot). [discover] tries the last address first, so this
  /// is cheap when nothing changed.
  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), discover);
  }

  void _setStatus(PiStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  String _friendlyError(Object e, String host) {
    if (e is SocketException || e is NoConnectionException) {
      return 'Can\'t reach the broker at $host:$port. Is the Pi still on your '
          'hotspot with Mosquitto running?';
    }
    return e.toString();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _incoming.close();
    super.dispose();
  }
}
