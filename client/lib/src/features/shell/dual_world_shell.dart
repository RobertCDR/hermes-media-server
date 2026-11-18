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
    this.onOpenAdmin,
    this.onOpenSettings,
    this.onOpenAccountSettings,
    this.onSwitchServer,
    this.onSignOut,
    this.onTogglePlayPause,
    this.onNextTrack,
    this.onPreviousTrack,
    this.onToggleMute,
    this.initialWorld = HermesWorld.cinema,
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
  final VoidCallback? onOpenAdmin;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAccountSettings;
  final VoidCallback? onSwitchServer;
  final VoidCallback? onSignOut;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback? onNextTrack;
  final VoidCallback? onPreviousTrack;
  final VoidCallback? onToggleMute;
  final HermesWorld initialWorld;

  @override
  State<DualWorldShell> createState() => _DualWorldShellState();
}

class _DualWorldShellState extends State<DualWorldShell> {
  late HermesWorld _world;
  bool _popoverOpen = false;
  final FocusNode _shellFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _world = widget.worldNotifier?.value ?? widget.initialWorld;
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

    if (_isTextInputFocused()) {
      return KeyEventResult.ignored;
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
    if ((key == LogicalKeyboardKey.mediaTrackNext ||
            (hw.isAltPressed && key == LogicalKeyboardKey.arrowRight)) &&
        widget.onNextTrack != null) {
      widget.onNextTrack!();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.mediaTrackPrevious ||
            (hw.isAltPressed && key == LogicalKeyboardKey.arrowLeft)) &&
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
      });
    }
  }

  void _selectWorld(HermesWorld world) {
    setState(() {
      _popoverOpen = false;
      if (world == HermesWorld.admin && widget.adminBuilder == null) {
        widget.onOpenAdmin?.call();
        return;
      }
      if (world == HermesWorld.settings && widget.settingsBuilder == null) {
        widget.onOpenSettings?.call();
        return;
      }
      _world = world;
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
      } else if (!accountTab) {
        widget.onOpenSettings?.call();
      }
    });
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;

        if (isDesktop) {
          return Focus(
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
          );
        }

        // Mobile / compact viewport
        final mobileWorlds = <HermesWorld>[
          HermesWorld.cinema,
          HermesWorld.music,
          if (widget.isAdmin) HermesWorld.admin,
          HermesWorld.settings,
        ];
        final selectedIndex = mobileWorlds.indexOf(_world).clamp(0, mobileWorlds.length - 1);

        return Scaffold(
          backgroundColor: tokens.bg,
          body: SafeArea(
            bottom: false,
            child: _buildActiveWorld(context),
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
                  selectedIndex: selectedIndex,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) {
                    _selectWorld(mobileWorlds[index]);
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.movie_outlined, color: tokens.text3),
                      selectedIcon: Icon(Icons.movie_rounded, color: tokens.accent),
                      label: 'Cinema',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.music_note_outlined, color: tokens.text3),
                      selectedIcon: Icon(Icons.music_note_rounded, color: tokens.accent),
                      label: 'Music',
                    ),
                    if (widget.isAdmin)
                      NavigationDestination(
                        icon: Icon(Icons.dns_outlined, color: tokens.text3),
                        selectedIcon: Icon(Icons.dns_rounded, color: tokens.accent),
                        label: 'Server',
                      ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined, color: tokens.text3),
                      selectedIcon: Icon(Icons.settings_rounded, color: tokens.accent),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
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
