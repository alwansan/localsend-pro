import 'package:flutter/foundation.dart';
import 'package:localsend_app/pro/transfer_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pro preferences are separate from generated SettingsState to avoid
/// changing the upstream code-generation contract for existing settings.
class ProPreferencesController extends ValueNotifier<ProTransferOptions> {
  ProPreferencesController() : super(const ProTransferOptions());

  static const _fast = 'ls_pro_accelerated_transport';
  static const _hotspot = 'ls_pro_direct_hotspot';
  static const _fiveGHz = 'ls_pro_prefer_5ghz';

  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    value = ProTransferOptions(
      acceleratedTransport: prefs.getBool(_fast) ?? true,
      preferDirectHotspot: prefs.getBool(_hotspot) ?? true,
      prefer5GHz: prefs.getBool(_fiveGHz) ?? true,
    );
  }

  Future<void> setAcceleratedTransport(bool enabled) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fast, enabled);
    value = value.copyWith(acceleratedTransport: enabled);
  }

  Future<void> setDirectHotspot(bool enabled) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hotspot, enabled);
    value = value.copyWith(preferDirectHotspot: enabled);
  }

  Future<void> setPrefer5GHz(bool enabled) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fiveGHz, enabled);
    value = value.copyWith(prefer5GHz: enabled);
  }
}

final proPreferencesController = ProPreferencesController();
