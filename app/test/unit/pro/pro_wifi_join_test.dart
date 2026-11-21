import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/pro_wifi_join.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.localsend.localsend_app/localsend');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Android join passes credentials transiently and parses network handle', () async {
    String? requestedSsid;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'joinProLocalOnlyWifi');
      requestedSsid = (call.arguments as Map)['ssid'] as String?;
      expect((call.arguments as Map)['passphrase'], '12345678');
      return <String, dynamic>{'connected': true, 'networkHandle': '777', 'localIpv4': '192.168.43.12'};
    });

    final network = await ProWifiJoin.join(ssid: 'ProLocal', passphrase: '12345678');
    expect(requestedSsid, 'ProLocal');
    expect(network.networkHandle, '777');
    expect(network.localIpv4, '192.168.43.12');
  });

  test('join rejects missing or invalid network response', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => <String, dynamic>{'connected': false});
    await expectLater(ProWifiJoin.join(ssid: 'ProLocal', passphrase: '12345678'), throwsFormatException);
    await expectLater(ProWifiJoin.join(ssid: '', passphrase: '12345678'), throwsArgumentError);
  });

  test('association status and explicit leave call the native bridge', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'getProWifiJoinStatus' ? <String, dynamic>{'connected': true} : null;
    });
    expect(await ProWifiJoin.isConnected(), true);
    await ProWifiJoin.leave();
    expect(calls, ['getProWifiJoinStatus', 'leaveProLocalOnlyWifi']);
  });
}
