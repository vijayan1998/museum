import 'package:flutter/material.dart';

import '../services/pi_connection.dart';
import '../songplayscreen.dart'
    show kAccent, kBackground, kDarkShadow, kLightShadow, kText;

/// A raised neumorphic chip that shows the live MQTT link state to the
/// Raspberry Pi and lets the visitor search/retry or disconnect with a tap.
///
/// Drop it anywhere (e.g. the home-screen header) — it listens to the shared
/// [PiConnection.instance] and rebuilds on every state change.
class PiStatusChip extends StatelessWidget {
  const PiStatusChip({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    final pi = PiConnection.instance;
    return ListenableBuilder(
      listenable: pi,
      builder: (context, _) {
        final busy =
            pi.status == PiStatus.searching || pi.status == PiStatus.connecting;
        final visuals = _visualsFor(pi.status);
        return GestureDetector(
          onTap: () => _onTap(context, pi),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kBackground,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: kDarkShadow,
                  offset: Offset(5, 5),
                  blurRadius: 10,
                ),
                BoxShadow(
                  color: kLightShadow,
                  offset: Offset(-5, -5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: busy
                ? SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(kAccent),
                    ),
                  )
                : Icon(visuals.icon, color: visuals.color, size: size * 0.46),
          ),
        );
      },
    );
  }

  ({IconData icon, Color color}) _visualsFor(PiStatus status) {
    switch (status) {
      case PiStatus.connected:
        return (icon: Icons.wifi_tethering, color: const Color(0xFF2FBF71));
      case PiStatus.searching:
      case PiStatus.connecting:
        return (icon: Icons.wifi_tethering, color: kAccent);
      case PiStatus.error:
        return (
          icon: Icons.wifi_tethering_error,
          color: const Color(0xFFE0685A),
        );
      case PiStatus.disconnected:
        return (
          icon: Icons.wifi_tethering_off,
          color: kText.withValues(alpha: 0.5),
        );
    }
  }

  void _onTap(BuildContext context, PiConnection pi) {
    if (pi.status == PiStatus.connected) {
      _showSheet(context, pi);
    } else {
      // Scan the hotspot for the Pi's MQTT broker and connect.
      pi.discover();
    }
  }

  /// A small neumorphic sheet showing link details and a disconnect action.
  void _showSheet(BuildContext context, PiConnection pi) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Raspberry Pi (MQTT)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Broker on your hotspot at ${pi.host}:${pi.port}',
                  style: TextStyle(color: kText.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      pi.disconnect();
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.link_off, color: Color(0xFFE0685A)),
                    label: const Text(
                      'Disconnect',
                      style: TextStyle(color: Color(0xFFE0685A)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
