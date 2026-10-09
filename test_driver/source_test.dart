import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 8),
  responseDataCallback: (data) async {
    if (data?['verified'] != true) {
      throw StateError('Real anime verification did not finish.');
    }
    final platform = data!['platform'];
    for (final name in [
      'source-home',
      'source-playing',
      if (data['playbackOnly'] != true) 'source-offline',
    ]) {
      final encoded = data[name];
      if (encoded is! String) throw StateError('Missing $name evidence.');
      await File(
        'evidence/$platform-${data['playbackOnly'] == true ? 'buffering-' : ''}$name.png',
      ).writeAsBytes(base64Decode(encoded));
    }
  },
);
