import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Local, transport-agnostic building block for future Pro resumable uploads.
///
/// It is intentionally NOT connected to LocalSend v2 upload endpoints yet.
/// Every acknowledgement requires a separate durable-write confirmation from
/// the receiver. No byte offset from a peer can make this ledger skip data.
const proMaxChunkBytes = 4 * 1024 * 1024;

enum ProChunkVerdict { staged, duplicate, busy, wrongTransfer, invalidLength, invalidOffset, corrupt, alreadyComplete }

class ProChunkStage {
  final int offset;
  final int length;
  final String sha256Hex;

  const ProChunkStage({required this.offset, required this.length, required this.sha256Hex});

  int get endOffset => offset + length;
}

class ProChunkCheck {
  final ProChunkVerdict verdict;
  final ProChunkStage? stage;

  const ProChunkCheck(this.verdict, [this.stage]);
}

class ProDurableReceipt {
  final String sessionId;
  final String fileId;
  final int confirmedOffset;

  const ProDurableReceipt({required this.sessionId, required this.fileId, required this.confirmedOffset});
}

/// Receiver's monotonic, in-memory acknowledgement ledger.
///
/// An app integration must persist the temporary file and its checkpoint
/// atomically before calling [confirmDurableWrite], and must validate the
/// checkpoint against the on-disk file before restoring this state after a
/// restart. It must never rely on bytes read/sent by the sender as an ACK.
class ProResumeLedger {
  final String sessionId;
  final String fileId;
  final int expectedSize;
  final String expectedSha256Hex;
  final int chunkLimit;
  int _durableOffset = 0;
  bool _completed = false;
  ProChunkStage? _staged;
  final _committed = <int, ({int length, String hash})>{};

  ProResumeLedger({
    required this.sessionId,
    required this.fileId,
    required this.expectedSize,
    required this.expectedSha256Hex,
    this.chunkLimit = proMaxChunkBytes,
  }) {
    if (sessionId.isEmpty || fileId.isEmpty || expectedSize < 0 || chunkLimit < 1 || chunkLimit > proMaxChunkBytes) {
      throw ArgumentError('Invalid resume session or size');
    }
    if (!_isSha256Hex(expectedSha256Hex)) throw ArgumentError.value(expectedSha256Hex, 'expectedSha256Hex');
  }

  int get confirmedOffset => _durableOffset;
  bool get isComplete => _completed;
  bool get hasPendingWrite => _staged != null;

  ProChunkCheck stageChunk({
    required String sessionId,
    required String fileId,
    required int offset,
    required Uint8List bytes,
    required String sha256Hex,
  }) {
    if (sessionId != this.sessionId || fileId != this.fileId) return const ProChunkCheck(ProChunkVerdict.wrongTransfer);
    if (_completed) return const ProChunkCheck(ProChunkVerdict.alreadyComplete);
    if (bytes.isEmpty || bytes.length > chunkLimit || bytes.length > expectedSize) {
      return const ProChunkCheck(ProChunkVerdict.invalidLength);
    }
    if (offset < 0 || offset > expectedSize || offset + bytes.length > expectedSize) {
      return const ProChunkCheck(ProChunkVerdict.invalidOffset);
    }
    if (!_isSha256Hex(sha256Hex)) return const ProChunkCheck(ProChunkVerdict.corrupt);
    final digest = sha256.convert(bytes).toString();
    if (digest.toLowerCase() != sha256Hex.toLowerCase()) return const ProChunkCheck(ProChunkVerdict.corrupt);

    if (offset < _durableOffset) {
      final previous = _committed[offset];
      if (previous?.length == bytes.length && previous?.hash == digest) {
        return const ProChunkCheck(ProChunkVerdict.duplicate);
      }
      return const ProChunkCheck(ProChunkVerdict.invalidOffset);
    }
    if (offset != _durableOffset) return const ProChunkCheck(ProChunkVerdict.invalidOffset);
    if (_staged != null) return const ProChunkCheck(ProChunkVerdict.busy);

    final candidate = ProChunkStage(offset: offset, length: bytes.length, sha256Hex: digest);
    _staged = candidate;
    return ProChunkCheck(ProChunkVerdict.staged, candidate);
  }

  /// Only call AFTER writing and durably syncing the staged bytes to disk,
  /// including required checkpoint metadata. Never call on partial writes.
  ///
  /// The exact stage instance is needed to avoid an ACK from another in-flight
  /// chunk or a stale callback after an abandoned write.
  ProDurableReceipt confirmDurableWrite(ProChunkStage stage) {
    if (!identical(stage, _staged) || stage.offset != _durableOffset || _completed) {
      throw StateError('No matching durable chunk is staged');
    }
    _committed[stage.offset] = (length: stage.length, hash: stage.sha256Hex);
    _durableOffset = stage.endOffset;
    _staged = null;
    return ProDurableReceipt(sessionId: sessionId, fileId: fileId, confirmedOffset: _durableOffset);
  }

  /// An interrupted/failed write must not advance the confirmed offset.
  /// The on-disk staging file must be truncated to [confirmedOffset] before
  /// reusing it: uncommitted bytes may exist beyond that boundary.
  void abandonPendingWrite() => _staged = null;

  /// Called only after recalculating the full final hash from the RECEIVER's
  /// durable file and comparing with the sender's authenticated file digest.
  /// Atomic publication/rename must happen separately after this succeeds.
  bool verifyFinalFile({required String receiverSha256Hex}) {
    if (_staged != null || _durableOffset != expectedSize || !_isSha256Hex(receiverSha256Hex)) return false;
    if (receiverSha256Hex.toLowerCase() != expectedSha256Hex.toLowerCase()) return false;
    _completed = true;
    return true;
  }

  static bool _isSha256Hex(String value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}
