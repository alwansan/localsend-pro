import 'package:flutter/material.dart';
import 'package:localsend_app/pro/pro_preferences.dart';
import 'package:localsend_app/pro/pro_wifi_capabilities.dart';
import 'package:localsend_app/pro/transfer_policy.dart';

/// Exposes saved policy preferences without pretending that an unfinished
/// native Wi-Fi/hotspot or resumable transport feature is already operational.
class ProPreferencesPanel extends StatefulWidget {
  const ProPreferencesPanel({super.key, this.compact = false});

  final bool compact;

  @override
  State<ProPreferencesPanel> createState() => _ProPreferencesPanelState();
}

class _ProPreferencesPanelState extends State<ProPreferencesPanel> {
  late final Future<void> _ready = proPreferencesController.initialize();
  late final Future<ProWifiSnapshot?> _radio = ProWifiCapabilities.read();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ListTile(title: Text('LocalSend Pro'), subtitle: Text('Could not load Pro settings'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListTile(title: Text('LocalSend Pro'), subtitle: Text('Loading preferences...'));
        }
        return ValueListenableBuilder<ProTransferOptions>(
          valueListenable: proPreferencesController,
          builder: (context, settings, _) => Card(
            margin: widget.compact ? const EdgeInsets.symmetric(horizontal: 15, vertical: 6) : EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.bolt),
                  title: const Text('LocalSend Pro — Android'),
                  subtitle: const Text('Experimental preferences. Automatic hotspot and resumable transport are not active yet.'),
                  dense: widget.compact,
                ),
                SwitchListTile(
                  title: const Text('Accelerated transfer'),
                  subtitle: const Text('Prefer the Pro engine when supported by both devices'),
                  value: settings.acceleratedTransport,
                  onChanged: (enabled) => proPreferencesController.setAcceleratedTransport(enabled),
                  dense: widget.compact,
                ),
                SwitchListTile(
                  title: const Text('Direct hotspot'),
                  subtitle: const Text('Prefer a direct local link when LAN is unsuitable and Android permits it'),
                  value: settings.preferDirectHotspot,
                  onChanged: (enabled) => proPreferencesController.setDirectHotspot(enabled),
                  dense: widget.compact,
                ),
                SwitchListTile(
                  title: const Text('Auto 5 GHz'),
                  subtitle: const Text('Only when both devices and the active network support it; otherwise fallback'),
                  value: settings.prefer5GHz,
                  onChanged: (enabled) => proPreferencesController.setPrefer5GHz(enabled),
                  dense: widget.compact,
                ),
                FutureBuilder<ProWifiSnapshot?>(
                  future: _radio,
                  builder: (context, radio) {
                    final wifi = radio.data;
                    if (wifi == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Current Wi-Fi: ${wifi.currentBand} GHz • 5 GHz client: ${wifi.supports5GHzStation ? "yes" : "no"} • hotspot: ${wifi.supportsLocalOnlyHotspot ? "available" : "unavailable"}. '
                        'Android determines the actual hotspot band.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
