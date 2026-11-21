import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/pro_receiver_session_gate.dart';
import 'package:localsend_app/pro/resumable_chunk_ledger.dart';
import 'package:localsend_app/pro/resumable_file_store.dart';

String digest(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory directory;
  const sessionId = 'accepted-private-session';
  const fileId = 'file-1';
  final peer = List.filled(64, 'A').join();
  final otherPeer = List.filled(64, 'B').join();
  const token = 'secure-private-file-token-0123456789ABCDEF';
  const otherToken = 'another-private-file-token-0123456789ABCDEF';
  final payload = <int>[3, 8, 13, 21, 34, 55];

  Future<ProResumableFileStore> open() => ProResumableFileStore.open(
    directory: directory,
    sessionId: sessionId,
    fileId: fileId,
    expectedSize: payload.length,
    expectedSha256Hex: digest(payload),
    chunkLimit: 4,
  );

  ProReceiverSessionGate gate(ProResumableFileStore store) => ProReceiverSessionGate(
    store: store,
    verifiedPeerFingerprint: peer,
    fileToken: token,
  );

  ProVerifiedResumeStatus? status(ProReceiverSessionGate receiver, {
    String? peerFingerprint,
    String? requestToken,
    String? requestSession,
    String? requestFile,
    String? requestHash,
  }) => receiver.verifiedStatus(
    presentedPeerFingerprint: peerFingerprint ?? peer,
    sessionId: requestSession ?? sessionId,
    fileId: requestFile ?? fileId,
    expectedSha256Hex: requestHash ?? digest(payload),
    fileToken: requestToken ?? token,
  );

  Future<ProPersistOutcome?> put(ProReceiverSessionGate receiver, int offset, List<int> bytes, {
    String? peerFingerprint,
    String? requestToken,
    String? requestSession,
  }) => receiver.appendAuthorized(
    presentedPeerFingerprint: peerFingerprint ?? peer,
    sessionId: requestSession ?? sessionId,
    fileId: fileId,
    expectedSha256Hex: digest(payload),
    fileToken: requestToken ?? token,
    offset: offset,
    bytes: Uint8List.fromList(bytes),
    chunkSha256Hex: digest(bytes),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pro-receiver-auth-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('authorized status starts at zero and never includes access secret', () async {
    final store = await open();
    final result = status(gate(store));
    expect(result, isNotNull);
    expect(result!.sessionId, sessionId);
    expect(result.fileId, fileId);
    expect(result.confirmedOffset, 0);
    expect(result.expectedSize, payload.length);
    expect(result.complete, false);
    expect(result.toString().contains(token), false);
    store.close();
  });

  test('wrong TLS identity or file token gives no status and no ACK', () async {
    final store = await open();
    final receiver = gate(store);
    expect(status(receiver, peerFingerprint: otherPeer), isNull);
    expect(status(receiver, requestToken: otherToken), isNull);
    expect(await put(receiver, 0, payload.sublist(0, 4), peerFingerprint: otherPeer), isNull);
    expect(await put(receiver, 0, payload.sublist(0, 4), requestToken: otherToken), isNull);
    expect(store.confirmedOffset, 0);
    store.close();
  });

  test('session, file ID and full digest substitution are rejected', () async {
    final store = await open();
    final receiver = gate(store);
    expect(status(receiver, requestSession: 'other-session'), isNull);
    expect(status(receiver, requestFile: 'other-file'), isNull);
    expect(status(receiver, requestHash: digest([9, 9, 9])), isNull);
    expect(await put(receiver, 0, payload.sublist(0, 4), requestSession: 'other-session'), isNull);
    expect(store.confirmedOffset, 0);
    store.close();
  });

  test('receiver status reflects only committed bytes and survives replay', () async {
    final initial = await open();
    final first = gate(initial);
    final persisted = await put(first, 0, payload.sublist(0, 4));
    expect(persisted?.verdict, ProChunkVerdict.staged);
    expect(persisted?.confirmedOffset, 4);
    expect(status(first)?.confirmedOffset, 4);
    initial.close();
    final reopened = await open();
    final second = gate(reopened);
    expect(status(second)?.confirmedOffset, 4);
    expect((await put(second, 0, payload.sublist(0, 4)))?.verdict, ProChunkVerdict.duplicate);
    expect((await put(second, 4, payload.sublist(4)))?.confirmedOffset, 6);
    expect(await reopened.verifyComplete(), true);
    expect(status(second)?.complete, true);
    reopened.close();
  });

  test('a closed receiver cannot advertise progress', () async {
    final store = await open();
    final receiver = gate(store);
    store.close();
    expect(status(receiver), isNull);
  });

  test('rejects weak file tokens and malformed certificate fingerprints', () async {
    final store = await open();
    expect(() => ProReceiverSessionGate(store: store, verifiedPeerFingerprint: 'bad', fileToken: token), throwsArgumentError);
    expect(() => ProReceiverSessionGate(store: store, verifiedPeerFingerprint: peer, fileToken: 'weak'), throwsArgumentError);
    store.close();
  });
}
