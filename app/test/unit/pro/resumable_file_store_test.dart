import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/resumable_chunk_ledger.dart';
import 'package:localsend_app/pro/resumable_file_store.dart';

String digest(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory directory;
  const sessionId = 'secure-session';
  const fileId = 'video-file';
  final payload = Uint8List.fromList([12, 20, 30, 40, 50, 60]);
  Future<ProResumableFileStore> open() => ProResumableFileStore.open(
    directory: directory,
    sessionId: sessionId,
    fileId: fileId,
    expectedSize: payload.length,
    expectedSha256Hex: digest(payload),
    chunkLimit: 4,
  );
  Future<ProPersistOutcome> append(ProResumableFileStore store, int offset, List<int> bytes) => store.append(
    sessionId: sessionId,
    fileId: fileId,
    offset: offset,
    bytes: Uint8List.fromList(bytes),
    sha256Hex: digest(bytes),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pro-resume-store-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('persists confirmed chunks and resumes at verified offset after reopen', () async {
    final first = await open();
    expect((await append(first, 0, [12, 20, 30, 40])).confirmedOffset, 4);
    first.close();

    final resumed = await open();
    expect(resumed.confirmedOffset, 4);
    expect((await append(resumed, 0, [12, 20, 30, 40])).verdict, ProChunkVerdict.duplicate);
    expect((await append(resumed, 4, [50, 60])).confirmedOffset, 6);
    expect(await resumed.verifyComplete(), true);
    expect(await resumed.partFile.readAsBytes(), payload);
    resumed.close();
  });

  test('drops speculative tail after interrupted upload without skipping any byte', () async {
    final first = await open();
    await append(first, 0, [12, 20, 30, 40]);
    await first.partFile.writeAsBytes([99, 98], mode: FileMode.append, flush: true);
    first.close();

    final resumed = await open();
    expect(resumed.confirmedOffset, 4);
    expect(await resumed.partFile.length(), 4);
    expect((await append(resumed, 4, [50, 60])).confirmedOffset, 6);
    expect(await resumed.verifyComplete(), true);
    resumed.close();
  });

  test('fails closed on corrupted committed data, preserving evidence', () async {
    final first = await open();
    await append(first, 0, [12, 20, 30, 40]);
    first.close();
    await first.partFile.writeAsBytes([1, 2, 3, 4], mode: FileMode.write, flush: true);

    await expectLater(open(), throwsStateError);
    expect(await first.checkpointFile.exists(), true);
    expect(await first.partFile.exists(), true);
  });

  test('does not resume with mismatched expected digest or file identity', () async {
    final first = await open();
    await append(first, 0, [12, 20]);
    first.close();
    await expectLater(
      ProResumableFileStore.open(
        directory: directory,
        sessionId: sessionId,
        fileId: fileId,
        expectedSize: payload.length,
        expectedSha256Hex: digest([1, 2, 3, 4, 5, 6]),
        chunkLimit: 4,
      ),
      throwsStateError,
    );
  });

  test('does not acknowledge out-of-order, corrupt, oversized or wrong-session chunks', () async {
    final store = await open();
    expect((await append(store, 1, [20])).verdict, ProChunkVerdict.invalidOffset);
    expect((await append(store, 0, [12, 20, 30, 40, 50])).verdict, ProChunkVerdict.invalidLength);
    final wrong = await store.append(
      sessionId: 'other-session',
      fileId: fileId,
      offset: 0,
      bytes: Uint8List.fromList([12]),
      sha256Hex: digest([12]),
    );
    expect(wrong.verdict, ProChunkVerdict.wrongTransfer);
    final corrupt = await store.append(
      sessionId: sessionId,
      fileId: fileId,
      offset: 0,
      bytes: Uint8List.fromList([12]),
      sha256Hex: digest([20]),
    );
    expect(corrupt.verdict, ProChunkVerdict.corrupt);
    expect(store.confirmedOffset, 0);
    store.close();
  });

  test('rejects tampered checkpoint offsets instead of skipping missing chunks', () async {
    final store = await open();
    await append(store, 0, [12, 20]);
    store.close();
    final metadata = jsonDecode(await store.checkpointFile.readAsString()) as Map<String, dynamic>;
    (metadata['chunks'] as List).first['offset'] = 2;
    await store.checkpointFile.writeAsString(jsonEncode(metadata), flush: true);

    await expectLater(open(), throwsStateError);
  });

  test('second writer in the same isolate is rejected without touching verified bytes', () async {
    final first = await open();
    expect((await append(first, 0, [12, 20, 30, 40])).confirmedOffset, 4);
    await expectLater(open(), throwsStateError);
    expect(await first.partFile.readAsBytes(), [12, 20, 30, 40]);

    first.close();
    final resumed = await open();
    expect(resumed.confirmedOffset, 4);
    expect((await append(resumed, 4, [50, 60])).confirmedOffset, 6);
    expect(await resumed.verifyComplete(), true);
    resumed.close();
  });

  test('failed open releases in-isolate reservation for a legitimate resume', () async {
    final first = await open();
    await append(first, 0, [12, 20]);
    first.close();
    await expectLater(
      ProResumableFileStore.open(
        directory: directory,
        sessionId: sessionId,
        fileId: fileId,
        expectedSize: payload.length,
        expectedSha256Hex: digest([7, 8, 9]),
        chunkLimit: 4,
      ),
      throwsStateError,
    );
    final resumed = await open();
    expect(resumed.confirmedOffset, 2);
    resumed.close();
  });

  test('nonempty orphan .part is preserved and is never accepted', () async {
    final first = await open();
    final part = first.partFile;
    final manifest = first.checkpointFile;
    first.close();
    await manifest.delete();
    await part.writeAsBytes([99, 98, 97], flush: true);
    await expectLater(open(), throwsStateError);
    expect(await part.readAsBytes(), [99, 98, 97]);
    expect(await manifest.exists(), false);
  });

  test('failed checkpoint write poisons handle until replayed from disk', () async {
    final first = await open();
    final obstruction = Directory(first.temporaryCheckpointFile.path);
    await obstruction.create();
    await expectLater(append(first, 0, [12, 20, 30, 40]), throwsA(isA<FileSystemException>()));
    expect(first.confirmedOffset, 0);
    await expectLater(append(first, 0, [12, 20, 30, 40]), throwsStateError);
    first.close();

    await obstruction.delete();
    final resumed = await open();
    expect(resumed.confirmedOffset, 0);
    expect(await resumed.partFile.length(), 0);
    expect((await append(resumed, 0, [12, 20, 30, 40])).confirmedOffset, 4);
    resumed.close();
  });

  test('final digest verification excludes concurrent appends and early close', () async {
    final store = await open();
    await append(store, 0, [12, 20, 30, 40]);
    await append(store, 4, [50, 60]);
    final verification = store.verifyComplete();
    expect(() => store.close(), throwsStateError);
    final competing = await append(store, 4, [50, 60]);
    expect(competing.verdict, ProChunkVerdict.busy);
    expect(await verification, true);
    store.close();
  });

  test('empty file has verified hash and remains resumable', () async {
    final store = await ProResumableFileStore.open(
      directory: directory,
      sessionId: sessionId,
      fileId: 'empty',
      expectedSize: 0,
      expectedSha256Hex: digest([]),
    );
    expect(store.confirmedOffset, 0);
    expect(await store.verifyComplete(), true);
    store.close();
  });
}
