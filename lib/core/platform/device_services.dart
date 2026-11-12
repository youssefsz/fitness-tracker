import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/data_transfer/transfer_codec.dart';
import '../../shared/domain/training.dart';

abstract interface class FeedbackService {
  Future<void> selection();
  Future<void> saved();
}

class DeviceFeedback implements FeedbackService {
  const DeviceFeedback();

  @override
  Future<void> selection() => HapticFeedback.selectionClick();

  @override
  Future<void> saved() => HapticFeedback.lightImpact();
}

abstract interface class TransferFiles {
  Future<String?> pickJson();
  Future<void> copy(String text);
  Future<void> share(
    String filename,
    String content,
    Rect origin, {
    required bool csv,
  });
  Future<String> saveRecovery(String filename, String content);
  Future<List<String>> recoveryFiles();
  Future<String> readRecovery(String filename);
}

class DeviceTransferFiles implements TransferFiles {
  const DeviceTransferFiles();

  @override
  Future<String?> pickJson() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxTransferBytes) {
      throw const TrackerException('This file is larger than 20 MB.');
    }
    // Bound the read again in case a provider replaced the selected file.
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxTransferBytes) {
        throw const TrackerException('This file is larger than 20 MB.');
      }
      bytes.addAll(chunk);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const TrackerException('This file is not UTF-8 JSON.');
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<void> share(
    String filename,
    String content,
    Rect origin, {
    required bool csv,
  }) async {
    final temp = await getTemporaryDirectory();
    final folder = Directory(p.join(temp.path, 'exports'));
    await folder.create(recursive: true);
    final file = await File(p.join(folder.path, filename))
        .writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, mimeType: csv ? 'text/csv' : 'application/json'),
        ],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<Directory> _recoveryFolder() async {
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'restore-backups'));
  }

  @override
  Future<String> saveRecovery(String filename, String content) async {
    final folder = await _recoveryFolder();
    await folder.create(recursive: true);
    final finalPath = p.join(folder.path, filename);
    final temp = File('$finalPath.part');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(finalPath);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    return filename;
  }

  @override
  Future<List<String>> recoveryFiles() async {
    final folder = await _recoveryFolder();
    if (!await folder.exists()) return [];
    final list = await folder
        .list(followLinks: false)
        .where((file) => file is File && file.path.endsWith('.json'))
        .map((file) => p.basename(file.path))
        .toList();
    return list..sort((a, b) => b.compareTo(a));
  }

  @override
  Future<String> readRecovery(String filename) async {
    if (p.basename(filename) != filename || !filename.endsWith('.json')) {
      throw const TrackerException('Invalid recovery backup filename.');
    }
    final folder = await _recoveryFolder();
    final file = File(p.join(folder.path, filename));
    if (await file.length() > maxTransferBytes) {
      throw const TrackerException(
        'This recovery backup is larger than 20 MB.',
      );
    }
    return file.readAsString();
  }
}
