import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/pro_peer_capabilities.dart';
import 'package:localsend_isolates/model/device.dart';

final fingerprint = List.filled(64, 'A').join();

Device peer(List<DeviceChannel> channels, {String? identity}) => Device(
  signalingId: null,
  ip: '192.168.1.80',
  version: '2.2',
  port: 53317,
  https: true,
  fingerprint: identity ?? fingerprint,
  alias: 'Receiver',
  deviceModel: null,
  deviceType: DeviceType.mobile,
  download: false,
  channels: channels,
);

void main() {
  const reachable = HttpChannel(
    host: '192.168.1.80',
    port: 53317,
    https: true,
    outbound: ChannelOutbound.reachable,
  );
  const untested = HttpChannel(
    host: '192.168.1.81',
    port: 53317,
    https: true,
  );
  const failed = HttpChannel(
    host: '192.168.1.82',
    port: 53317,
    https: true,
    outbound: ChannelOutbound.failed,
  );

  test('never probes a peer without a valid pinned certificate identity', () {
    expect(selectProCapabilityChannel(peer([reachable], identity: '')), isNull);
    expect(selectProCapabilityChannel(peer([reachable], identity: 'device-token')), isNull);
  });

  test('refuses plaintext, failed channels and invalid endpoints', () {
    expect(selectProCapabilityChannel(peer([
      const HttpChannel(host: '192.168.1.1', port: 53317, https: false),
      failed,
      const HttpChannel(host: '', port: 53317, https: true),
      const HttpChannel(host: '192.168.1.1', port: 0, https: true),
    ])), isNull);
  });

  test('prefers a known reachable HTTPS route over an untested candidate', () {
    expect(selectProCapabilityChannel(peer([untested, failed, reachable])), same(reachable));
  });

  test('allows manual check on an untested HTTPS channel, never a known failed one', () {
    expect(selectProCapabilityChannel(peer([failed, untested])), same(untested));
    expect(selectProCapabilityChannel(peer([failed])), isNull);
  });

  test('supports a certificate-pinned IPv6 address', () {
    const ipv6 = HttpChannel(
      host: 'fe80::1234%3',
      port: 53317,
      https: true,
      outbound: ChannelOutbound.reachable,
    );
    expect(selectProCapabilityChannel(peer([ipv6])), same(ipv6));
  });
}
