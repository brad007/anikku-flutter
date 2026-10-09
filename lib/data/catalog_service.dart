import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../domain/catalog.dart';

class CatalogService {
  CatalogService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const maxBytes = 5 * 1024 * 1024;

  Future<Catalog> sample() async => decode(
    await rootBundle.loadString('assets/catalog/sample.json'),
    isSample: true,
  );

  Future<Catalog> fetch(Uri url) async {
    networkUri(url.toString(), 'catalog URL');
    final response = await _client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw FormatException(
        'Catalog server returned HTTP ${response.statusCode}.',
      );
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('Catalog is larger than 5 MB.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('Catalog is larger than 5 MB.');
      }
    }
    return decode(utf8.decode(bytes), url: url);
  }

  Catalog decode(String text, {Uri? url, bool isSample = false}) {
    try {
      return Catalog.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
        url: url,
        isSample: isSample,
      );
    } on TypeError {
      throw const FormatException(
        'Invalid catalog fields. See the catalog format in the project docs.',
      );
    }
  }

  void dispose() => _client.close();
}
