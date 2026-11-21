import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/transfer_policy.dart';

const sender = ProPeerCapabilities(
  supportsPro: true,
  supports5GHzStation: true,
  supports5GHzHotspot: true,
  canCreateLocalOnlyHotspot: true,
  currentWifiBand: ProRadioBand.ghz5,
);
const receiver = ProPeerCapabilities(
  supportsPro: true,
  supports5GHzStation: true,
  supports5GHzHotspot: false,
  canCreateLocalOnlyHotspot: false,
  currentWifiBand: ProRadioBand.ghz5,
);

void main() {
  test('Pro feature switches are enabled by default', () {
    const options = ProTransferOptions();
    expect(options.acceleratedTransport, true);
    expect(options.preferDirectHotspot, true);
    expect(options.prefer5GHz, true);
  });

  test('healthy 5GHz router connection is kept even with hotspot preference on', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: sender,
      receiver: receiver,
      context: const ProRouteContext(lanReachable: true, lanHealthy: true, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.existingLan);
    expect(plan.preferredBand, ProRadioBand.ghz5);
    expect(plan.requiresConsent, false);
  });

  test('poor LAN and a capable host propose direct 5GHz, subject to consent', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: sender,
      receiver: receiver,
      context: const ProRouteContext(lanReachable: true, lanHealthy: false, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.localOnlyHotspot);
    expect(plan.preferredBand, ProRadioBand.ghz5);
    expect(plan.hostIsSender, true);
    expect(plan.requiresConsent, true);
  });

  test('falls back to 2.4GHz if the joining phone cannot use 5GHz', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: sender,
      receiver: const ProPeerCapabilities(
        supportsPro: true,
        supports5GHzStation: false,
        supports5GHzHotspot: false,
        canCreateLocalOnlyHotspot: false,
        currentWifiBand: ProRadioBand.unknown,
      ),
      context: const ProRouteContext(lanReachable: false, lanHealthy: false, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.localOnlyHotspot);
    expect(plan.preferredBand, ProRadioBand.ghz24);
  });

  test('5GHz LAN still works with direct hotspot disabled', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(preferDirectHotspot: false),
      sender: sender,
      receiver: receiver,
      context: const ProRouteContext(lanReachable: true, lanHealthy: true, hotspotAllowed: false, peerAssociationAvailable: false),
    );
    expect(plan.route, ProRoute.existingLan);
    expect(plan.preferredBand, ProRadioBand.ghz5);
  });

  test('existing 2.4 GHz router band is reported accurately', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: const ProPeerCapabilities(
        supportsPro: true,
        supports5GHzStation: true,
        supports5GHzHotspot: true,
        canCreateLocalOnlyHotspot: true,
        currentWifiBand: ProRadioBand.ghz24,
      ),
      receiver: const ProPeerCapabilities(
        supportsPro: true,
        supports5GHzStation: false,
        supports5GHzHotspot: false,
        canCreateLocalOnlyHotspot: false,
        currentWifiBand: ProRadioBand.ghz24,
      ),
      context: const ProRouteContext(lanReachable: true, lanHealthy: true, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.existingLan);
    expect(plan.preferredBand, ProRadioBand.ghz24);
  });

  test('receiver can host when sender cannot, selecting 2.4 GHz safely', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: const ProPeerCapabilities(
        supportsPro: true,
        supports5GHzStation: false,
        supports5GHzHotspot: false,
        canCreateLocalOnlyHotspot: false,
        currentWifiBand: ProRadioBand.unknown,
      ),
      receiver: const ProPeerCapabilities(
        supportsPro: true,
        supports5GHzStation: true,
        supports5GHzHotspot: true,
        canCreateLocalOnlyHotspot: true,
        currentWifiBand: ProRadioBand.unknown,
      ),
      context: const ProRouteContext(lanReachable: false, lanHealthy: false, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.localOnlyHotspot);
    expect(plan.hostIsSender, false);
    expect(plan.preferredBand, ProRadioBand.ghz24);
  });

  test('legacy peer remains on original transport and no Pro direct link', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: sender,
      receiver: const ProPeerCapabilities(
        supportsPro: false,
        supports5GHzStation: true,
        supports5GHzHotspot: false,
        canCreateLocalOnlyHotspot: false,
        currentWifiBand: ProRadioBand.unknown,
      ),
      context: const ProRouteContext(lanReachable: true, lanHealthy: false, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.existingLan);
    expect(plan.acceleratedEngineAllowed, false);
  });

  test('Android permissions absent means no hotspot route', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(),
      sender: sender,
      receiver: receiver,
      context: const ProRouteContext(lanReachable: false, lanHealthy: false, hotspotAllowed: false, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.unavailable);
    expect(plan.requiresConsent, false);
  });

  test('direct route disabled regardless of radio capability', () {
    final plan = chooseProTransferPlan(
      options: const ProTransferOptions(preferDirectHotspot: false, prefer5GHz: false),
      sender: sender,
      receiver: receiver,
      context: const ProRouteContext(lanReachable: false, lanHealthy: false, hotspotAllowed: true, peerAssociationAvailable: true),
    );
    expect(plan.route, ProRoute.unavailable);
  });
}
