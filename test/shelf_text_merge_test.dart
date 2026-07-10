import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shakepin/utils/shelf_text_merge.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shakepin-merge-test-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<File> createTextFile(String name, String content) async {
    final file = File('${directory.path}/$name.txt');
    await file.writeAsString(content);
    return file;
  }

  test('merges selected text in the supplied order', () async {
    final first = await createTextFile('first', '第一段');
    final second = await createTextFile('second', '第二段');
    final third = await createTextFile('third', '第三段');

    final mergedPath = await mergeTextFiles([
      second.path,
      first.path,
      third.path,
    ]);

    expect(
      await File(mergedPath).readAsString(),
      '第二段$textMergeSeparator第一段$textMergeSeparator第三段',
    );
    expect(await first.readAsString(), '第一段');
  });

  test('appends dragged sources after the target', () async {
    final target = await createTextFile('target', '目标');
    final firstSource = await createTextFile('first-source', '来源一');
    final secondSource = await createTextFile('second-source', '来源二');

    final mergedPath = await appendTextFilesToTarget(
      targetPath: target.path,
      sourcePaths: [firstSource.path, secondSource.path],
    );

    expect(
      await File(mergedPath).readAsString(),
      '目标$textMergeSeparator来源一$textMergeSeparator来源二',
    );
    expect(await target.readAsString(), '目标');
  });

  test('rejects non-text inputs', () async {
    final first = await createTextFile('first', '文本');
    final image = File('${directory.path}/image.png')..writeAsBytesSync([]);

    await expectLater(
      mergeTextFiles([first.path, image.path]),
      throwsArgumentError,
    );
  });
}
