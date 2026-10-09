import 'package:http/http.dart' as http;

import 'anime_source.dart';
import 'anime_onsen_source.dart';
import 'anikoto_source.dart';
import 'user_source_config.dart';

List<AnimeSource> userConfiguredSources({http.Client? client}) {
  final sources = <AnimeSource>[];
  final onsen = AnimeOnsenConfig.fromValues(
    name: userAnimeOnsenName,
    baseUrl: userAnimeOnsenBaseUrl,
    apiUrl: userAnimeOnsenApiUrl,
    searchUrl: userAnimeOnsenSearchUrl,
  );
  if (onsen != null) {
    sources.add(AnimeOnsenSource(config: onsen, client: client));
  }

  final anikoto = AnikotoConfig.fromValues(
    name: userAnikotoName,
    baseUrl: userAnikotoBaseUrl,
    episodeListTemplate: userAnikotoEpisodeListTemplate,
    serverListTemplate: userAnikotoServerListTemplate,
    streamResolverTemplate: userAnikotoStreamResolverTemplate,
  );
  if (anikoto != null) {
    sources.add(AnikotoSource(config: anikoto, client: client));
  }
  return sources;
}
