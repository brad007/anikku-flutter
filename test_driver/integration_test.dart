import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 6),
  responseDataCallback: (data) async {
    final prefix = data?['platform'] == 'macos' ? 'macos' : 'tvos';
    if (data?['tvos-anime'] case final String encoded) {
      await File('evidence/$prefix-anime.png')
          .writeAsBytes(base64Decode(encoded));
    }
    // Also guards against a misconfigured runner declaring zero tests.
    for (final name in [
      'tvos-browse',
      'tvos-playback',
      'tvos-catalog',
      'tvos-home',
      'tvos-downloads',
    ]) {
      final encoded = data?[name];
      if (encoded is! String) {
        throw StateError('Missing native evidence: $name');
      }
      await Directory('evidence').create(recursive: true);
      await File('evidence/${name.replaceFirst('tvos', prefix)}.png')
          .writeAsBytes(base64Decode(encoded));
    }
  },
);
