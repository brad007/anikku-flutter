import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/catalog_service.dart';
import 'data/sources/animegg_source.dart';
import 'data/sources/internet_archive_source.dart';
import 'data/sources/user_configured_sources.dart';
import 'data/download_manager.dart';
import 'data/library_model.dart';
import 'data/library_repository.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final model = LibraryModel(
    store: FileStateStore(
      directory: Platform.operatingSystem == 'tvos'
          ? getApplicationCacheDirectory
          : getApplicationSupportDirectory,
    ),
    catalogs: CatalogService(),
    includeSamples: false,
    sources: [
      AnimeGgSource(),
      InternetArchiveSource(),
      ...userConfiguredSources(),
    ],
    downloads: DownloadManager(
      directory: Platform.operatingSystem == 'tvos'
          ? getApplicationCacheDirectory
          : getApplicationSupportDirectory,
    ),
  );
  runApp(AnikkuApp(model: model));
  model.initialize();
}
