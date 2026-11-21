import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of user-approved local-only Wi-Fi association. A successful join is
/// NOT proof that the Rust transport uses that network. Do not switch routes
/// until the peer is authenticated and sockets are network-bound and probed.
class ProAssociatedWifi {
  final String networkHandle;
  final String? localIpv4;

  const ProAssociatedWifi({required this.networkHandle, this.localIpv4});

  factory ProAssociatedWifi.fromMap(Map<String, dynamic> data) {
    if (data['connected'] != true || data['networkHandle'] is! String || (data['networkHandle'] as String).isEmpty) {
      throw const FormatException('No active Android local-only network');
    }
    return ProAssociatedWifi(
      networkHandle: data['networkHandle'] as String,
      localIpv4: data['localIpv4'] is String ? data['localIpv4'] as String : null,
    );
  }
}

class ProWifiJoin {
  static const _channel = MethodChannel('org.localsend.localsend_app/localsend');

  /// Call only after authenticated Pro capability exchange and user intent.
  /// Android presents a system approval dialog; credentials must never be
  /// written to preferences, analytics or ordinary diagnostic logs.
  static Future<ProAssociatedWifi> join({required String ssid, required String passphrase}) async {
    if (defaultTargetPlatform != TargetPlatform.android) throw UnsupportedError('Android only');
    if (ssid.isEmpty || passphrase.isEmpty) throw ArgumentError('Missing local hotspot credentials');
    final data = await _channel.invokeMapMethod<String, dynamic>('joinProLocalOnlyWifi', {
      'ssid': ssid,
      'passphrase': passphrase,
    });
    if (data == null) throw const FormatException('Empty Android Wi-Fi join response');
    return ProAssociatedWifi.fromMap(data);
  }

  static Future<bool> isConnected() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final data = await _channel.invokeMapMethod<String, dynamic>('getProWifiJoinStatus');
    return data?['connected'] == true;
  }

  static Future<void> leave() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('leaveProLocalOnlyWifi');
  }
}
