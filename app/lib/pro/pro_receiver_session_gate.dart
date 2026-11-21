import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/pro/resumable_file_store.dart';

/// Receiver-local access control for one accepted Pro file. Not a network
/// endpoint: a future HTTP handler MUST pass the fingerprint from the actual
/// VERIFIED mTLS client certificate and a per-file post-consent secret.
/// Never accept a claimed peer fingerprint from a JSON request as proof.
/// Never put the per-file secret in discovery, a URL, metrics or logs.
class ProReceiverSessionGate {
  final ProResumableFileStore _store;
  final String _expectedPeerFingerprint;
  final Uint8List _tokenDigest;

  ProReceiverSessionGate({
    required ProResumableFileStore store,
    required String verifiedPeerFingerprint,
    required String fileToken,
  }) : _store = store,
       _expectedPeerFingerprint = verifiedPeerFingerprint.toUpperCase(),
       _tokenDigest = Uint8List.fromList(sha256.convert(utf8.encode(fileToken)).bytes) {
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(_expectedPeerFingerprint)) {
      throw ArgumentError.value(verifiedPeerFingerprint, 'verifiedPeerFingerprint', 'Expected a certificate SHA-256');
    }
    // A strong, cryptographically generated file token is mandatory.
    // Length alone is NOT an entropy guarantee; the issuer is responsible.
    if (fileToken.length < 32 || fileToken.length > 256) {
      throw ArgumentError('Expected a private file token of 32-256 characters');
    }
  }

  bool _authorized({
    required String presentedPeerFingerprint,
    required String sessionId,
    required String fileId,
    required String expectedSha256Hex,
    required String fileToken,
  }) {
    if (presentedPeerFingerprint.toUpperCase() != _expectedPeerFingerprint ||
        sessionId != _store.ledger.sessionId ||
        fileId != _store.ledger.fileId ||
        expectedSha256Hex.toLowerCase() != _store.ledger.expectedSha256Hex.toLowerCase() ||
        fileToken.length < 32 ||
        fileToken.length > 256) {
      return false;
    }
    final candidate = sha256.convert(utf8.encode(fileToken)).bytes;
    // Constant-work comparison avoids exposing matching digest prefix length.
    var difference = 0;
    for (var i = 0; i < _tokenDigest.length; i++) {
      difference |= _tokenDigest[i] ^ candidate[i];
    }
    return difference == 0;
  }

  /// Only receiver-verified progress is returned. Null means unauthorized,
  /// inactive or busy; it does not disclose whether a session exists.
  ProVerifiedResumeStatus? verifiedStatus({
    required String presentedPeerFingerprint,
    required String sessionId,
    required String fileId,
    required String expectedSha256Hex,
    required String fileToken,
  }) {
    if (!_authorized(
          presentedPeerFingerprint: presentedPeerFingerprint,
          sessionId: sessionId,
          fileId: fileId,
          expectedSha256Hex: expectedSha256Hex,
          fileToken: fileToken,
        ) ||
        !_store.canReportVerifiedOffset) {
      return null;
    }
    return ProVerifiedResumeStatus(
      sessionId: _store.ledger.sessionId,
      fileId: _store.ledger.fileId,
      confirmedOffset: _store.confirmedOffset,
      expectedSize: _store.ledger.expectedSize,
      complete: _store.isComplete,
    );
  }

  /// A future receiver transport may use this after authenticating the mTLS
  /// peer and accepted file token. Invalid callers receive NO progress/ACK.
  Future<ProPersistOutcome?> appendAuthorized({
    required String presentedPeerFingerprint,
    required String sessionId,
    required String fileId,
    required String expectedSha256Hex,
    required String fileToken,
    required int offset,
    required Uint8List bytes,
    required String chunkSha256Hex,
  }) async {
    if (!_authorized(
      presentedPeerFingerprint: presentedPeerFingerprint,
      sessionId: sessionId,
      fileId: fileId,
      expectedSha256Hex: expectedSha256Hex,
      fileToken: fileToken,
    )) {
      return null;
    }
    return _store.append(sessionId: sessionId, fileId: fileId, offset: offset, bytes: bytes, sha256Hex: chunkSha256Hex);
  }
}

/// Safe to expose only after full session authentication; no secret/token.
class ProVerifiedResumeStatus {
  final String sessionId;
  final String fileId;
  final int confirmedOffset;
  final int expectedSize;
  final bool complete;

  const ProVerifiedResumeStatus({
    required this.sessionId,
    required this.fileId,
    required this.confirmedOffset,
    required this.expectedSize,
    required this.complete,
  });
}
