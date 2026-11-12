import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/data_transfer/transfer_codec.dart';
import '../../shared/domain/training.dart';

abstract interface class FeedbackService {
  Future<void> selection();
  Future<void> saved();
}

typedef AppBuild = ({String version, String number});

Future<AppBuild> installedAppBuild() async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, number: info.buildNumber);
}

abstract interface class ProfilePhotos {
  Future<Uint8List?> pick();
  Future<Uint8List?> recover();
}

class DeviceProfilePhotos implements ProfilePhotos {
  final _picker = ImagePicker();

  @override
  Future<Uint8List?> pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      requestFullMetadata: false,
    );
    return file == null ? null : _avatarBytes(file);
  }

  @override
  Future<Uint8List?> recover() async {
    if (!Platform.isAndroid) return null;
    final result = await _picker.retrieveLostData();
    if (result.exception case final error?) throw error;
    final file = result.files?.firstOrNull;
    return file == null ? null : _avatarBytes(file);
  }

  Future<Uint8List> _avatarBytes(XFile file) async {
    const maxSourceBytes = 20 * 1024 * 1024;
    if (await file.length() > maxSourceBytes) {
      throw const TrackerException('Choose a photo under 20 MB.');
    }
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        const side = 384;
        if (width <= side && height <= side) return const ui.TargetImageSize();
        return width >= height
            ? const ui.TargetImageSize(width: side)
            : const ui.TargetImageSize(height: side);
      },
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) {
          throw const TrackerException('Couldn’t prepare this photo.');
        }
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
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
  Future<void> clearLocalCopies();
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
    final folder = await _exportFolder();
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

  Future<Directory> _exportFolder() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, 'exports'));
  }

  @override
  Future<void> clearLocalCopies() async {
    final exports = await _exportFolder();
    for (final folder in [
      await _recoveryFolder(),
      exports,
      // Android's share plugin keeps a separate copy of shared files.
      if (Platform.isAndroid)
        Directory(p.join(exports.parent.path, 'share_plus')),
    ]) {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
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
