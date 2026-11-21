import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/resumable_chunk_ledger.dart';

String hash(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
  ProResumeLedger fresh() => ProResumeLedger(
    sessionId: 'authenticated-session',
    fileId: 'file-1',
    expectedSize: payload.length,
    expectedSha256Hex: hash(payload),
    chunkLimit: 4,
  );

  ProChunkCheck offer(ProResumeLedger ledger, int offset, List<int> bytes, {String? sessionId, String? fileId, String? digest}) {
    return ledger.stageChunk(
      sessionId: sessionId ?? 'authenticated-session',
      fileId: fileId ?? 'file-1',
      offset: offset,
      bytes: Uint8List.fromList(bytes),
      sha256Hex: digest ?? hash(bytes),
    );
  }

  test('only durably confirmed chunks advance offset; missing final bytes forbid success', () {
    final ledger = fresh();
    final first = offer(ledger, 0, [1, 2, 3, 4]);
    expect(first.verdict, ProChunkVerdict.staged);
    expect(ledger.confirmedOffset, 0);
    expect(ledger.verifyFinalFile(receiverSha256Hex: hash(payload)), false);
    final receipt = ledger.confirmDurableWrite(first.stage!);
    expect(receipt.confirmedOffset, 4);
    expect(receipt.sessionId, 'authenticated-session');
    expect(ledger.verifyFinalFile(receiverSha256Hex: hash(payload)), false);

    final second = offer(ledger, 4, [5, 6]);
    expect(second.verdict, ProChunkVerdict.staged);
    expect(ledger.confirmDurableWrite(second.stage!).confirmedOffset, 6);
    expect(ledger.verifyFinalFile(receiverSha256Hex: hash(payload)), true);
    expect(ledger.isComplete, true);
    expect(offer(ledger, 6, [7]).verdict, ProChunkVerdict.alreadyComplete);
  });

  test('a network interruption cannot turn a partial write into an acknowledged offset', () {
    final ledger = fresh();
    final first = offer(ledger, 0, [1, 2, 3, 4]).stage!;
    ledger.abandonPendingWrite();
    expect(ledger.confirmedOffset, 0);
    expect(() => ledger.confirmDurableWrite(first), throwsStateError);
    final retried = offer(ledger, 0, [1, 2, 3, 4]);
    expect(retried.verdict, ProChunkVerdict.staged);
  });

  test('replayed acknowledged chunk is idempotent; modified replay is not', () {
    final ledger = fresh();
    final first = offer(ledger, 0, [1, 2, 3, 4]);
    ledger.confirmDurableWrite(first.stage!);
    expect(offer(ledger, 0, [1, 2, 3, 4]).verdict, ProChunkVerdict.duplicate);
    expect(offer(ledger, 0, [9, 2, 3, 4]).verdict, ProChunkVerdict.invalidOffset);
    expect(ledger.confirmedOffset, 4);
  });

  test('rejects corrupt hashes, wrong session, future offsets, oversized chunks and concurrent writes', () {
    final ledger = fresh();
    expect(offer(ledger, 0, [1], sessionId: 'attacker').verdict, ProChunkVerdict.wrongTransfer);
    expect(offer(ledger, 3, [1]).verdict, ProChunkVerdict.invalidOffset);
    expect(offer(ledger, 0, [1, 2, 3, 4, 5]).verdict, ProChunkVerdict.invalidLength);
    expect(offer(ledger, 0, [1], digest: hash([8])).verdict, ProChunkVerdict.corrupt);
    final first = offer(ledger, 0, [1, 2]);
    expect(first.verdict, ProChunkVerdict.staged);
    expect(offer(ledger, 0, [1, 2]).verdict, ProChunkVerdict.busy);
    ledger.confirmDurableWrite(first.stage!);
  });

  test('a completed byte count alone is insufficient without matching receiver hash', () {
    final ledger = fresh();
    final first = offer(ledger, 0, [1, 2, 3, 4]).stage!;
    ledger.confirmDurableWrite(first);
    final second = offer(ledger, 4, [5, 6]).stage!;
    ledger.confirmDurableWrite(second);
    expect(ledger.verifyFinalFile(receiverSha256Hex: hash([6, 5, 4, 3, 2, 1])), false);
    expect(ledger.isComplete, false);
  });

  test('empty files require verified empty-content SHA-256 without chunk writes', () {
    final ledger = ProResumeLedger(
      sessionId: 's',
      fileId: 'empty',
      expectedSize: 0,
      expectedSha256Hex: hash([]),
    );
    expect(ledger.verifyFinalFile(receiverSha256Hex: hash([])), true);
  });
}
