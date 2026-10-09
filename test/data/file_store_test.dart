import 'dart:io';

import 'package:anikku/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'file store replaces snapshots atomically and reloads large catalogs',
    () async {
      final directory = await Directory.systemTemp.createTemp('anikku-test-');
      final store = FileStateStore(directory: () async => directory);
      try {
        expect(await store.read(), isNull);
        await store.write({'version': 1, 'data': 'a' * 1100000});
        expect((await store.read())!['data'], hasLength(1100000));
        await store.write({'version': 1, 'data': 'updated'});
        final restored = FileStateStore(directory: () async => directory);
        expect((await restored.read())!['data'], 'updated');
        expect(
          await File('${directory.path}/anikku-library-v1.json.tmp').exists(),
          isFalse,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
