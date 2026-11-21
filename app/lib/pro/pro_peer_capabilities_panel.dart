import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/pro/pro_peer_capabilities.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:refena_flutter/refena_flutter.dart';

/// Manual, read-only peer capability check. It never attempts a hotspot join,
/// upgrades an active transfer, or sends secrets over discovery channels.
class ProPeerCapabilitiesPanel extends StatefulWidget {
  const ProPeerCapabilitiesPanel({super.key, required this.device});

  final Device device;

  @override
  State<ProPeerCapabilitiesPanel> createState() => _ProPeerCapabilitiesPanelState();
}

class _ProPeerCapabilitiesPanelState extends State<ProPeerCapabilitiesPanel> with Refena {
  bool _checking = false;
  String? _report;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant ProPeerCapabilitiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device != widget.device) {
      _generation++;
      _checking = false;
      _report = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _check() async {
    final channel = selectProCapabilityChannel(widget.device);
    if (_checking || channel == null) return;
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _report = null;
    });
    try {
      final capabilities = await ref
          .read(httpProvider)
          .pinnedTo(widget.device.fingerprint)
          .proCapabilities(
            protocol: rust_model.ProtocolType.https,
            ip: channel.host,
            port: channel.port,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (capabilities == null) {
          _report = 'No verified Pro advertisement. Standard LocalSend remains available.';
        } else {
          final resume = capabilities.resumableUpload ? 'advertised' : 'not available';
          final hotspot = capabilities.hotspotCoordination ? 'advertised' : 'not available';
          final routed = capabilities.networkBoundUpload ? 'advertised' : 'not available';
          _report =
              'Verified Pro capability schema ${capabilities.schemaVersion} over pinned HTTPS. '
              'Resume: $resume; direct hotspot: $hotspot; network-bound upload: $routed. '
              'This is a diagnostic check only; standard transfers are unchanged.';
        }
        _checking = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _checking = false;
        _report = 'Could not authenticate or reach this peer for a Pro check. Standard LocalSend is unchanged.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return const SizedBox.shrink();
    final channel = selectProCapabilityChannel(widget.device);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: const Text('LocalSend Pro — peer compatibility'),
        subtitle: Text(
          _report ??
              (channel == null
                  ? 'No eligible HTTPS channel with a certificate fingerprint.'
                  : 'Manual encrypted capability check; does not change the transfer route.'),
        ),
        trailing: _checking
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton(
                onPressed: channel == null ? null : _check,
                child: const Text('Check'),
              ),
      ),
    );
  }
}
