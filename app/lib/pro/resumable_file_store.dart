import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/pro/resumable_chunk_ledger.dart';
import 'package:localsend_isolates/rust/api/pro_file_lease.dart';

/// App-private, Android-oriented resumable receive staging.
///
/// This is an offline storage building block, NOT a LocalSend protocol endpoint.
/// The caller must authenticate its peer, authenticate the expected full-file
/// SHA-256, and ensure each chunk belongs to the accepted transfer session.
///
/// Each acknowledged chunk is flushed to a .part file before a replacement
/// checkpoint is written, flushed and renamed in the same private directory.
/// After an ordinary process crash, open() verifies every checkpointed chunk
/// before it can issue any new acknowledgement, and discards uncheckpointed
/// trailing bytes. An abrupt power loss may still require native directory
/// fsync for strict durability guarantees; this component must not be
/// advertised as a complete crash-proof, end-to-end transfer protocol.
class ProResumableFileStore {
  final File partFile;
  final File checkpointFile;
  final File temporaryCheckpointFile;
  final ProResumeLedger ledger;
  final List<ProChunkStage> _confirmedChunks;
  final String _storeKey;
  final RsProFileLease? _nativeLease;

  // Also guards concurrent open() calls within the same Dart isolate.
  // Android additionally requires the native file-description flock lease:
  // it is non-blocking and excludes independent writers in OTHER isolates
  // or processes, and its OS lock is released after an ordinary process crash.
  // Non-Android hosts use only this in-isolate safeguard.
  static final Set<String> _activeStores = <String>{};

  bool _busy = false;
  bool _closed = false;

  ProResumableFileStore._({
    required this.partFile,
    required this.checkpointFile,
    required this.temporaryCheckpointFile,
    required this.ledger,
    required List<ProChunkStage> confirmedChunks,
    required String storeKey,
    required RsProFileLease? nativeLease,
  }) : _confirmedChunks = confirmedChunks,
       _storeKey = storeKey,
       _nativeLease = nativeLease;

  int get confirmedOffset => ledger.confirmedOffset;
  bool get isComplete => ledger.isComplete;

  /// Call with an APP-PRIVATE directory, never a public downloads folder.
  /// A restart with mismatched session/file/hash or corrupted checkpoint fails
  /// closed, preserving both files for investigation rather than trusting bytes.
  static Future<ProResumableFileStore> open({
    required Directory directory,
    required String sessionId,
    required String fileId,
    required int expectedSize,
    required String expectedSha256Hex,
    int chunkLimit = proMaxChunkBytes,
  }) async {
    final ledger = ProResumeLedger(
      sessionId: sessionId,
      fileId: fileId,
      expectedSize: expectedSize,
      expectedSha256Hex: expectedSha256Hex,
      chunkLimit: chunkLimit,
    );
    await directory.create(recursive: true);
    final canonicalDirectory = await directory.resolveSymbolicLinks();
    final storageId = sha256.convert(utf8.encode('$sessionId\u0000$fileId')).toString();
    final base = '$canonicalDirectory${Platform.pathSeparator}pro_$storageId';
    if (!_activeStores.add(base)) {
      throw StateError('This Pro partial file already has an active writer in this isolate');
    }
    RsProFileLease? nativeLease;
    try {
      if (Platform.isAndroid) {
        // Acquiring the lease MUST succeed before any .part or checkpoint
        // operation. Never silently fall back to an unlocked Android writer.
        // The .lease file remains on disk: deleting it can split inode locks.
        nativeLease = acquireProFileLease(path: '$base.lease');
      }
      return await _openReserved(
        base: base,
        nativeLease: nativeLease,
        sessionId: sessionId,
        fileId: fileId,
        expectedSize: expectedSize,
        expectedSha256Hex: expectedSha256Hex,
        chunkLimit: chunkLimit,
        ledger: ledger,
      );
    } catch (_) {
      nativeLease?.release();
      _activeStores.remove(base);
      rethrow;
    }
  }

  static Future<ProResumableFileStore> _openReserved({
    required String base,
    required RsProFileLease? nativeLease,
    required String sessionId,
    required String fileId,
    required int expectedSize,
    required String expectedSha256Hex,
    required int chunkLimit,
    required ProResumeLedger ledger,
  }) async {
    final part = File('$base.part');
    final checkpoint = File('$base.checkpoint.json');
    final pendingCheckpoint = File('$base.checkpoint.pending');

    // A process may have died during the preceding temp checkpoint write.
    // Never promote an uncommitted checkpoint.
    if (await pendingCheckpoint.exists()) await pendingCheckpoint.delete();

    final confirmed = <ProChunkStage>[];
    if (await checkpoint.exists()) {
      if (!await part.exists()) throw StateError('Checkpoint exists without matching partial file');
      final length = await checkpoint.length();
      if (length > 16 * 1024 * 1024) throw StateError('Checkpoint exceeds safe metadata size');
      final dynamic decoded;
      try {
        decoded = jsonDecode(await checkpoint.readAsString());
      } on FormatException {
        throw StateError('Malformed Pro checkpoint');
      }
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != 1 ||
          decoded['sessionId'] != sessionId ||
          decoded['fileId'] != fileId ||
          decoded['expectedSize'] != expectedSize ||
          decoded['expectedSha256Hex']?.toString().toLowerCase() != expectedSha256Hex.toLowerCase() ||
          decoded['chunkLimit'] != chunkLimit ||
          decoded['chunks'] is! List) {
        throw StateError('Checkpoint identity or schema mismatch');
      }

      final entries = decoded['chunks'] as List;
      if (entries.length > 200000) throw StateError('Too many checkpoint chunks');
      var nextOffset = 0;
      final totalOnDisk = await part.length();
      final reader = await part.open(mode: FileMode.read);
      try {
        for (final raw in entries) {
          if (raw is! Map<String, dynamic>) throw StateError('Invalid checkpoint chunk');
          final offset = raw['offset'];
          final length = raw['length'];
          final hash = raw['sha256Hex'];
          if (offset is! int || length is! int || hash is! String ||
              offset != nextOffset || length < 1 || length > chunkLimit ||
              offset + length > expectedSize || offset + length > totalOnDisk) {
            throw StateError('Invalid or incomplete checkpoint chunk');
          }
          await reader.setPosition(offset);
          final bytes = await reader.read(length);
          if (bytes.length != length || sha256.convert(bytes).toString() != hash.toLowerCase()) {
            throw StateError('Partial file does not match checkpoint hash');
          }
          final checked = ledger.stageChunk(
            sessionId: sessionId,
            fileId: fileId,
            offset: offset,
            bytes: Uint8List.fromList(bytes),
            sha256Hex: hash,
          );
          if (checked.verdict != ProChunkVerdict.staged || checked.stage == null) {
            throw StateError('Checkpoint replay failed validation');
          }
          ledger.confirmDurableWrite(checked.stage!);
          confirmed.add(checked.stage!);
          nextOffset += length;
        }
      } finally {
        await reader.close();
      }

      // Bytes written before a crash but not recorded in the committed
      // checkpoint are speculative and must not be exposed for resumption.
      if (totalOnDisk > nextOffset) {
        final file = await part.open(mode: FileMode.append);
        try {
          await file.truncate(nextOffset);
          await file.flush();
        } finally {
          await file.close();
        }
      }
    } else {
      // A nonempty orphan .part is not authenticated by any checkpoint.
      // Preserve it for investigation instead of silently truncating bytes.
      // An empty .part from a crash during initialization can be reused.
      if (await part.exists()) {
        if (await part.length() != 0) {
          throw StateError('Orphan Pro partial file without verified checkpoint');
        }
      } else {
        final file = await part.open(mode: FileMode.write);
        try {
          await file.flush();
        } finally {
          await file.close();
        }
      }
      await _publishCheckpoint(
        checkpoint: checkpoint,
        pending: pendingCheckpoint,
        sessionId: sessionId,
        fileId: fileId,
        expectedSize: expectedSize,
        expectedSha256Hex: expectedSha256Hex,
        chunkLimit: chunkLimit,
        chunks: confirmed,
      );
    }

    return ProResumableFileStore._(
      partFile: part,
      checkpointFile: checkpoint,
      temporaryCheckpointFile: pendingCheckpoint,
      ledger: ledger,
      confirmedChunks: confirmed,
      storeKey: base,
      nativeLease: nativeLease,
    );
  }

  /// Appends one authenticated chunk and returns its receiver-confirmed offset.
  /// A rejected/duplicate chunk performs no write.
  ///
  /// A caller may only treat a successful result as a *local* ACK. The eventual
  /// network ACK must be bound to the authenticated peer and file token.
  Future<ProPersistOutcome> append({
    required String sessionId,
    required String fileId,
    required int offset,
    required Uint8List bytes,
    required String sha256Hex,
  }) async {
    if (_closed) throw StateError('Store is closed');
    if (_busy) return ProPersistOutcome(ProChunkVerdict.busy, confirmedOffset);
    _busy = true;
    try {
      final check = ledger.stageChunk(
        sessionId: sessionId,
        fileId: fileId,
        offset: offset,
        bytes: bytes,
        sha256Hex: sha256Hex,
      );
      if (check.verdict != ProChunkVerdict.staged || check.stage == null) {
        return ProPersistOutcome(check.verdict, confirmedOffset);
      }
      final stage = check.stage!;
      try {
        // Existing tail may be left by a failed write in this same process.
        final file = await partFile.open(mode: FileMode.append);
        try {
          await file.truncate(confirmedOffset);
          await file.setPosition(confirmedOffset);
          await file.writeFrom(bytes);
          await file.flush();
        } finally {
          await file.close();
        }

        final candidate = [..._confirmedChunks, stage];
        await _publishCheckpoint(
          checkpoint: checkpointFile,
          pending: temporaryCheckpointFile,
          sessionId: ledger.sessionId,
          fileId: ledger.fileId,
          expectedSize: ledger.expectedSize,
          expectedSha256Hex: ledger.expectedSha256Hex,
          chunkLimit: ledger.chunkLimit,
          chunks: candidate,
        );
        // Only advance after both the file and checkpoint have been flushed.
        final receipt = ledger.confirmDurableWrite(stage);
        _confirmedChunks.add(stage);
        return ProPersistOutcome(ProChunkVerdict.staged, receipt.confirmedOffset);
      } catch (_) {
        ledger.abandonPendingWrite();
        // The rename may already have committed the new checkpoint even
        // though an I/O error was observed. This handle no longer knows
        // which state is authoritative: never retry on it. Reopen to replay
        // and verify the committed manifest before a new local ACK.
        _closed = true;
        rethrow;
      }
    } finally {
      _busy = false;
    }
  }

  /// Hash the RECEIVER's full file without loading it into memory.
  /// The caller must still atomically publish the checked .part in its own
  /// trusted save destination after this returns true.
  Future<bool> verifyComplete() async {
    if (_closed || _busy || ledger.hasPendingWrite || confirmedOffset != ledger.expectedSize) return false;
    _busy = true;
    try {
      if (await partFile.length() != ledger.expectedSize) {
        _closed = true;
        return false;
      }
      final digest = await sha256.bind(partFile.openRead()).first;
      final valid = ledger.verifyFinalFile(receiverSha256Hex: digest.toString());
      if (!valid) _closed = true;
      return valid;
    } catch (_) {
      _closed = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Closing while hashing or persisting is forbidden: doing so would
  /// relinquish in-isolate ownership while an old operation is still active.
  /// Every open() must be paired with close(), including after I/O failure.
  void close() {
    if (_busy) throw StateError('Cannot close Pro file store with an operation in progress');
    _closed = true;
    try {
      _nativeLease?.release();
    } finally {
      _activeStores.remove(_storeKey);
    }
  }

  static Future<void> _publishCheckpoint({
    required File checkpoint,
    required File pending,
    required String sessionId,
    required String fileId,
    required int expectedSize,
    required String expectedSha256Hex,
    required int chunkLimit,
    required List<ProChunkStage> chunks,
  }) async {
    final raw = jsonEncode({
      'schema': 1,
      'sessionId': sessionId,
      'fileId': fileId,
      'expectedSize': expectedSize,
      'expectedSha256Hex': expectedSha256Hex.toLowerCase(),
      'chunkLimit': chunkLimit,
      'chunks': [
        for (final c in chunks) {'offset': c.offset, 'length': c.length, 'sha256Hex': c.sha256Hex},
      ],
    });
    final file = await pending.open(mode: FileMode.write);
    try {
      await file.writeString(raw);
      await file.flush();
    } finally {
      await file.close();
    }
    // Same-directory rename is atomic on Android's supported Linux filesystems.
    // Native directory fsync must be added before claiming power-loss durability.
    await pending.rename(checkpoint.path);
  }
}

class ProPersistOutcome {
  final ProChunkVerdict verdict;
  final int confirmedOffset;

  const ProPersistOutcome(this.verdict, this.confirmedOffset);
}
