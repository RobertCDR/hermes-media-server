import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_icons.dart';

enum HermesWorld { cinema, music, admin, settings }

class DualWorldShell extends StatefulWidget {
  const DualWorldShell({
    super.key,
    required this.username,
    required this.isAdmin,
    required this.cinemaBuilder,
    required this.musicBuilder,
    this.serverName = 'Hermes Home',
    this.endpointLabel,
    this.adminBuilder,
    this.settingsBuilder,
    this.miniPlayerBuilder,
    this.sidePanelBuilder,
    this.floatingOverlayBuilder,
    this.worldNotifier,
    this.onOpenSearch,
    this.onOpenSettings,
    this.onOpenAccountSettings,
    this.onSwitchServer,
    this.onSignOut,
    this.onTogglePlayPause,
    this.onNextTrack,
    this.onPreviousTrack,
    this.onToggleMute,
    this.initialWorld = HermesWorld.cinema,
    this.activeMobileTabIndex = 0,
    this.onSelectMobileTab,
    this.onHandleBack,
    this.onHandleForward,
    this.onToggleFullscreen,
    this.onOpenShortcuts,
    this.onMediaKeyAction,
  });

  final String username;
  final bool isAdmin;
  final WidgetBuilder cinemaBuilder;
  final WidgetBuilder musicBuilder;
  final String serverName;
  final String? endpointLabel;
  final WidgetBuilder? adminBuilder;
  final WidgetBuilder? settingsBuilder;
  final WidgetBuilder? miniPlayerBuilder;
  final WidgetBuilder? sidePanelBuilder;
  final WidgetBuilder? floatingOverlayBuilder;
  final ValueNotifier<HermesWorld>? worldNotifier;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAccountSettings;
  final VoidCallback? onSwitchServer;
  final VoidCallback? onSignOut;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onNextTrack;
  final VoidCallback? onPreviousTrack;
  final VoidCallback? onToggleMute;
  final HermesWorld initialWorld;
  final int activeMobileTabIndex;
  final ValueChanged<int>? onSelectMobileTab;
  final bool Function()? onHandleBack;
  final bool Function()? onHandleForward;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onOpenShortcuts;
  final ValueChanged<String>? onMediaKeyAction;

  @override
  State<DualWorldShell> createState() => _DualWorldShellState();
}

class _DualWorldShellState extends State<DualWorldShell> {
  late HermesWorld _world;
  late HermesWorld _lastContentWorld;
  bool _popoverOpen = false;
  final FocusNode _shellFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _world = widget.worldNotifier?.value ?? widget.initialWorld;
    _lastContentWorld =
        (_world == HermesWorld.music || _world == HermesWorld.cinema)
            ? _world
            : HermesWorld.cinema;
    widget.worldNotifier?.addListener(_syncWorldFromNotifier);
  }

  @override
  void didUpdateWidget(covariant DualWorldShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.worldNotifier != widget.worldNotifier) {
      oldWidget.worldNotifier?.removeListener(_syncWorldFromNotifier);
      widget.worldNotifier?.addListener(_syncWorldFromNotifier);
      if (widget.worldNotifier != null) {
        _world = widget.worldNotifier!.value;
        if (_world == HermesWorld.music || _world == HermesWorld.cinema) {
          _lastContentWorld = _world;
        }
      }
    }
  }

  @override
  void dispose() {
    widget.worldNotifier?.removeListener(_syncWorldFromNotifier);
    _shellFocusNode.dispose();
    super.dispose();
  }

  bool _isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleGlobalKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrlOrMeta = hw.isControlPressed || hw.isMetaPressed;

    if (ctrlOrMeta && key == LogicalKeyboardKey.keyK) {
      widget.onOpenSearch?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && _popoverOpen) {
      setState(() => _popoverOpen = false);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f11 && widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.browserBack && widget.onHandleBack != null) {
      if (widget.onHandleBack!()) return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.browserForward &&
        widget.onHandleForward != null) {
      if (widget.onHandleForward!()) return KeyEventResult.handled;
    }

    // Hardware media keys work even while a text input is focused.
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      widget.onTogglePlayPause?.call();
      widget.onMediaKeyAction?.call('playPause');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      widget.onNextTrack?.call();
      widget.onMediaKeyAction?.call('next');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      widget.onPreviousTrack?.call();
      widget.onMediaKeyAction?.call('previous');
      return KeyEventResult.handled;
    }

    if (_isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.slash && hw.isShiftPressed) {
      if (widget.onOpenShortcuts != null) {
        widget.onOpenShortcuts!();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.slash) {
      widget.onOpenSearch?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && widget.onTogglePlayPause != null) {
      widget.onTogglePlayPause!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM && widget.onToggleMute != null) {
      widget.onToggleMute!();
      return KeyEventResult.handled;
    }
    if (((hw.isAltPressed || ctrlOrMeta) &&
            key == LogicalKeyboardKey.arrowRight) &&
        widget.onNextTrack != null) {
      widget.onNextTrack!();
      return KeyEventResult.handled;
    }
    if (((hw.isAltPressed || ctrlOrMeta) &&
            key == LogicalKeyboardKey.arrowLeft) &&
        widget.onPreviousTrack != null) {
      widget.onPreviousTrack!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _syncWorldFromNotifier() {
    final target = widget.worldNotifier?.value;
    if (target != null && target != _world && mounted) {
      setState(() {
        _popoverOpen = false;
        _world = target;
        if (target == HermesWorld.music || target == HermesWorld.cinema) {
          _lastContentWorld = target;
        }
      });
    }
  }

  void _selectWorld(HermesWorld world) {
    setState(() {
      _popoverOpen = false;
      if (world == HermesWorld.settings && widget.settingsBuilder == null) {
        widget.onOpenSettings?.call();
        return;
      }
      _world = world;
      if (world == HermesWorld.music || world == HermesWorld.cinema) {
        _lastContentWorld = world;
      }
      widget.worldNotifier?.value = world;
    });
  }

  void _openSettings({required bool accountTab}) {
    setState(() {
      _popoverOpen = false;
      if (accountTab) {
        widget.onOpenAccountSettings?.call();
      } else {
        widget.onOpenSettings?.call();
      }
      if (widget.settingsBuilder != null) {
        _world = HermesWorld.settings;
        widget.worldNotifier?.value = HermesWorld.settings;
      } else if (!accountTab) {
        widget.onOpenSettings?.call();
      }
    });
  }

  void _handleSystemBack() {
    if (_popoverOpen) {
      setState(() => _popoverOpen = false);
      return;
    }
    if (_world == HermesWorld.settings || _world == HermesWorld.admin) {
      _selectWorld(_lastContentWorld);
      return;
    }
    if (widget.onHandleBack?.call() == true) {
      return;
    }
    if (widget.activeMobileTabIndex != 0 && widget.onSelectMobileTab != null) {
      widget.onSelectMobileTab!(0);
      return;
    }
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    unawaited(SystemNavigator.pop());
  }

  String get _avatarInitial {
    final trimmed = widget.username.trim();
    if (trimmed.isEmpty) return 'H';
    return trimmed[0].toUpperCase();
  }

  Widget _buildActiveWorld(BuildContext context) {
    return switch (_world) {
      HermesWorld.cinema => widget.cinemaBuilder(context),
      HermesWorld.music => widget.musicBuilder(context),
      HermesWorld.admin =>
        widget.adminBuilder?.call(context) ?? widget.cinemaBuilder(context),
      HermesWorld.settings =>
        widget.settingsBuilder?.call(context) ?? widget.cinemaBuilder(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final miniPlayer = widget.miniPlayerBuilder?.call(context);
    final sidePanel = widget.sidePanelBuilder?.call(context);
    final floatingOverlay = widget.floatingOverlayBuilder?.call(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleSystemBack();
        }
      },
      child: LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;

        if (isDesktop) {
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if ((event.buttons & kBackMouseButton) != 0) {
                widget.onHandleBack?.call();
              } else if ((event.buttons & kForwardMouseButton) != 0) {
                widget.onHandleForward?.call();
              }
            },
            child: Focus(
              focusNode: _shellFocusNode,
              autofocus: true,
              onKeyEvent: _handleGlobalKeyEvent,
              child: Scaffold(
              backgroundColor: tokens.bg,
              body: Stack(
                children: [
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _ObsidianRail(
                            activeWorld: _world,
                            isAdmin: widget.isAdmin,
                            avatarInitial: _avatarInitial,
                            popoverOpen: _popoverOpen,
                            onBrandTap: () => _selectWorld(HermesWorld.cinema),
                            onSelectWorld: _selectWorld,
                            onTogglePopover: () {
                              setState(() => _popoverOpen = !_popoverOpen);
                            },
                          ),
                          Expanded(
                            child: Container(
                              color: tokens.bg,
                              child: _buildActiveWorld(context),
                            ),
                          ),
                          ?sidePanel,
                        ],
                      ),
                    ),
                    ?miniPlayer,
                  ],
                ),
                ?floatingOverlay,
                if (_popoverOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _popoverOpen = false),
                    ),
                  ),
                  Positioned(
                    left: 82,
                    bottom: miniPlayer != null ? 92 : 16,
                    child: _AccountPopover(
                      username: widget.username,
                      isAdmin: widget.isAdmin,
                      serverName: widget.serverName,
                      endpointLabel: widget.endpointLabel,
                      onAccountSettings: () => _openSettings(accountTab: true),
                      onSwitchServer: () {
                        setState(() => _popoverOpen = false);
                        widget.onSwitchServer?.call();
                      },
                      onSignOut: () {
                        setState(() => _popoverOpen = false);
                        widget.onSignOut?.call();
                      },
                    ),
                  ),
                ],
              ],
            ),
            ),
            ),
          );
        }

        // Mobile / compact viewport
        final activeContentWorld =
            (_world == HermesWorld.music || _world == HermesWorld.cinema)
                ? _world
                : _lastContentWorld;
        final showOverlayBack =
            _world == HermesWorld.settings || _world == HermesWorld.admin;
        final activeWorldWidget = _buildActiveWorld(context);
        final topChromeClearance = MediaQuery.paddingOf(context).top + 54;

        return Scaffold(
          backgroundColor: tokens.bg,
          body: Stack(
            children: [
              Positioned.fill(
                child: showOverlayBack
                    ? Padding(
                        padding: EdgeInsets.only(top: topChromeClearance),
                        child: activeWorldWidget,
                      )
                    : activeWorldWidget,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _MobileTopBar(
                    activeWorld: activeContentWorld,
                    showBack: showOverlayBack,
                    avatarInitial: _avatarInitial,
                    onBackFromOverlay: () => _selectWorld(_lastContentWorld),
                    onToggleWorld: () => _selectWorld(
                      activeContentWorld == HermesWorld.music
                          ? HermesWorld.cinema
                          : HermesWorld.music,
                    ),
                    onOpenAccountMenu: () =>
                        unawaited(_openMobileAccountSheet(context)),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?miniPlayer,
              Container(
                decoration: BoxDecoration(
                  color: tokens.bgRail,
                  border: Border(top: BorderSide(color: tokens.lineSoft)),
                ),
                child: NavigationBar(
                  height: 64,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor: tokens.accent.withValues(alpha: 0.16),
                  selectedIndex: widget.activeMobileTabIndex.clamp(0, 2),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) {
                    if (_world == HermesWorld.settings ||
                        _world == HermesWorld.admin) {
                      _selectWorld(_lastContentWorld);
                    }
                    widget.onSelectMobileTab?.call(index);
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined, color: tokens.text3),
                      selectedIcon: Icon(
                        Icons.home_rounded,
                        color: tokens.accent,
                      ),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_outlined, color: tokens.text3),
                      selectedIcon: Icon(
                        Icons.search_rounded,
                        color: tokens.accent,
                      ),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        activeContentWorld == HermesWorld.music
                            ? Icons.library_music_outlined
                            : Icons.video_library_outlined,
                        color: tokens.text3,
                      ),
                      selectedIcon: Icon(
                        activeContentWorld == HermesWorld.music
                            ? Icons.library_music_rounded
                            : Icons.video_library_rounded,
                        color: tokens.accent,
                      ),
                      label: 'Library',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Future<void> _openMobileAccountSheet(BuildContext ctx) async {
    final tokens = HermesThemeTokens.of(ctx);
    final roleLabel = widget.isAdmin ? 'Owner' : 'Member';
    final connectionText =
        widget.endpointLabel != null && widget.endpointLabel!.isNotEmpty
            ? '${widget.serverName} · ${widget.endpointLabel}'
            : widget.serverName;

    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: tokens.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Container(
          key: const Key('mobile-account-sheet'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.username} · $roleLabel',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connectionText,
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 12,
                        color: tokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.line),
              const SizedBox(height: 6),
              _PopoverActionRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openSettings(accountTab: false);
                },
              ),
              _PopoverActionRow(
                icon: Icons.person_outline_rounded,
                label: 'Account settings',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openSettings(accountTab: true);
                },
              ),
              if (widget.isAdmin)
                _PopoverActionRow(
                  icon: Icons.dns_outlined,
                  label: 'Server dashboard',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _selectWorld(HermesWorld.admin);
                  },
                ),
              _PopoverActionRow(
                icon: Icons.swap_horiz_rounded,
                label: 'Switch server / Setup UI',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  widget.onSwitchServer?.call();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1, thickness: 1, color: tokens.line),
              ),
              _PopoverActionRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  widget.onSignOut?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.activeWorld,
    required this.showBack,
    required this.avatarInitial,
    required this.onBackFromOverlay,
    required this.onToggleWorld,
    required this.onOpenAccountMenu,
  });

  final HermesWorld activeWorld;
  final bool showBack;
  final String avatarInitial;
  final VoidCallback onBackFromOverlay;
  final VoidCallback onToggleWorld;
  final VoidCallback onOpenAccountMenu;

  static const _floatingDecoration = BoxShadow(
    color: Color(0x55000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final floatingSurface = tokens.bg.withValues(alpha: 0.78);
    final floatingBorder = Colors.white.withValues(alpha: 0.16);
    final toggleTargetLabel = activeWorld == HermesWorld.music
        ? 'Switch to Cinema'
        : 'Switch to Music';

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (showBack) ...[
              Container(
                decoration: BoxDecoration(
                  color: floatingSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: floatingBorder),
                  boxShadow: const [_floatingDecoration],
                ),
                child: IconButton(
                  key: const Key('mobile-overlay-back-btn'),
                  tooltip: 'Back',
                  visualDensity: VisualDensity.compact,
                  onPressed: onBackFromOverlay,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: tokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Tooltip(
              message: toggleTargetLabel,
              child: Container(
                decoration: BoxDecoration(
                  color: floatingSurface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: floatingBorder),
                  boxShadow: const [_floatingDecoration],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('mobile-world-pill'),
                    onTap: onToggleWorld,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WorldPillSegment(
                            segmentKey: const Key('mobile-world-pill-music'),
                            icon: Icons.music_note_rounded,
                            selected: activeWorld == HermesWorld.music,
                          ),
                          const SizedBox(width: 2),
                          _WorldPillSegment(
                            segmentKey: const Key('mobile-world-pill-cinema'),
                            icon: Icons.movie_rounded,
                            selected: activeWorld == HermesWorld.cinema,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Tooltip(
              message: 'Account & Server',
              child: InkWell(
                key: const Key('mobile-account-btn'),
                onTap: onOpenAccountMenu,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: floatingSurface,
                    border: Border.all(color: floatingBorder),
                    boxShadow: const [_floatingDecoration],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    avatarInitial,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tokens.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldPillSegment extends StatelessWidget {
  const _WorldPillSegment({
    required this.segmentKey,
    required this.icon,
    required this.selected,
  });

  final Key segmentKey;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return AnimatedContainer(
      key: segmentKey,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 36,
      height: 30,
      decoration: BoxDecoration(
        color: selected ? tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        icon,
        size: 18,
        color: selected ? tokens.accentInk : tokens.text2,
      ),
    );
  }
}

class _ObsidianRail extends StatelessWidget {
  const _ObsidianRail({
    required this.activeWorld,
    required this.isAdmin,
    required this.avatarInitial,
    required this.popoverOpen,
    required this.onBrandTap,
    required this.onSelectWorld,
    required this.onTogglePopover,
  });

  final HermesWorld activeWorld;
  final bool isAdmin;
  final String avatarInitial;
  final bool popoverOpen;
  final VoidCallback onBrandTap;
  final ValueChanged<HermesWorld> onSelectWorld;
  final VoidCallback onTogglePopover;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Container(
      width: 76,
      color: tokens.bgRail,
      padding: const EdgeInsets.only(top: 18, bottom: 16),
      child: Column(
        children: [
          Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: 'Hermes Home',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onBrandTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: HermesMarkIcon(size: 24, color: tokens.accent),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _RailDestinationButton(
            label: 'Cinema',
            icon: Icons.movie_outlined,
            selectedIcon: Icons.movie_rounded,
            selected: activeWorld == HermesWorld.cinema,
            onTap: () => onSelectWorld(HermesWorld.cinema),
          ),
          const SizedBox(height: 2),
          _RailDestinationButton(
            label: 'Music',
            icon: Icons.music_note_outlined,
            selectedIcon: Icons.music_note_rounded,
            selected: activeWorld == HermesWorld.music,
            onTap: () => onSelectWorld(HermesWorld.music),
          ),
          const Spacer(),
          if (isAdmin) ...[
            _RailDestinationButton(
              label: 'Server',
              icon: Icons.dns_outlined,
              selectedIcon: Icons.dns_rounded,
              selected: activeWorld == HermesWorld.admin,
              onTap: () => onSelectWorld(HermesWorld.admin),
            ),
            const SizedBox(height: 2),
          ],
          _RailDestinationButton(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            selected: activeWorld == HermesWorld.settings,
            onTap: () => onSelectWorld(HermesWorld.settings),
          ),
          const SizedBox(height: 14),
          Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: 'Account and server',
            child: InkWell(
              key: const Key('rail-avatar-button'),
              customBorder: const CircleBorder(),
              onTap: onTogglePopover,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.accent,
                  boxShadow: popoverOpen
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.35),
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  avatarInitial,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: tokens.accentInk,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailDestinationButton extends StatefulWidget {
  const _RailDestinationButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailDestinationButton> createState() => _RailDestinationButtonState();
}

class _RailDestinationButtonState extends State<_RailDestinationButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final textColor = (widget.selected || _hovered) ? tokens.text : tokens.text3;
    final iconColor = widget.selected
        ? tokens.accent
        : (_hovered ? tokens.text : tokens.text3);

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      excludeSemantics: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.selected)
                  Positioned(
                    left: 0,
                    child: Container(
                      width: 3,
                      height: 22,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 58,
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: _hovered && !widget.selected
                        ? tokens.surface.withValues(alpha: 0.65)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.selected ? widget.selectedIcon : widget.icon,
                        size: 22,
                        color: iconColor,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountPopover extends StatelessWidget {
  const _AccountPopover({
    required this.username,
    required this.isAdmin,
    required this.serverName,
    this.endpointLabel,
    required this.onAccountSettings,
    required this.onSwitchServer,
    required this.onSignOut,
  });

  final String username;
  final bool isAdmin;
  final String serverName;
  final String? endpointLabel;
  final VoidCallback onAccountSettings;
  final VoidCallback onSwitchServer;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final roleLabel = isAdmin ? 'Owner' : 'Member';
    final connectionText = endpointLabel != null && endpointLabel!.isNotEmpty
        ? '$serverName · $endpointLabel'
        : serverName;

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('account-popover'),
        width: 248,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$username · $roleLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF3ECF72),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          connectionText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 12,
                            color: tokens.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _PopoverActionRow(
              icon: Icons.person_outline_rounded,
              label: 'Account settings',
              onTap: onAccountSettings,
            ),
            _PopoverActionRow(
              icon: Icons.dns_outlined,
              label: 'Switch server / Setup UI',
              onTap: onSwitchServer,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1, thickness: 1, color: tokens.line),
            ),
            _PopoverActionRow(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              onTap: onSignOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _PopoverActionRow extends StatelessWidget {
  const _PopoverActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      hoverColor: tokens.surface3,
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tokens.text2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
