import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shakepin/utils/utils.dart';

const textMergeSeparator = '\n\n';

bool isPlainTextShelfItem(String itemPath) {
  return !isUrl(itemPath) && path.extension(itemPath).toLowerCase() == '.txt';
}

Future<String> mergeTextFiles(
  List<String> sourcePaths, {
  String separator = textMergeSeparator,
}) async {
  final uniquePaths = <String>{
    for (final sourcePath in sourcePaths) sourcePath,
  }.toList();
  if (uniquePaths.length < 2 || !uniquePaths.every(isPlainTextShelfItem)) {
    throw ArgumentError('At least two plain text files are required to merge.');
  }

  final contents = <String>[];
  for (final sourcePath in uniquePaths) {
    contents.add(await File(sourcePath).readAsString());
  }

  return _writeMergedText(contents.join(separator));
}

Future<String> appendTextFilesToTarget({
  required String targetPath,
  required List<String> sourcePaths,
  String separator = textMergeSeparator,
}) async {
  final uniqueSources = <String>{
    for (final sourcePath in sourcePaths)
      if (sourcePath != targetPath) sourcePath,
  }.toList();

  if (!isPlainTextShelfItem(targetPath) ||
      uniqueSources.isEmpty ||
      !uniqueSources.every(isPlainTextShelfItem)) {
    throw ArgumentError(
        'A text target and at least one text source are required.');
  }

  final contents = <String>[await File(targetPath).readAsString()];
  for (final sourcePath in uniqueSources) {
    contents.add(await File(sourcePath).readAsString());
  }

  return _writeMergedText(contents.join(separator));
}

Future<String> _writeMergedText(String content) async {
  final directory = await Directory.systemTemp.createTemp('shakepin-merge-');
  final file = File(path.join(directory.path, '合并文本.txt'));
  await file.writeAsString(content, flush: true);
  return file.path;
}
