import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';
import 'hermes_video_player.dart';
import 'source_selector_card.dart';

class CinemaCatalogScreen extends StatefulWidget {
  const CinemaCatalogScreen({
    super.key,
    required this.cinemaService,
    required this.playerConfig,
    required this.defaultQuality,
  });

  final CinemaService cinemaService;
  final HermesVideoPlayerConfig playerConfig;
  final VideoQualityPreset defaultQuality;

  @override
  State<CinemaCatalogScreen> createState() => _CinemaCatalogScreenState();
}

class _CinemaCatalogScreenState extends State<CinemaCatalogScreen> {
  late Future<(List<MovieSummary>, List<TvSeriesSummary>)> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _load();
  }

  Future<(List<MovieSummary>, List<TvSeriesSummary>)> _load() async {
    final movies = await widget.cinemaService.listMovies();
    final series = await widget.cinemaService.listSeries();
    return (movies, series);
  }

  void _openSourceSheet({
    required String title,
    required List<MediaSourceModel> sources,
    String? movieId,
    String? episodeId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SourceSelectorCard(
          sources: sources,
          initialQuality: widget.defaultQuality,
          onPlaySource: (source, quality) {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HermesVideoPlayerScreen(
                  title: title,
                  source: source,
                  initialQuality: quality,
                  config: widget.playerConfig,
                  cinemaService: widget.cinemaService,
                  movieId: movieId,
                  episodeId: episodeId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return FutureBuilder<(List<MovieSummary>, List<TvSeriesSummary>)>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load Cinema catalog: ${snapshot.error}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _catalogFuture = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final (movies, series) = snapshot.data ?? (<MovieSummary>[], <TvSeriesSummary>[]);
        if (movies.isEmpty && series.isEmpty) {
          return Center(
            child: Text(
              'No movies or series scanned yet. Open Admin Dashboard to add a library root.',
              style: TextStyle(color: tokens.textSecondary),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (movies.isNotEmpty) ...[
              Text('Movies (${movies.length})', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...movies.map((movie) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(movie.year == null ? movie.title : '${movie.title} (${movie.year})'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${movie.sources.length} source(s)'),
                          if (movie.watchProgress != null) ...[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: movie.watchProgress!.completionRatio),
                          ],
                        ],
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: movie.sources.isEmpty
                            ? null
                            : () => _openSourceSheet(
                                  title: movie.title,
                                  sources: movie.sources,
                                  movieId: movie.id,
                                ),
                        child: const Text('Watch'),
                      ),
                    ),
                  )),
            ],
            if (series.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('TV Series (${series.length})', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...series.map((show) => ExpansionTile(
                    title: Text(show.year == null ? show.title : '${show.title} (${show.year})'),
                    children: [
                      for (final season in show.seasons)
                        for (final ep in season.episodes)
                          ListTile(
                            title: Text('S${season.seasonNumber}E${ep.episodeNumber} • ${ep.title}'),
                            subtitle: Text('${ep.sources.length} source(s)'),
                            trailing: TextButton(
                              onPressed: ep.sources.isEmpty
                                  ? null
                                  : () => _openSourceSheet(
                                        title: '${show.title} S${season.seasonNumber}E${ep.episodeNumber}',
                                        sources: ep.sources,
                                        episodeId: ep.id,
                                      ),
                              child: const Text('Play'),
                            ),
                          ),
                    ],
                  )),
            ],
          ],
        );
      },
    );
  }
}
