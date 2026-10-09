import '../../domain/catalog.dart';

class SourcePage {
  const SourcePage(this.titles, {required this.hasMore});
  final List<Anime> titles;
  final bool hasMore;
}

abstract interface class AnimeSource {
  String get id;
  String get name;
  Future<SourcePage> browse({String query = '', int page = 1});
  Future<Anime> details(Anime anime);
  Future<List<VideoStream>> resolve(Anime anime, Episode episode);
  void dispose();
}
