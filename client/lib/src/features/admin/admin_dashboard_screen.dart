import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import 'admin_modals.dart';
import 'admin_models.dart';
import 'admin_service.dart';

/// Figma v4 `.page` Server dashboard: live Active Sessions, structured Libraries table with scan progress,
/// Needs attention unmatched files with TMDb Fix match, and People/Invites table.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.adminService,
    this.onServerNameChanged,
  });

  final AdminService adminService;
  final ValueChanged<String>? onServerNameChanged;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<LibraryRootModel> _libraries = [];
  List<ActiveStreamSessionModel> _sessions = [];
  List<UnmatchedMediaModel> _unmatched = [];
  List<InviteModel> _invites = [];
  List<UserSummaryModel> _users = [];
  ServerSettingsModel? _serverSettings;
  final TextEditingController _serverNameController =
      TextEditingController(text: 'Hermes Media Server');
  bool _transcodingEnabled = true;
  HardwareAccelerationMode _hwAccelMode = HardwareAccelerationMode.none;
  int _maxVideoTranscodes = 2;
  int _maxAudioTranscodes = 4;
  int? _maxRemoteBitrateBps;
  bool _savingSettings = false;
  final Set<String> _localScanningLibs = {};
  Timer? _scanPollTimer;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _scanPollTimer?.cancel();
    _serverNameController.dispose();
    super.dispose();
  }

  Future<T> _safeOptional<T>(Future<T> Function() loader, T fallback) async {
    try {
      return await loader();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _refresh({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final libraries = await widget.adminService.listLibraries();
      final invites = await widget.adminService.listInvites();
      final users = await widget.adminService.listUsers();
      final sessions = await _safeOptional(
        widget.adminService.listActiveSessions,
        const <ActiveStreamSessionModel>[],
      );
      final unmatched = await _safeOptional(
        widget.adminService.listUnmatchedMedia,
        const <UnmatchedMediaModel>[],
      );
      final settings = await _safeOptional<ServerSettingsModel?>(
        widget.adminService.getServerSettings,
        null,
      );

      if (!mounted) return;
      setState(() {
        _libraries = libraries;
        _invites = invites;
        _users = users;
        _sessions = sessions;
        _unmatched = unmatched;
        if (settings != null) {
          _serverSettings = settings;
          _serverNameController.text = settings.serverName;
          _transcodingEnabled = settings.transcodingEnabled;
          _hwAccelMode = settings.hardwareAccelerationMode;
          _maxVideoTranscodes = settings.maxConcurrentVideoTranscodes;
          _maxAudioTranscodes = settings.maxConcurrentAudioTranscodes;
          _maxRemoteBitrateBps = settings.maxRemoteVideoBitrateBps;
        }
        _loading = false;
        _loadError = null;
      });

      _syncScanPollTimer(libraries.any((l) => l.isScanning));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _syncScanPollTimer(bool anyScanning) {
    if (!anyScanning) {
      _scanPollTimer?.cancel();
      _scanPollTimer = null;
      return;
    }
    _scanPollTimer ??= Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_refresh(showSpinner: false)),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanLibrary(String id) async {
    setState(() => _localScanningLibs.add(id));
    try {
      final summary = await widget.adminService.scanLibrary(id);
      if (!mounted) return;
      _showToast(
        'Scan finished: ${summary.filesDiscovered} files, ${summary.sourcesUpserted} upserted.',
      );
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Scan error: $e');
    } finally {
      if (mounted) {
        setState(() => _localScanningLibs.remove(id));
      }
    }
  }

  Future<void> _scanAllLibraries() async {
    final targets = List<LibraryRootModel>.from(_libraries);
    if (targets.isEmpty) return;

    setState(() {
      for (final lib in targets) {
        _localScanningLibs.add(lib.id);
      }
    });
    try {
      var files = 0;
      var upserted = 0;
      for (final lib in targets) {
        final summary = await widget.adminService.scanLibrary(lib.id);
        files += summary.filesDiscovered;
        upserted += summary.sourcesUpserted;
      }
      _showToast('Scanned ${targets.length} libraries ($files files, $upserted upserted).');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Scan error: $e');
    } finally {
      if (mounted) {
        setState(() => _localScanningLibs.clear());
      }
    }
  }

  Future<void> _openAddLibrary() async {
    final result = await showDialog<AddLibraryResult>(
      context: context,
      builder: (_) => const AddLibraryDialog(),
    );
    if (result == null) return;

    try {
      final created = await widget.adminService.createLibrary(
        name: result.name,
        mediaType: result.mediaType,
        rootPath: result.rootPath,
        watchEnabled: result.watchEnabled,
        fetchMetadata: result.fetchMetadata,
      );
      if (!mounted) return;
      _showToast('Added "${created.name}". Scanning library...');
      await _scanLibrary(created.id);
    } catch (e) {
      _showToast('Add library error: $e');
    }
  }

  Future<void> _openEditLibrary(LibraryRootModel lib) async {
    final result = await showDialog<AddLibraryResult>(
      context: context,
      builder: (_) => AddLibraryDialog(initialLibrary: lib),
    );
    if (result == null) return;

    try {
      final updated = await widget.adminService.updateLibrary(
        id: lib.id,
        name: result.name,
        rootPath: result.rootPath,
        watchEnabled: result.watchEnabled,
        fetchMetadata: result.fetchMetadata,
      );
      if (!mounted) return;
      _showToast('Updated "${updated.name}".');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Update library error: $e');
    }
  }

  Future<void> _deleteLibrary(LibraryRootModel lib) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDeleteLibraryDialog(library: lib),
    );
    if (confirmed != true) return;

    try {
      await widget.adminService.deleteLibrary(lib.id);
      if (!mounted) return;
      _showToast('Deleted "${lib.name}".');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Delete library error: $e');
    }
  }

  Future<void> _saveServerSettings() async {
    final serverName = _serverNameController.text.trim();
    if (serverName.isEmpty) {
      _showToast('Server name cannot be empty.');
      return;
    }

    setState(() => _savingSettings = true);
    try {
      final updated = await widget.adminService.updateServerSettings(
        UpdateServerSettingsInput(
          serverName: serverName,
          transcodingEnabled: _transcodingEnabled,
          maxConcurrentVideoTranscodes: _maxVideoTranscodes,
          maxConcurrentAudioTranscodes: _maxAudioTranscodes,
          maxRemoteVideoBitrateBps: _maxRemoteBitrateBps,
          hardwareAccelerationMode: _hwAccelMode,
        ),
      );
      if (!mounted) return;
      setState(() {
        _serverSettings = updated;
        _serverNameController.text = updated.serverName;
        _transcodingEnabled = updated.transcodingEnabled;
        _hwAccelMode = updated.hardwareAccelerationMode;
        _maxVideoTranscodes = updated.maxConcurrentVideoTranscodes;
        _maxAudioTranscodes = updated.maxConcurrentAudioTranscodes;
        _maxRemoteBitrateBps = updated.maxRemoteVideoBitrateBps;
        _savingSettings = false;
      });
      widget.onServerNameChanged?.call(updated.serverName);
      _showToast('Saved server settings.');
    } catch (e) {
      if (mounted) {
        setState(() => _savingSettings = false);
      }
      _showToast('Could not save settings: $e');
    }
  }

  int get _effectiveTotalStorageBytes =>
      _serverSettings?.totalMediaSizeBytes ??
      _libraries.fold<int>(0, (sum, lib) => sum + lib.totalSizeBytes);

  Future<void> _openCreateInvite() async {
    final opts = await showDialog<CreateInviteOptions>(
      context: context,
      builder: (_) => const CreateInviteDialog(),
    );
    if (opts == null) return;

    try {
      final created = await widget.adminService.createInvite(
        maxUses: opts.maxUses,
        expiresInHours: opts.expiresInHours,
      );
      if (!mounted) return;
      await _refresh(showSpinner: false);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => InviteReadyDialog(
          invite: created,
          joinLink: _joinLinkForCode(created.code),
        ),
      );
    } catch (e) {
      _showToast('Could not create invite: $e');
    }
  }

  Future<void> _openFixMatch(UnmatchedMediaModel item) async {
    final locked = await showDialog<IdentifyMediaResult>(
      context: context,
      builder: (_) => FixMatchDialog(
        item: item,
        adminService: widget.adminService,
      ),
    );
    if (locked == null || !mounted) return;
    _showToast('Matched "${locked.title}" (TMDb ${locked.tmdbId}).');
    await _refresh(showSpinner: false);
  }

  Future<void> _stopSession(String sessionId) async {
    try {
      await widget.adminService.stopSession(sessionId);
      _showToast('Stopped stream session.');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Could not stop session: $e');
    }
  }

  Future<void> _revokeInvite(InviteModel invite) async {
    try {
      await widget.adminService.revokeInvite(invite.id);
      _showToast('Revoked invite ${invite.code}.');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Could not revoke invite: $e');
    }
  }

  Future<void> _issueResetCode(UserSummaryModel user) async {
    try {
      final reset = await widget.adminService.issueResetCode(user.id);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: reset.resetCode));
      _showToast('One-time login code for ${user.username}: ${reset.resetCode} (copied)');
    } catch (e) {
      _showToast('Could not issue reset code: $e');
    }
  }

  Future<void> _removeUser(UserSummaryModel user) async {
    try {
      await widget.adminService.deactivateUser(user.id);
      _showToast('Removed ${user.username}.');
      await _refresh(showSpinner: false);
    } catch (e) {
      _showToast('Could not remove user: $e');
    }
  }

  String _joinLinkForCode(String code) {
    final origin = widget.adminService.baseUri.origin;
    return '$origin/join/$code';
  }

  String _formatScanTime(LibraryRootModel lib) {
    final ts = lib.lastScanCompletedAtUtc?.toLocal();
    if (ts == null) return 'Never';
    final now = DateTime.now();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    if (ts.year == now.year && ts.month == now.month && ts.day == now.day) {
      return 'Today, $hh:$mm';
    }
    return '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: tokens.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: tokens.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load server admin data: $_loadError',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.text2),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.bg,
      body: RefreshIndicator(
        onRefresh: () => _refresh(showSpinner: false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 740;
            final padX = constraints.maxWidth >= 680 ? 40.0 : 18.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(padX, 32, padX, 56),
                  children: [
                    _buildHeader(tokens),
                    const SizedBox(height: 28),
                    _buildSessionsSection(tokens),
                    const SizedBox(height: 36),
                    _buildLibrariesSection(tokens, wide),
                    if (_unmatched.isNotEmpty) ...[
                      const SizedBox(height: 36),
                      _buildAttentionSection(tokens, wide),
                    ],
                    const SizedBox(height: 36),
                    _buildPeopleSection(tokens, wide),
                    const SizedBox(height: 36),
                    _buildServerSettingsSection(tokens, wide),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(HermesThemeTokens tokens) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Text(
          'Server',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.02,
            color: tokens.text,
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (_libraries.isNotEmpty)
              TextButton(
                onPressed: _localScanningLibs.isNotEmpty ? null : _scanAllLibraries,
                style: TextButton.styleFrom(
                  backgroundColor: tokens.surface2,
                  foregroundColor: tokens.text,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                ),
                child: const Text(
                  'Scan all libraries',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            FilledButton(
              onPressed: _openAddLibrary,
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.accentInk,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
              child: const Text(
                'Add library',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSessionsSection(HermesThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Now streaming',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: tokens.text,
          ),
        ),
        const SizedBox(height: 12),
        if (_sessions.isEmpty)
          Text(
            'Nobody is streaming right now.',
            style: TextStyle(fontSize: 14, color: tokens.text2),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 780;
              final itemWidth = twoCols
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final s in _sessions)
                    SizedBox(
                      width: itemWidth,
                      child: _SessionTile(
                        session: s,
                        artworkUri: widget.adminService.buildArtworkUri(s.artworkHash),
                        onStop: s.canStop ? () => unawaited(_stopSession(s.sessionId)) : null,
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildLibrariesSection(HermesThemeTokens tokens, bool wide) {
    final thStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: tokens.text2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Libraries',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tokens.text,
              ),
            ),
            if (_libraries.isNotEmpty)
              Text(
                'Total storage: ${formatStorageBytes(_effectiveTotalStorageBytes)}',
                style: TextStyle(fontSize: 13, color: tokens.text2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_libraries.isEmpty)
          Text(
            'No libraries configured yet. Use "Add library" to point Hermes to a media folder.',
            style: TextStyle(fontSize: 14, color: tokens.text2),
          )
        else if (wide)
          Column(
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: tokens.line)),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Name', style: thStyle)),
                    Expanded(flex: 3, child: Text('Folder', style: thStyle)),
                    Expanded(flex: 2, child: Text('Contents', style: thStyle)),
                    Expanded(flex: 1, child: Text('Size', style: thStyle)),
                    Expanded(flex: 2, child: Text('Last scanned', style: thStyle)),
                    const SizedBox(width: 184),
                  ],
                ),
              ),
              for (final lib in _libraries)
                _buildDesktopLibraryRow(tokens, lib),
            ],
          )
        else
          Column(
            children: [
              for (final lib in _libraries)
                _buildMobileLibraryRow(tokens, lib),
            ],
          ),
      ],
    );
  }

  Widget _buildDesktopLibraryRow(HermesThemeTokens tokens, LibraryRootModel lib) {
    final scanning = lib.isScanning || _localScanningLibs.contains(lib.id);
    final progressRatio = lib.scanTotalFiles > 0
        ? (lib.scanProcessedFiles / lib.scanTotalFiles).clamp(0.0, 1.0)
        : null;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              lib.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.text,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              lib.rootPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: tokens.text2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lib.contentsLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              lib.formattedSize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ),
          Expanded(
            flex: 2,
            child: scanning
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lib.scanTotalFiles > 0
                            ? 'Scanning ${lib.scanProcessedFiles} / ${lib.scanTotalFiles}'
                            : 'Scanning...',
                        style: TextStyle(fontSize: 12, color: tokens.text),
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: progressRatio,
                        minHeight: 3,
                        backgroundColor: tokens.surface3,
                        color: tokens.accent,
                      ),
                    ],
                  )
                : Text(
                    _formatScanTime(lib),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: tokens.text2),
                  ),
          ),
          SizedBox(
            width: 184,
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 10,
                children: [
                  _InlineTextAction(
                    label: 'Scan Now',
                    enabled: !scanning,
                    onTap: () => unawaited(_scanLibrary(lib.id)),
                  ),
                  _InlineTextAction(
                    label: 'Edit',
                    enabled: !scanning,
                    onTap: () => unawaited(_openEditLibrary(lib)),
                  ),
                  _InlineTextAction(
                    label: 'Delete',
                    enabled: !scanning,
                    onTap: () => unawaited(_deleteLibrary(lib)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLibraryRow(HermesThemeTokens tokens, LibraryRootModel lib) {
    final scanning = lib.isScanning || _localScanningLibs.contains(lib.id);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lib.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lib.rootPath,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: tokens.text2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scanning
                      ? (lib.scanTotalFiles > 0
                          ? 'Scanning ${lib.scanProcessedFiles} / ${lib.scanTotalFiles}…'
                          : 'Scanning…')
                      : '${lib.contentsLabel} • ${lib.formattedSize} • ${_formatScanTime(lib)}',
                  style: TextStyle(fontSize: 12, color: tokens.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _InlineTextAction(
                label: 'Scan Now',
                enabled: !scanning,
                onTap: () => unawaited(_scanLibrary(lib.id)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InlineTextAction(
                    label: 'Edit',
                    enabled: !scanning,
                    onTap: () => unawaited(_openEditLibrary(lib)),
                  ),
                  const SizedBox(width: 8),
                  _InlineTextAction(
                    label: 'Delete',
                    enabled: !scanning,
                    onTap: () => unawaited(_deleteLibrary(lib)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionSection(HermesThemeTokens tokens, bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Needs attention',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: tokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "${_unmatched.length} ${_unmatched.length == 1 ? "item couldn't" : "items couldn't"} be identified automatically. Fix the match so artwork and details appear.",
          style: TextStyle(fontSize: 13, color: tokens.text2),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _unmatched.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: i == _unmatched.length - 1
                        ? null
                        : Border(bottom: BorderSide(color: tokens.lineSoft)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xFFF2B13B),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _unmatched[i].filePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: tokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _unmatched[i].libraryName,
                              style: TextStyle(fontSize: 12, color: tokens.text2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => unawaited(_openFixMatch(_unmatched[i])),
                        style: TextButton.styleFrom(
                          backgroundColor: tokens.surface2,
                          foregroundColor: tokens.text,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        child: const Text(
                          'Fix match',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeopleSection(HermesThemeTokens tokens, bool wide) {
    final thStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: tokens.text2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'People',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tokens.text,
              ),
            ),
            _InlineTextAction(
              label: 'Create invite',
              accent: true,
              onTap: _openCreateInvite,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (wide)
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.line)),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Account', style: thStyle)),
                Expanded(flex: 2, child: Text('Role', style: thStyle)),
                Expanded(flex: 2, child: Text('Status', style: thStyle)),
                const SizedBox(width: 224),
              ],
            ),
          ),
        for (final user in _users)
          _buildUserRow(tokens, user, wide),
        for (final inv in _invites)
          _buildInviteRow(tokens, inv, wide),
      ],
    );
  }

  Widget _buildUserRow(
    HermesThemeTokens tokens,
    UserSummaryModel user,
    bool wide,
  ) {
    final isAdmin = user.role.toLowerCase() == 'admin';
    final statusDot = _StatusIndicator(
      label: user.isActive ? 'Active' : 'Disabled',
      active: user.isActive,
    );

    final actions = Wrap(
      spacing: 14,
      alignment: WrapAlignment.end,
      children: [
        _InlineTextAction(
          label: isAdmin ? 'Reset login code' : 'Reset code',
          onTap: () => unawaited(_issueResetCode(user)),
        ),
        if (!isAdmin && user.isActive)
          _InlineTextAction(
            label: 'Remove',
            onTap: () => unawaited(_removeUser(user)),
          ),
      ],
    );

    if (!wide) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.lineSoft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    user.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tokens.text),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isAdmin ? 'Owner' : user.role,
                  style: TextStyle(fontSize: 12, color: tokens.text2),
                ),
                const SizedBox(width: 10),
                statusDot,
              ],
            ),
            const SizedBox(height: 6),
            actions,
          ],
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tokens.text),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isAdmin ? 'Owner' : user.role,
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ),
          Expanded(flex: 2, child: statusDot),
          SizedBox(
            width: 224,
            child: Align(alignment: Alignment.centerRight, child: actions),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteRow(
    HermesThemeTokens tokens,
    InviteModel inv,
    bool wide,
  ) {
    final usesLabel = inv.maxUses >= 1000 ? 'unlimited' : '${inv.maxUses}';
    final expired = DateTime.now().toUtc().isAfter(inv.expiresAtUtc);
    final statusLabel = inv.isRevoked
        ? 'Revoked'
        : expired
            ? 'Expired'
            : 'Expires ${inv.expiresAtUtc.toLocal().toString().substring(0, 10)}';

    final actions = Wrap(
      spacing: 14,
      alignment: WrapAlignment.end,
      children: [
        _InlineTextAction(
          label: 'Copy link',
          onTap: () {
            unawaited(Clipboard.setData(ClipboardData(text: _joinLinkForCode(inv.code))));
            _showToast('Invite link copied.');
          },
        ),
        if (!inv.isRevoked)
          _InlineTextAction(
            label: 'Revoke',
            onTap: () => unawaited(_revokeInvite(inv)),
          ),
      ],
    );

    if (!wide) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.lineSoft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inv.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: tokens.text),
            ),
            const SizedBox(height: 3),
            Text(
              'Invite • ${inv.usedCount} of $usesLabel used • $statusLabel',
              style: TextStyle(fontSize: 12, color: tokens.text2),
            ),
            const SizedBox(height: 6),
            actions,
          ],
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              inv.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: tokens.text),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Invite • ${inv.usedCount} of $usesLabel used',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ),
          Expanded(
            flex: 2,
            child: _StatusIndicator(
              label: statusLabel,
              active: !inv.isRevoked && !expired,
            ),
          ),
          SizedBox(
            width: 224,
            child: Align(alignment: Alignment.centerRight, child: actions),
          ),
        ],
      ),
    );
  }

  Widget _buildServerSettingsSection(HermesThemeTokens tokens, bool wide) {
    final totalBytes = _effectiveTotalStorageBytes;
    final libCount = _serverSettings?.libraryCount ?? _libraries.length;
    final countsLabel = _serverSettings != null
        ? '${_serverSettings!.totalMovies} movies • ${_serverSettings!.totalSeries} series • ${_serverSettings!.totalSongs} tracks'
        : '$libCount ${libCount == 1 ? 'library' : 'libraries'} configured';

    const bitrateOptions = <int?>[null, 20000000, 15000000, 10000000, 8000000, 4000000];
    final currentBitrate = bitrateOptions.contains(_maxRemoteBitrateBps)
        ? _maxRemoteBitrateBps
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'Server settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tokens.text,
              ),
            ),
            Text(
              'Total media size: ${formatStorageBytes(totalBytes)} • $countsLabel',
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tokens.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildServerNameField(tokens),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _buildHwAccelDropdown(tokens),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildRemoteBitrateDropdown(tokens, currentBitrate, bitrateOptions),
                    ),
                  ],
                )
              else ...[
                _buildServerNameField(tokens),
                const SizedBox(height: 14),
                _buildHwAccelDropdown(tokens),
                const SizedBox(height: 14),
                _buildRemoteBitrateDropdown(tokens, currentBitrate, bitrateOptions),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: tokens.lineSoft)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enable transcoding',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Allow ffmpeg video HLS & audio bitrate conversion when clients cannot Direct Play.',
                                style: TextStyle(fontSize: 12, color: tokens.text2),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _transcodingEnabled,
                          onChanged: (v) => setState(() => _transcodingEnabled = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SlotStepperRow(
                      label: 'Max concurrent video transcodes',
                      value: _maxVideoTranscodes,
                      min: 0,
                      max: 16,
                      onChanged: (v) => setState(() => _maxVideoTranscodes = v),
                    ),
                    const SizedBox(height: 8),
                    _SlotStepperRow(
                      label: 'Max concurrent audio transcodes',
                      value: _maxAudioTranscodes,
                      min: 0,
                      max: 16,
                      onChanged: (v) => setState(() => _maxAudioTranscodes = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _savingSettings ? null : _saveServerSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.accentInk,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                  ),
                  child: Text(
                    _savingSettings ? 'Saving…' : 'Save settings',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerNameField(HermesThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server name',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _serverNameController,
          style: TextStyle(fontSize: 14, color: tokens.text),
          decoration: InputDecoration(
            hintText: 'Hermes Media Server',
            hintStyle: TextStyle(color: tokens.text3),
            filled: true,
            fillColor: tokens.surface3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildHwAccelDropdown(HermesThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server transcode GPU (host)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
        ),
        const SizedBox(height: 2),
        Text(
          'Runs inside the Hermes server host or container, never on phones or client devices.',
          style: TextStyle(fontSize: 11, color: tokens.text3),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<HardwareAccelerationMode>(
          initialValue: _hwAccelMode,
          isExpanded: true,
          dropdownColor: tokens.surface3,
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.surface3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            isDense: true,
          ),
          items: [
            for (final mode in HardwareAccelerationMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(
                  mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _hwAccelMode = v);
          },
        ),
      ],
    );
  }

  Widget _buildRemoteBitrateDropdown(
    HermesThemeTokens tokens,
    int? currentBitrate,
    List<int?> bitrateOptions,
  ) {
    String labelForBitrate(int? bps) {
      if (bps == null) return 'Unlimited';
      return '${(bps / 1000000).round()} Mbps';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Remote cap',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<int?>(
          initialValue: currentBitrate,
          isExpanded: true,
          dropdownColor: tokens.surface3,
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.surface3,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            isDense: true,
          ),
          items: [
            for (final bps in bitrateOptions)
              DropdownMenuItem<int?>(
                value: bps,
                child: Text(
                  labelForBitrate(bps),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _maxRemoteBitrateBps = v),
        ),
      ],
    );
  }
}

class _SlotStepperRow extends StatelessWidget {
  const _SlotStepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: tokens.text2),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_rounded, size: 16),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tokens.text),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded, size: 16),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.artworkUri,
    this.onStop,
  });

  final ActiveStreamSessionModel session;
  final Uri? artworkUri;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final thumbWidth = session.isMusic ? 72.0 : 120.0;
    final thumbHeight = session.isMusic ? 72.0 : 68.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HermesArtworkImage(
            uri: artworkUri,
            fallbackTitle: session.title,
            fallbackIcon: session.isMusic ? Icons.music_note_rounded : Icons.movie_rounded,
            width: thumbWidth,
            height: thumbHeight,
            borderRadius: BorderRadius.circular(4),
            showFallbackLabel: false,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.text,
                        ),
                      ),
                    ),
                    if (session.isPaused) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Paused',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tokens.text2,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  session.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: tokens.text2),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: session.progress,
                    minHeight: 3,
                    backgroundColor: tokens.surface3,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      '${session.username} • ${session.deviceName}',
                      style: TextStyle(fontSize: 12, color: tokens.text2),
                    ),
                    Text(
                      session.bitrate.isNotEmpty
                          ? '${session.mode} • ${session.bitrate}'
                          : session.mode,
                      style: TextStyle(fontSize: 12, color: tokens.text2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 8),
            _InlineTextAction(label: 'Stop', onTap: onStop!),
          ],
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF3ECF72) : tokens.text3,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: tokens.text2),
          ),
        ),
      ],
    );
  }
}

class _InlineTextAction extends StatelessWidget {
  const _InlineTextAction({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: !enabled
                ? tokens.text3
                : accent
                    ? tokens.accent
                    : tokens.text2,
          ),
        ),
      ),
    );
  }
}
