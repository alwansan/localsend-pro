import 'package:localsend_isolates/model/device.dart';

/// Pick only an HTTPS channel for a discovered peer whose TLS certificate
/// fingerprint is usable for pinning. The probe is read-only; it must never
/// initiate a transfer or change Android's selected network.
HttpChannel? selectProCapabilityChannel(Device device) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(device.fingerprint)) return null;

  HttpChannel? untested;
  for (final channel in device.channels.whereType<HttpChannel>()) {
    if (!channel.https ||
        channel.host.trim().isEmpty ||
        channel.port < 1 ||
        channel.port > 65535 ||
        channel.outbound == ChannelOutbound.failed) {
      continue;
    }
    if (channel.outbound == ChannelOutbound.reachable) return channel;
    untested ??= channel;
  }
  return untested;
}
