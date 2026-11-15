import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';

enum HermesWorld { cinema, music }

class DualWorldShell extends StatefulWidget {
  const DualWorldShell({
    super.key,
    required this.username,
    required this.isAdmin,
    required this.cinemaBuilder,
    required this.musicBuilder,
    this.miniPlayerBuilder,
    this.onOpenSearch,
    this.onOpenAdmin,
    this.onOpenSettings,
    this.initialWorld = HermesWorld.cinema,
  });

  final String username;
  final bool isAdmin;
  final WidgetBuilder cinemaBuilder;
  final WidgetBuilder musicBuilder;
  final WidgetBuilder? miniPlayerBuilder;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onOpenSettings;
  final HermesWorld initialWorld;

  @override
  State<DualWorldShell> createState() => _DualWorldShellState();
}

class _DualWorldShellState extends State<DualWorldShell> {
  late HermesWorld _world;

  @override
  void initState() {
    super.initState();
    _world = widget.initialWorld;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;
        final activeView = _world == HermesWorld.cinema
            ? widget.cinemaBuilder(context)
            : widget.musicBuilder(context);

        final topBar = AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tokens.accentPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _world == HermesWorld.cinema ? 'Hermes Cinema' : 'Hermes Music',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          actions: [
            if (widget.onOpenSearch != null)
              IconButton(
                tooltip: 'Search library',
                icon: const Icon(Icons.search),
                onPressed: widget.onOpenSearch,
              ),
            if (widget.isAdmin && widget.onOpenAdmin != null)
              IconButton(
                tooltip: 'Server Admin',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                onPressed: widget.onOpenAdmin,
              ),
            if (widget.onOpenSettings != null)
              IconButton(
                tooltip: 'Settings & Theme',
                icon: const Icon(Icons.tune),
                onPressed: widget.onOpenSettings,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 6),
              child: Chip(
                backgroundColor: tokens.bgElevated,
                side: const BorderSide(color: Color(0x1FFFFFFF)),
                label: Text(widget.username),
              ),
            ),
          ],
        );

        final contentColumn = Column(
          children: [
            Expanded(child: activeView),
            if (widget.miniPlayerBuilder != null)
              SafeArea(
                top: false,
                child: widget.miniPlayerBuilder!(context),
              ),
          ],
        );

        if (isDesktop) {
          return Scaffold(
            appBar: topBar,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: tokens.bgElevated,
                  selectedIndex: _world.index,
                  onDestinationSelected: (idx) => setState(() => _world = HermesWorld.values[idx]),
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: tokens.accentPrimary.withValues(alpha: 0.22),
                  selectedIconTheme: IconThemeData(color: tokens.accentPrimary),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.movie_outlined),
                      selectedIcon: Icon(Icons.movie),
                      label: Text('Cinema'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music),
                      label: Text('Music'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: contentColumn),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: topBar,
          body: contentColumn,
          bottomNavigationBar: NavigationBar(
            backgroundColor: tokens.bgElevated,
            indicatorColor: tokens.accentPrimary.withValues(alpha: 0.22),
            selectedIndex: _world.index,
            onDestinationSelected: (idx) => setState(() => _world = HermesWorld.values[idx]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: 'Cinema',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Music',
              ),
            ],
          ),
        );
      },
    );
  }
}
