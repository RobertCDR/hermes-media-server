import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../../core/settings/hermes_preferences.dart';
import '../../core/storage/hermes_cache_manager.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_icons.dart';
import '../../core/window/hermes_desktop_titlebar.dart';
import '../cinema/cinema_models.dart';
import '../cinema/hermes_video_player.dart';
import '../music/music_models.dart';

bool get _isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

enum SettingsTabKind { device, account }

typedef ChangePasswordCallback = Future<void> Function(
  String currentPassword,
  String newPassword,
);

class PlayerAndThemeSettingsScreen extends StatefulWidget {
  const PlayerAndThemeSettingsScreen({
    super.key,
    required this.tokens,
    required this.rendererBackend,
    required this.defaultVideoQuality,
    required this.onThemeChanged,
    required this.onRendererChanged,
    required this.onDefaultVideoQualityChanged,
    this.audioQualityPolicy = const AudioQualityPolicy(),
    this.onAudioQualityPolicyChanged,
    this.devicePreferences,
    this.accountPreferences = const HermesAccountPreferences(),
    this.username = 'hermes-user',
    this.deviceName = 'This device',
    this.initialTab = SettingsTabKind.device,
    this.onDevicePreferencesChanged,
    this.onAccountPreferencesChanged,
    this.onChangePassword,
    this.onSwitchServer,
    this.onSignOut,
    this.cacheManager,
    this.onClearCatalogCaches,
  });

  final HermesThemeTokens tokens;
  final VideoRendererBackend rendererBackend;
  final VideoQualityPreset defaultVideoQuality;
  final ValueChanged<HermesThemeTokens> onThemeChanged;
  final ValueChanged<VideoRendererBackend> onRendererChanged;
  final ValueChanged<VideoQualityPreset> onDefaultVideoQualityChanged;
  final AudioQualityPolicy audioQualityPolicy;
  final ValueChanged<AudioQualityPolicy>? onAudioQualityPolicyChanged;
  final HermesDevicePreferences? devicePreferences;
  final HermesAccountPreferences accountPreferences;
  final String username;
  final String deviceName;
  final SettingsTabKind initialTab;
  final ValueChanged<HermesDevicePreferences>? onDevicePreferencesChanged;
  final ValueChanged<HermesAccountPreferences>? onAccountPreferencesChanged;
  final ChangePasswordCallback? onChangePassword;
  final VoidCallback? onSwitchServer;
  final VoidCallback? onSignOut;
  final HermesCacheManager? cacheManager;
  final VoidCallback? onClearCatalogCaches;

  @override
  State<PlayerAndThemeSettingsScreen> createState() =>
      _PlayerAndThemeSettingsScreenState();
}

class _PlayerAndThemeSettingsScreenState
    extends State<PlayerAndThemeSettingsScreen> {
  late SettingsTabKind _activeTab;
  late HermesDevicePreferences _devicePrefs;
  late HermesAccountPreferences _accountPrefs;
  late final HermesCacheManager _cacheManager;
  HermesCacheSnapshot? _cacheSnapshot;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _devicePrefs = _buildInitialDevicePrefs();
    _accountPrefs = widget.accountPreferences;
    _cacheManager = widget.cacheManager ?? HermesCacheManager();
    unawaited(_refreshCacheSnapshot());
  }

  Future<void> _refreshCacheSnapshot() async {
    final snapshot = await _cacheManager.inspect(capMb: _devicePrefs.cacheCapMb);
    if (!mounted) return;
    setState(() => _cacheSnapshot = snapshot);
  }

  Future<void> _handleClearCache() async {
    setState(() => _clearingCache = true);
    try {
      final updated = await _cacheManager.clearAll(
        capMb: _devicePrefs.cacheCapMb,
        onClearCatalogCaches: widget.onClearCatalogCaches,
      );
      if (!mounted) return;
      setState(() {
        _cacheSnapshot = updated;
        _clearingCache = false;
      });
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Cache cleared'),
            duration: Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (mounted) {
        setState(() => _clearingCache = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PlayerAndThemeSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _activeTab = widget.initialTab;
    }
    if (widget.devicePreferences != oldWidget.devicePreferences ||
        widget.tokens != oldWidget.tokens ||
        widget.rendererBackend != oldWidget.rendererBackend ||
        widget.defaultVideoQuality != oldWidget.defaultVideoQuality ||
        widget.audioQualityPolicy != oldWidget.audioQualityPolicy) {
      _devicePrefs = _buildInitialDevicePrefs();
    }
    if (widget.accountPreferences != oldWidget.accountPreferences) {
      _accountPrefs = widget.accountPreferences;
    }
  }

  HermesDevicePreferences _buildInitialDevicePrefs() {
    final explicit = widget.devicePreferences;
    if (explicit != null) {
      return explicit;
    }
    return HermesDevicePreferences(
      themeId: widget.tokens.themeId,
      pureBlack: widget.tokens.pureBlack,
      defaultVideoQuality: widget.defaultVideoQuality,
      rendererBackend: widget.rendererBackend,
      wifiAudioPreset: widget.audioQualityPolicy.wifiPreset,
      cellularAudioPreset: widget.audioQualityPolicy.cellularPreset,
    );
  }

  void _updateDevicePrefs(HermesDevicePreferences next) {
    final prevTokens = _devicePrefs.toThemeTokens();
    final nextTokens = next.toThemeTokens();

    setState(() {
      _devicePrefs = next;
    });

    widget.onDevicePreferencesChanged?.call(next);
    if (prevTokens.themeId != nextTokens.themeId ||
        prevTokens.pureBlack != nextTokens.pureBlack) {
      widget.onThemeChanged(nextTokens);
    }
    if (next.rendererBackend != widget.rendererBackend) {
      widget.onRendererChanged(next.rendererBackend);
    }
    if (next.defaultVideoQuality != widget.defaultVideoQuality) {
      widget.onDefaultVideoQualityChanged(next.defaultVideoQuality);
    }
    if (next.wifiAudioPreset != widget.audioQualityPolicy.wifiPreset ||
        next.cellularAudioPreset != widget.audioQualityPolicy.cellularPreset) {
      widget.onAudioQualityPolicyChanged?.call(next.toAudioQualityPolicy());
    }
  }

  void _updateAccountPrefs(HermesAccountPreferences next) {
    setState(() {
      _accountPrefs = next;
    });
    widget.onAccountPreferencesChanged?.call(next);
  }

  Future<void> _showChangePasswordDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onChangePassword: widget.onChangePassword,
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Password updated across your account.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _devicePrefs.toThemeTokens();

    return Material(
      color: tokens.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final horizontalPadding = isWide ? 48.0 : 20.0;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isWide ? 40 : 24,
              horizontalPadding,
              64,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.64,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: tokens.line)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SettingsUnderlineTab(
                              label: 'This device',
                              active: _activeTab == SettingsTabKind.device,
                              tokens: tokens,
                              onTap: () => setState(
                                () => _activeTab = SettingsTabKind.device,
                              ),
                            ),
                            const SizedBox(width: 28),
                            _SettingsUnderlineTab(
                              label: 'Your account',
                              active: _activeTab == SettingsTabKind.account,
                              tokens: tokens,
                              onTap: () => setState(
                                () => _activeTab = SettingsTabKind.account,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          _activeTab == SettingsTabKind.device
                              ? (_isMobilePlatform
                                  ? Icons.smartphone_rounded
                                  : Icons.laptop_mac_outlined)
                              : Icons.link_rounded,
                          size: 16,
                          color: tokens.text2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _activeTab == SettingsTabKind.device
                                ? 'Saved on ${widget.deviceName} only'
                                : 'Synced to ${widget.username} on every device',
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 13,
                              color: tokens.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_activeTab == SettingsTabKind.device)
                      _buildDeviceTab(tokens)
                    else
                      _buildAccountTab(tokens),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceTab(HermesThemeTokens tokens) {
    const videoQualityOrder = [
      VideoQualityPreset.p480,
      VideoQualityPreset.p720,
      VideoQualityPreset.p1080,
      VideoQualityPreset.directPlay,
    ];

    const audioQualityOrder = [
      AudioQualityPreset.low64,
      AudioQualityPreset.medium96,
      AudioQualityPreset.high160,
      AudioQualityPreset.veryHigh320,
      AudioQualityPreset.lossless,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSectionHeader(title: 'Appearance', tokens: tokens),
        _SettingRow(
          label: 'Theme',
          description: 'Background tone and highlight color.',
          stacked: true,
          tokens: tokens,
          control: _ThemePreviewGrid(
            selectedTheme: _devicePrefs.themeId,
            pureBlack: _devicePrefs.pureBlack,
            activeTokens: tokens,
            onSelect: (id) {
              _updateDevicePrefs(_devicePrefs.copyWith(themeId: id));
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Pure black background',
          description:
              'Turns off the tinted background. Looks best on OLED screens.',
          tokens: tokens,
          control: Switch(
            key: const Key('setting-pure-black-switch'),
            value: _devicePrefs.pureBlack,
            onChanged: (value) {
              _updateDevicePrefs(_devicePrefs.copyWith(pureBlack: value));
            },
          ),
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Accessibility', tokens: tokens),
        _SettingRow(
          label: 'Text size',
          description: 'Scales text and controls across the app.',
          tokens: tokens,
          control: HermesSegmentedControl<HermesTextSize>(
            options: HermesTextSize.values
                .map((size) => HermesSegmentOption(value: size, label: size.label))
                .toList(growable: false),
            selected: _devicePrefs.textSize,
            onChanged: (size) {
              _updateDevicePrefs(_devicePrefs.copyWith(textSize: size));
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Reduce motion',
          description: 'Turns off animations, hover zooms and trailers.',
          tokens: tokens,
          control: Switch(
            key: const Key('setting-reduce-motion-switch'),
            value: _devicePrefs.reduceMotion,
            onChanged: (value) {
              _updateDevicePrefs(_devicePrefs.copyWith(reduceMotion: value));
            },
          ),
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Video playback', tokens: tokens),
        _SettingRow(
          label: 'Stream quality',
          description:
              'Original plays the file as-is. Lower qualities are converted on the server.',
          tokens: tokens,
          control: HermesFlatDropdown<VideoQualityPreset>(
            value: _devicePrefs.defaultVideoQuality,
            options: videoQualityOrder
                .map(
                  (preset) => HermesDropdownOption(
                    value: preset,
                    label: preset == VideoQualityPreset.directPlay
                        ? 'Original (Direct Play)'
                        : preset.label,
                  ),
                )
                .toList(growable: false),
            onChanged: (quality) {
              _updateDevicePrefs(
                _devicePrefs.copyWith(defaultVideoQuality: quality),
              );
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Video renderer',
          description: _isMobilePlatform
              ? 'Hardware MediaCodec surface (Automatic) or OpenGL ES shader compositing for HDR subtitles.'
              : 'OpenGL keeps subtitles from looking washed out on HDR titles.',
          tokens: tokens,
          control: HermesSegmentedControl<VideoRendererBackend>(
            options: _isMobilePlatform
                ? const [
                    HermesSegmentOption(
                      value: VideoRendererBackend.openGl,
                      label: 'OpenGL ES',
                    ),
                    HermesSegmentOption(
                      value: VideoRendererBackend.auto,
                      label: 'MediaCodec (Auto)',
                    ),
                  ]
                : const [
                    HermesSegmentOption(
                      value: VideoRendererBackend.openGl,
                      label: 'OpenGL',
                    ),
                    HermesSegmentOption(
                      value: VideoRendererBackend.auto,
                      label: 'Automatic',
                    ),
                  ],
            selected: _devicePrefs.rendererBackend,
            onChanged: (renderer) {
              _updateDevicePrefs(
                _devicePrefs.copyWith(rendererBackend: renderer),
              );
            },
          ),
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Audio quality', tokens: tokens),
        _SettingRow(
          label: 'Wi-Fi streaming',
          description:
              'Used on your home network and over Tailscale on Wi-Fi.',
          tokens: tokens,
          control: HermesFlatDropdown<AudioQualityPreset>(
            value: _devicePrefs.wifiAudioPreset,
            options: audioQualityOrder
                .map((preset) => HermesDropdownOption(value: preset, label: preset.label))
                .toList(growable: false),
            onChanged: (preset) {
              _updateDevicePrefs(_devicePrefs.copyWith(wifiAudioPreset: preset));
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Cellular streaming',
          description: 'Higher quality uses more mobile data.',
          tokens: tokens,
          control: HermesFlatDropdown<AudioQualityPreset>(
            value: _devicePrefs.cellularAudioPreset,
            options: audioQualityOrder
                .map((preset) => HermesDropdownOption(value: preset, label: preset.label))
                .toList(growable: false),
            onChanged: (preset) {
              _updateDevicePrefs(
                _devicePrefs.copyWith(cellularAudioPreset: preset),
              );
            },
          ),
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Storage & cache', tokens: tokens),
        _SettingRow(
          label: 'Cache usage',
          description: 'Artwork images and temporary library cache stored on this device.',
          stacked: true,
          tokens: tokens,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${HermesCacheManager.formatBytes(_cacheSnapshot?.totalBytes ?? 0)} used of ${HermesCacheManager.formatCapMb(_devicePrefs.cacheCapMb)}',
                key: const Key('cache-size-label'),
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _cacheSnapshot?.usageRatio ?? 0,
                  minHeight: 5,
                  color: tokens.accent,
                  backgroundColor: tokens.surface3,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Cache size limit',
          description: 'Caps artwork memory & disk cache before older items are evicted.',
          tokens: tokens,
          control: HermesFlatDropdown<int>(
            key: const Key('cache-cap-selector'),
            value: HermesCacheManager.capOptionsMb.contains(_devicePrefs.cacheCapMb)
                ? _devicePrefs.cacheCapMb
                : 512,
            options: HermesCacheManager.capOptionsMb
                .map(
                  (mb) => HermesDropdownOption(
                    value: mb,
                    label: HermesCacheManager.formatCapMb(mb),
                  ),
                )
                .toList(growable: false),
            onChanged: (mb) {
              _cacheManager.applyCapMb(mb);
              _updateDevicePrefs(_devicePrefs.copyWith(cacheCapMb: mb));
              unawaited(_refreshCacheSnapshot());
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Clear cache',
          description: 'Frees temporary artwork and cached metadata without touching your server files.',
          tokens: tokens,
          control: OutlinedButton.icon(
            key: const Key('clear-cache-btn'),
            onPressed: _clearingCache ? null : () => unawaited(_handleClearCache()),
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(_clearingCache ? 'Clearing...' : 'Clear cache'),
          ),
        ),
        if (_isDesktopPlatform) ...[
          const SizedBox(height: 36),
          _SettingsSectionHeader(title: 'Desktop & Window', tokens: tokens),
          _SettingRow(
            label: 'Close to system tray',
            description:
                'Keeps music playing in the system tray when closing the window.',
            tokens: tokens,
            control: Switch(
              key: const Key('setting-close-to-tray-switch'),
              value: _devicePrefs.closeToTray,
              onChanged: (value) {
                _updateDevicePrefs(_devicePrefs.copyWith(closeToTray: value));
              },
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.lineSoft),
          _SettingRow(
            label: 'Media key flyout',
            description:
                'Shows a compact always-on-top track card when media keys are pressed.',
            tokens: tokens,
            control: Switch(
              key: const Key('setting-media-flyout-switch'),
              value: _devicePrefs.showMediaFlyout,
              onChanged: (value) {
                _updateDevicePrefs(
                  _devicePrefs.copyWith(showMediaFlyout: value),
                );
              },
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.lineSoft),
          _SettingRow(
            label: 'Keyboard & mouse shortcuts',
            description:
                'View global, playback, Mouse 4/5 navigation, and video hotkeys.',
            tokens: tokens,
            control: OutlinedButton.icon(
              key: const Key('setting-shortcuts-btn'),
              onPressed: () =>
                  unawaited(showHermesKeyboardShortcutsDialog(context)),
              icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
              label: const Text('View shortcuts'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAccountTab(HermesThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSectionHeader(title: 'Playback', tokens: tokens),
        _SettingRow(
          label: 'Autoplay next episode',
          description:
              'Starts the next episode after a 20-second countdown during the credits.',
          tokens: tokens,
          control: Switch(
            key: const Key('setting-autoplay-switch'),
            value: _accountPrefs.autoplayNextEpisode,
            onChanged: (value) {
              _updateAccountPrefs(
                _accountPrefs.copyWith(autoplayNextEpisode: value),
              );
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Normalize volume',
          description: 'Plays every song at roughly the same loudness.',
          tokens: tokens,
          control: Switch(
            key: const Key('setting-normalize-switch'),
            value: _accountPrefs.normalizeVolume,
            onChanged: (value) {
              _updateAccountPrefs(
                _accountPrefs.copyWith(normalizeVolume: value),
              );
            },
          ),
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Subtitles', tokens: tokens),
        _SettingRow(
          label: 'Size',
          description: '',
          tokens: tokens,
          control: HermesSegmentedControl<SubtitleSizePreset>(
            options: SubtitleSizePreset.values
                .map((preset) => HermesSegmentOption(value: preset, label: preset.label))
                .toList(growable: false),
            selected: _accountPrefs.subtitleSize,
            onChanged: (size) {
              _updateAccountPrefs(_accountPrefs.copyWith(subtitleSize: size));
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.lineSoft),
        _SettingRow(
          label: 'Background',
          description:
              'A background keeps subtitles readable over bright scenes.',
          tokens: tokens,
          control: HermesSegmentedControl<SubtitleBackgroundStyle>(
            options: SubtitleBackgroundStyle.values
                .map((bg) => HermesSegmentOption(value: bg, label: bg.label))
                .toList(growable: false),
            selected: _accountPrefs.subtitleBackground,
            onChanged: (bg) {
              _updateAccountPrefs(
                _accountPrefs.copyWith(subtitleBackground: bg),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _SubtitlePreviewBox(
          tokens: tokens,
          subtitleSize: _accountPrefs.subtitleSize,
          subtitleBackground: _accountPrefs.subtitleBackground,
        ),
        const SizedBox(height: 36),
        _SettingsSectionHeader(title: 'Colors', tokens: tokens),
        _SettingRow(
          label: 'Match title colors',
          description:
              'Title pages and the player use each movie or show\'s own color instead of your theme\'s.',
          tokens: tokens,
          control: Switch(
            key: const Key('setting-match-title-colors-switch'),
            value: _accountPrefs.matchTitleColors,
            onChanged: (value) {
              _updateAccountPrefs(
                _accountPrefs.copyWith(matchTitleColors: value),
              );
            },
          ),
        ),
        if (widget.onChangePassword != null ||
            widget.onSwitchServer != null ||
            widget.onSignOut != null) ...[
          const SizedBox(height: 36),
          _SettingsSectionHeader(title: 'Account & server', tokens: tokens),
          if (widget.onChangePassword != null) ...[
            _SettingRow(
              label: 'Password',
              description: 'Change your password for ${widget.username}.',
              tokens: tokens,
              control: OutlinedButton(
                onPressed: _showChangePasswordDialog,
                child: const Text('Change password'),
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.lineSoft),
          ],
          if (widget.onSwitchServer != null) ...[
            _SettingRow(
              label: 'Server connection',
              description: 'Connect to another Hermes server or re-run setup.',
              tokens: tokens,
              control: OutlinedButton(
                onPressed: widget.onSwitchServer,
                child: const Text('Switch server'),
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.lineSoft),
          ],
          if (widget.onSignOut != null)
            _SettingRow(
              label: 'Session',
              description: 'Sign out of ${widget.username} on this device.',
              tokens: tokens,
              control: OutlinedButton(
                onPressed: widget.onSignOut,
                child: const Text('Sign out'),
              ),
            ),
        ],
      ],
    );
  }
}

class _SettingsUnderlineTab extends StatelessWidget {
  const _SettingsUnderlineTab({
    required this.label,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool active;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? tokens.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: active ? tokens.text : tokens.text2,
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
    required this.tokens,
  });

  final String title;
  final HermesThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Figtree',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: tokens.text,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.description,
    required this.control,
    required this.tokens,
    this.stacked = false,
  });

  final String label;
  final String description;
  final Widget control;
  final HermesThemeTokens tokens;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tokens.text,
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              description,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13,
                color: tokens.text2,
              ),
            ),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStacked = stacked || constraints.maxWidth < 560;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: useStacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textColumn,
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerLeft, child: control),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: textColumn,
                      ),
                    ),
                    control,
                  ],
                ),
        );
      },
    );
  }
}

class _ThemePreviewGrid extends StatelessWidget {
  const _ThemePreviewGrid({
    required this.selectedTheme,
    required this.pureBlack,
    required this.activeTokens,
    required this.onSelect,
  });

  final HermesThemeId selectedTheme;
  final bool pureBlack;
  final HermesThemeTokens activeTokens;
  final ValueChanged<HermesThemeId> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = (constraints.maxWidth / 160).floor().clamp(2, 4);
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: HermesThemeId.values.map((id) {
            final preview = HermesThemeTokens.resolve(
              themeId: id,
              pureBlack: pureBlack,
            );
            final isSelected = id == selectedTheme;

            return SizedBox(
              width: cardWidth,
              child: Semantics(
                container: true,
                button: true,
                selected: isSelected,
                excludeSemantics: true,
                label: '${id.label} theme',
                child: InkWell(
                  key: Key('theme-card-${id.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(id),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    decoration: BoxDecoration(
                      color: activeTokens.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? activeTokens.text : activeTokens.line,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MiniThemeUiPreview(preview: preview),
                        const SizedBox(height: 9),
                        Text(
                          id.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: activeTokens.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _MiniThemeUiPreview extends StatelessWidget {
  const _MiniThemeUiPreview({required this.preview});

  final HermesThemeTokens preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: preview.bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 12,
                  decoration: BoxDecoration(
                    color: preview.bgRail,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  padding: const EdgeInsets.only(top: 4),
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: preview.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.4,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: preview.text.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: Row(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: 4),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: Container(
                                      color: i == 1
                                          ? preview.surface3
                                          : preview.surface2,
                                      alignment: Alignment.bottomLeft,
                                      child: i == 0
                                          ? FractionallySizedBox(
                                              widthFactor: 0.6,
                                              child: Container(
                                                height: 2,
                                                color: preview.accent,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 12,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: preview.bgSunken,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 4,
                  decoration: BoxDecoration(
                    color: preview.text.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, barConstraints) {
                      return Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: preview.text3,
                          borderRadius: BorderRadius.circular(1),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: barConstraints.maxWidth * 0.45,
                          height: 2,
                          decoration: BoxDecoration(
                            color: preview.accent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitlePreviewBox extends StatelessWidget {
  const _SubtitlePreviewBox({
    required this.tokens,
    required this.subtitleSize,
    required this.subtitleBackground,
  });

  final HermesThemeTokens tokens;
  final SubtitleSizePreset subtitleSize;
  final SubtitleBackgroundStyle subtitleBackground;

  @override
  Widget build(BuildContext context) {
    final shadows = switch (subtitleBackground) {
      SubtitleBackgroundStyle.shadow => const [
          Shadow(
            color: Color(0xF2000000),
            offset: Offset(0, 1.5),
            blurRadius: 5,
          ),
          Shadow(
            color: Color(0xE6000000),
            offset: Offset(1, 1),
            blurRadius: 2,
          ),
        ],
      _ => null,
    };

    return Container(
      key: const Key('subtitle-preview-box'),
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: tokens.bgSunken,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/subtitle_preview_scene.jpg',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Container(
                  padding: subtitleBackground == SubtitleBackgroundStyle.box
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                      : EdgeInsets.zero,
                  decoration: subtitleBackground == SubtitleBackgroundStyle.box
                      ? BoxDecoration(
                          color: const Color(0xBF000000),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Text(
                    'We only ever found half the signal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: subtitleSize.previewFontSize,
                      fontWeight: FontWeight.w600,
                      color: tokens.subtitleSafeColor,
                      shadows: shadows,
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

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onChangePassword});

  final ChangePasswordCallback? onChangePassword;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _nextController = TextEditingController();
  String? _errorText;
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _nextController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _nextController.text;
    if (next.trim().length < 8) {
      setState(() {
        _errorText = 'New password must be at least 8 characters.';
      });
      return;
    }

    setState(() {
      _errorText = null;
      _submitting = true;
    });

    try {
      await widget.onChangePassword?.call(current, next);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final cleaned = error
          .toString()
          .replaceFirst(RegExp(r'^AuthException\s*:?\s*'), '')
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .trim();
      setState(() {
        _submitting = false;
        _errorText = cleaned.isEmpty ? 'Could not update password.' : cleaned;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.surface2,
      title: Text(
        'Change password',
        style: TextStyle(
          fontFamily: 'Figtree',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: tokens.text,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Updating your password signs out inactive refresh sessions on other devices.',
                style: TextStyle(fontSize: 13, color: tokens.text2),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _currentController,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nextController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'New password',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Color(0xFFFF6B7D),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save password'),
        ),
      ],
    );
  }
}
