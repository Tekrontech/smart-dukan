import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// File helpers. Destinations go through the system pickers (phone storage,
/// USB, Google Drive app) or the share sheet (WhatsApp) — the app never
/// uploads anything itself (spec Section 9).

/// Picks one file and returns its bytes, or null if cancelled.
Future<Uint8List?> pickFileBytes({List<String>? extensions}) async {
  final files = await FilePicker.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  if (files.isEmpty) return null;
  return files.first.readAsBytes();
}

/// Picks one file and returns (name, bytes).
Future<({String name, Uint8List bytes})?> pickNamedFile({List<String>? extensions}) async {
  final files = await FilePicker.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  if (files.isEmpty) return null;
  return (name: files.first.name, bytes: await files.first.readAsBytes());
}

/// Lets the user choose where to save [bytes]. Returns false if cancelled.
Future<bool> saveBytesAs(String fileName, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
  return uri != null;
}

/// Writes [bytes] to a temporary file and opens the share sheet.
Future<void> shareBytes(String fileName, Uint8List bytes, {String? mimeType, String? text}) async {
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, 'share', fileName));
  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mimeType)], text: text));
}

Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));
