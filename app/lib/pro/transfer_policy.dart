/// Android Pro route selection (pure, deterministic and testable).
///
/// This only chooses a *proposed* route. The Android backend must verify that
/// it can actually create the network and obtain user/system consent; the
/// sender must never switch networks based solely on this result.
enum ProRadioBand { unknown, ghz24, ghz5 }

enum ProRoute { existingLan, localOnlyHotspot }

class ProTransferOptions {
  final bool acceleratedTransport;
  final bool preferDirectHotspot;
  final bool prefer5GHz;

  const ProTransferOptions({
    this.acceleratedTransport = true,
    this.preferDirectHotspot = true,
    this.prefer5GHz = true,
  });

  ProTransferOptions copyWith({bool? acceleratedTransport, bool? preferDirectHotspot, bool? prefer5GHz}) {
    return ProTransferOptions(
      acceleratedTransport: acceleratedTransport ?? this.acceleratedTransport,
      preferDirectHotspot: preferDirectHotspot ?? this.preferDirectHotspot,
      prefer5GHz: prefer5GHz ?? this.prefer5GHz,
    );
  }
}

class ProPeerCapabilities {
  /// A legacy LocalSend peer cannot negotiate Pro-specific extensions.
  final bool supportsPro;
  final bool supports5GHzStation;
  final bool supports5GHzHotspot;
  final bool canCreateLocalOnlyHotspot;
  final ProRadioBand currentWifiBand;

  const ProPeerCapabilities({
    required this.supportsPro,
    required this.supports5GHzStation,
    required this.supports5GHzHotspot,
    required this.canCreateLocalOnlyHotspot,
    required this.currentWifiBand,
  });
}

class ProRouteContext {
  /// Whether normal discovery found a working LAN link.
  final bool lanReachable;

  /// This is a measured link-health input, not an assumption about band.
  final bool lanHealthy;

  /// Whether permission and OS prerequisites for both devices are available.
  final bool hotspotAllowed;
  final bool peerAssociationAvailable;

  const ProRouteContext({
    required this.lanReachable,
    required this.lanHealthy,
    required this.hotspotAllowed,
    required this.peerAssociationAvailable,
  });
}

class ProTransferPlan {
  final ProRoute route;
  final ProRadioBand preferredBand;
  final bool hostIsSender;
  final bool requiresConsent;
  final bool acceleratedEngineAllowed;
  final String reason;

  const ProTransferPlan({
    required this.route,
    required this.preferredBand,
    required this.hostIsSender,
    required this.requiresConsent,
    required this.acceleratedEngineAllowed,
    required this.reason,
  });
}

/// Proposes the safest route with fallback. The real negotiated radio band
/// must be reported again after association, never inferred from this intent.
ProTransferPlan chooseProTransferPlan({
  required ProTransferOptions options,
  required ProPeerCapabilities sender,
  required ProPeerCapabilities receiver,
  required ProRouteContext context,
}) {
  final compatible = sender.supportsPro && receiver.supportsPro;
  final prefer5 = options.prefer5GHz;

  final lanBand = prefer5 &&
          sender.currentWifiBand == ProRadioBand.ghz5 &&
          receiver.currentWifiBand == ProRadioBand.ghz5
      ? ProRadioBand.ghz5
      : (context.lanReachable ? ProRadioBand.unknown : ProRadioBand.unknown);

  // Never disrupt a healthy LAN just to start a hotspot; 5GHz LAN works
  // even if the separate direct-hotspot preference is disabled.
  final canTryDirect = compatible &&
      options.preferDirectHotspot &&
      context.hotspotAllowed &&
      context.peerAssociationAvailable &&
      (!context.lanReachable || !context.lanHealthy);

  if (canTryDirect) {
    final hostIsSender = sender.canCreateLocalOnlyHotspot || !receiver.canCreateLocalOnlyHotspot;
    final host = hostIsSender ? sender : receiver;
    final guest = hostIsSender ? receiver : sender;
    if (host.canCreateLocalOnlyHotspot) {
      final band = prefer5 && host.supports5GHzHotspot && guest.supports5GHzStation ? ProRadioBand.ghz5 : ProRadioBand.ghz24;
      return ProTransferPlan(
        route: ProRoute.localOnlyHotspot,
        preferredBand: band,
        hostIsSender: hostIsSender,
        requiresConsent: true,
        acceleratedEngineAllowed: options.acceleratedTransport,
        reason: 'Direct link eligible; await Android approval and actual band confirmation',
      );
    }
  }

  return ProTransferPlan(
    route: ProRoute.existingLan,
    preferredBand: lanBand,
    hostIsSender: false,
    requiresConsent: false,
    acceleratedEngineAllowed: compatible && options.acceleratedTransport,
    reason: compatible ? 'Keep current LAN or fallback to standard transfer' : 'Legacy peer: use standard LocalSend',
  );
}
