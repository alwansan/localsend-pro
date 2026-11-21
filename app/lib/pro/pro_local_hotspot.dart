import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A hotspot reservation owned by Android. Do not log, persist or announce
/// credentials without the receiver's authenticated/consented handshake.
class ProHotspotReservationInfo {
  final String ssid;
  final String passphrase;

  const ProHotspotReservationInfo({required this.ssid, required this.passphrase});

  factory ProHotspotReservationInfo.fromMap(Map<String, dynamic> data) {
    final ssid = data['ssid'];
    final passphrase = data['passphrase'];
    if (ssid is! String || ssid.isEmpty || passphrase is! String || passphrase.isEmpty) {
      throw const FormatException('Android did not return valid local hotspot credentials');
    }
    return ProHotspotReservationInfo(ssid: ssid, passphrase: passphrase);
  }
}

class ProLocalHotspot {
  static const _channel = MethodChannel('org.localsend.localsend_app/localsend');

  /// Only call after actual intent from the user/transfer coordinator. Android
  /// may present an OS permission prompt. A started hotspot does not itself
  /// connect a receiving device or determine the actual radio band.
  static Future<ProHotspotReservationInfo> start() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Local-only hotspot is available only on Android');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>('startProLocalOnlyHotspot');
    if (data == null) throw const FormatException('No local-only hotspot response');
    return ProHotspotReservationInfo.fromMap(data);
  }

  static Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('stopProLocalOnlyHotspot');
  }
}
