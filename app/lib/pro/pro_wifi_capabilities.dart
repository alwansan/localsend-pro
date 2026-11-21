import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Read-only snapshot of the Android device's current Wi-Fi state.
/// The actual hotspot band cannot be guaranteed until Android starts it.
class ProWifiSnapshot {
  final bool supports5GHzStation;
  final bool supportsLocalOnlyHotspot;
  final bool supportsWifiDirect;
  final int? currentFrequencyMHz;
  final String currentBand;

  const ProWifiSnapshot({
    required this.supports5GHzStation,
    required this.supportsLocalOnlyHotspot,
    required this.supportsWifiDirect,
    required this.currentFrequencyMHz,
    required this.currentBand,
  });

  factory ProWifiSnapshot.fromMap(Map<String, dynamic> data) {
    return ProWifiSnapshot(
      supports5GHzStation: data['supports5GHzStation'] == true,
      supportsLocalOnlyHotspot: data['supportsLocalOnlyHotspot'] == true,
      supportsWifiDirect: data['supportsWifiDirect'] == true,
      currentFrequencyMHz: data['currentFrequencyMHz'] is int ? data['currentFrequencyMHz'] as int : null,
      currentBand: data['currentBand'] is String ? data['currentBand'] as String : 'unknown',
    );
  }
}

class ProWifiCapabilities {
  static const _channel = MethodChannel('org.localsend.localsend_app/localsend');

  static Future<ProWifiSnapshot?> read() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final values = await _channel.invokeMapMethod<String, dynamic>('getProWifiCapabilities');
      if (values == null) return null;
      return ProWifiSnapshot.fromMap(values);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
