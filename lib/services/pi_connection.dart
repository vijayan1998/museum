import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Connection lifecycle states for the link to the Raspberry Pi.
enum PiStatus { disconnected, searching, connecting, connected, error }

/// A network-free link to a Raspberry Pi over the phone's **mobile hotspot**.
///
/// Topology (no router, no internet):
///
///   ┌──────────────────────────┐         ┌────────────────────┐
///   │ Phone / tablet           │  Wi-Fi  │ Raspberry Pi        │
///   │  • shares mobile hotspot │◀───────▶│  joins the hotspot  │
///   │  • runs the Museum app   │  (LAN)  │  runs museum_server │
///   └──────────────────────────┘         └────────────────────┘
///
/// Because the hotspot hands the Pi a **dynamic** IP (Android ≈ 192.168.43.x,
/// iOS ≈ 172.20.10.x), the app cannot hard-code the address — it [discover]s
/// the Pi by probing the hotspot subnet for a host that answers on [port] with
/// the museum handshake, then holds a TCP socket open to it.
///
/// Messages are newline-delimited JSON in both directions:
///
///   app -> pi : {"cmd": "select_stage", "stage": 1}
///   pi  -> app: {"type": "status", "playing": true}
///
/// It is a [ChangeNotifier] so widgets rebuild via a plain [ListenableBuilder]
/// — no extra state-management package required.
class PiConnection extends ChangeNotifier {
  PiConnection({this.port = defaultPort});

  static const int defaultPort = 8000;

  /// The handshake the Pi sends on connect so we know it's *our* device and not
  /// some other service that happens to have the port open.
  static const String deviceId = 'museum-pi';

  /// A shared instance so the whole app talks to one Pi link.
  static final PiConnection instance = PiConnection();

  int port;

  /// The Pi's address, once found. Tried first on the next (re)connect so we
  /// skip the scan when the IP hasn't changed.
  String? host;

  Socket? _socket;
  StreamSubscription<String>? _lineSub;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  PiStatus _status = PiStatus.disconnected;
  PiStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  bool get isConnected => _status == PiStatus.connected;

  /// Broadcast stream of decoded JSON messages received from the Pi.
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  Map<String, dynamic>? _lastMessage;
  Map<String, dynamic>? get lastMessage => _lastMessage;

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Find the Pi on the hotspot subnet and connect to it. Tries the last known
  /// address first (instant), then scans if that fails. This is the entry point
  /// the UI should call.
  Future<void> discover({int? port}) async {
    if (port != null) this.port = port;
    if (_status == PiStatus.searching ||
        _status == PiStatus.connecting ||
        _status == PiStatus.connected) {
      return;
    }
    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    // Fast path: the Pi is probably still where we last found it.
    if (host != null) {
      _setStatus(PiStatus.connecting);
      if (await _probe(host!, this.port)) {
        return _open(host!);
      }
    }

    _setStatus(PiStatus.searching);
    final candidates = await _candidateHosts();
    final found = await _scan(candidates, this.port);
    if (_manualDisconnect) return;
    if (found != null) {
      host = found;
      return _open(found);
    }
    _lastError =
        'No Pi found on your hotspot. Make sure it\'s powered on and has '
        'joined this phone\'s hotspot, then retry.';
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

  /// Open a short-lived socket and check the host answers with our handshake.
  /// Only a real museum Pi (right [deviceId]) counts as a match.
  Future<bool> _probe(String host, int port) async {
    Socket? probe;
    try {
      probe = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      final completer = Completer<bool>();
      final timer = Timer(const Duration(milliseconds: 900), () {
        if (!completer.isCompleted) completer.complete(false);
      });
      final sub = probe
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (completer.isCompleted) return;
              try {
                final m = jsonDecode(line.trim());
                completer.complete(m is Map && m['device'] == deviceId);
              } catch (_) {
                completer.complete(false);
              }
            },
            onError: (_) {
              if (!completer.isCompleted) completer.complete(false);
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete(false);
            },
            cancelOnError: true,
          );
      final ok = await completer.future;
      timer.cancel();
      await sub.cancel();
      return ok;
    } catch (_) {
      return false;
    } finally {
      probe?.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Connect directly to a known [host] (e.g. from a manual settings field),
  /// skipping discovery.
  Future<void> connect({required String host, int? port}) async {
    if (port != null) this.port = port;
    this.host = host;
    if (_status == PiStatus.connecting || _status == PiStatus.connected) return;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _setStatus(PiStatus.connecting);
    await _open(host);
  }

  /// Open the long-lived managed socket to [host].
  Future<void> _open(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 6),
      );
      _socket = socket;
      this.host = host;
      _lastError = null;
      _setStatus(PiStatus.connected);

      _lineSub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onError: (Object e) => _handleDrop('socket error: $e'),
            onDone: () => _handleDrop('connection closed by Pi'),
            cancelOnError: true,
          );
    } catch (e) {
      _lastError = _friendlyError(e, host);
      _setStatus(PiStatus.error);
      _scheduleReconnect();
    }
  }

  /// Send a command map to the Pi as one JSON line. Returns `false` if the link
  /// is down.
  bool send(Map<String, dynamic> command) {
    final socket = _socket;
    if (socket == null || _status != PiStatus.connected) return false;
    try {
      socket.write('${jsonEncode(command)}\n');
      return true;
    } catch (e) {
      _handleDrop('send failed: $e');
      return false;
    }
  }

  /// Convenience helper for the common "run this command" shape.
  bool sendCommand(String cmd, [Map<String, dynamic> extra = const {}]) =>
      send({'cmd': cmd, ...extra});

  /// Close the link on purpose and stop auto-reconnecting.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await _teardownSocket();
    _setStatus(PiStatus.disconnected);
  }

  void _handleLine(String line) {
    final text = line.trim();
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _lastMessage = decoded;
        _incoming.add(decoded);
        notifyListeners();
      }
    } catch (_) {
      // Ignore malformed lines rather than tearing down the link.
    }
  }

  void _handleDrop(String reason) {
    if (_manualDisconnect) return;
    _lastError = reason;
    _teardownSocket();
    _setStatus(PiStatus.error);
    _scheduleReconnect();
  }

  Future<void> _teardownSocket() async {
    await _lineSub?.cancel();
    _lineSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket?.destroy();
    _socket = null;
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
    if (e is SocketException) {
      return 'Can\'t reach the Pi at $host:$port. Is it still on your hotspot?';
    }
    if (e is TimeoutException) {
      return 'Timed out connecting to $host:$port.';
    }
    return e.toString();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _teardownSocket();
    _incoming.close();
    super.dispose();
  }
}
