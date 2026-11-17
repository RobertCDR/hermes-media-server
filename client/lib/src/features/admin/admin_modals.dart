import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_icons.dart';
import 'admin_models.dart';
import 'admin_service.dart';

class AddLibraryResult {
  const AddLibraryResult({
    required this.name,
    required this.mediaType,
    required this.rootPath,
    required this.watchEnabled,
  });

  final String name;
  final int mediaType;
  final String rootPath;
  final bool watchEnabled;
}

class CreateInviteOptions {
  const CreateInviteOptions({
    required this.maxUses,
    required this.expiresInHours,
  });

  final int maxUses;
  final int expiresInHours;
}

/// Figma v4 flat `.modal` for adding a media library root without ChoiceChip pills.
class AddLibraryDialog extends StatefulWidget {
  const AddLibraryDialog({super.key});

  @override
  State<AddLibraryDialog> createState() => _AddLibraryDialogState();
}

class _AddLibraryDialogState extends State<AddLibraryDialog> {
  final TextEditingController _nameController = TextEditingController(text: 'Movies');
  final TextEditingController _pathController = TextEditingController(text: '/media/Movies');
  int _mediaType = 0;
  bool _watchEnabled = true;

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _selectType(int nextType) {
    final defaultName = switch (_mediaType) {
      0 => 'Movies',
      1 => 'TV Shows',
      _ => 'Music',
    };
    final nextName = switch (nextType) {
      0 => 'Movies',
      1 => 'TV Shows',
      _ => 'Music',
    };
    final nextPath = switch (nextType) {
      0 => '/media/Movies',
      1 => '/media/Series',
      _ => '/media/Music',
    };

    setState(() {
      _mediaType = nextType;
      if (_nameController.text.trim() == defaultName || _nameController.text.trim().isEmpty) {
        _nameController.text = nextName;
      }
      if (_pathController.text.trim().startsWith('/media/')) {
        _pathController.text = nextPath;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Add library',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.text),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Point Hermes to a media folder mounted on the server.',
                style: TextStyle(fontSize: 13, color: tokens.text2),
              ),
              const SizedBox(height: 16),
              Text(
                'Media type',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
              ),
              const SizedBox(height: 8),
              HermesSegmentedControl<int>(
                options: const [
                  HermesSegmentOption(value: 0, label: 'Movies'),
                  HermesSegmentOption(value: 1, label: 'TV Shows'),
                  HermesSegmentOption(value: 2, label: 'Music'),
                ],
                selected: _mediaType,
                onChanged: _selectType,
              ),
              const SizedBox(height: 16),
              _DialogInputField(
                label: 'Library name',
                controller: _nameController,
                hint: 'Movies',
              ),
              const SizedBox(height: 14),
              _DialogInputField(
                label: 'Folder path on server',
                controller: _pathController,
                hint: '/media/Movies',
                monospace: true,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Watch for file changes',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tokens.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Automatically enqueue scans when new files arrive.',
                          style: TextStyle(fontSize: 12, color: tokens.text2),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _watchEnabled,
                    onChanged: (v) => setState(() => _watchEnabled = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: tokens.text2)),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final rootPath = _pathController.text.trim();
            if (name.isEmpty || rootPath.isEmpty) return;
            Navigator.of(context).pop(
              AddLibraryResult(
                name: name,
                mediaType: _mediaType,
                rootPath: rootPath,
                watchEnabled: _watchEnabled,
              ),
            );
          },
          child: const Text('Add & scan library'),
        ),
      ],
    );
  }
}

/// Figma v4 `Fix match` dialog searching TMDb live with fallback manual TMDb ID lock.
class FixMatchDialog extends StatefulWidget {
  const FixMatchDialog({
    super.key,
    required this.item,
    required this.adminService,
  });

  final UnmatchedMediaModel item;
  final AdminService adminService;

  @override
  State<FixMatchDialog> createState() => _FixMatchDialogState();
}

class _FixMatchDialogState extends State<FixMatchDialog> {
  late final TextEditingController _queryController;
  final TextEditingController _manualTmdbIdController = TextEditingController();
  List<TmdbCandidateModel> _candidates = const [];
  bool _searching = false;
  bool _manualMode = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.item.title);
    unawaited(_runSearch(widget.item.title));
  }

  @override
  void dispose() {
    _queryController.dispose();
    _manualTmdbIdController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _candidates = const []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final hits = await widget.adminService.searchTmdb(
        query: trimmed,
        mediaType: widget.item.mediaType,
      );
      if (mounted) {
        setState(() {
          _candidates = hits;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search unavailable ($e)';
          _searching = false;
        });
      }
    }
  }

  Future<void> _lockMatch({
    required int tmdbId,
    required String title,
    int? year,
    String? overview,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.adminService.identifyMedia(
        mediaId: widget.item.id,
        tmdbId: tmdbId,
        title: title,
        year: year,
        overview: overview,
      );
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not lock match: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final kindLabel = widget.item.mediaType == 1 ? 'TV Series' : 'Movie';

    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Fix match',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.text),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.filePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: tokens.text2,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _DialogInputField(
                    label: 'Search TMDb for the correct title',
                    controller: _queryController,
                    hint: 'Title or year',
                    onSubmitted: _runSearch,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _searching ? null : () => _runSearch(_queryController.text),
                  child: const Text('Search'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 12, color: tokens.accent)),
            ],
            const SizedBox(height: 12),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No TMDb results yet. Ensure TMDB API key is set or enter TMDb ID manually.',
                  style: TextStyle(fontSize: 12, color: tokens.text2),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _candidates.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: tokens.lineSoft),
                  itemBuilder: (ctx, i) {
                    final c = _candidates[i];
                    return InkWell(
                      onTap: _saving
                          ? null
                          : () => _lockMatch(
                                tmdbId: c.tmdbId,
                                title: c.title,
                                year: c.year,
                                overview: c.overview,
                              ),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$kindLabel${c.year != null ? ' • ${c.year}' : ''}',
                              style: TextStyle(fontSize: 12, color: tokens.text2),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _manualMode = !_manualMode),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                _manualMode ? 'Hide manual TMDb ID' : 'Enter TMDb ID manually',
                style: TextStyle(fontSize: 12, color: tokens.text2),
              ),
            ),
            if (_manualMode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualTmdbIdController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: tokens.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'TMDb ID (e.g. 693134)',
                        hintStyle: TextStyle(color: tokens.text3),
                        filled: true,
                        fillColor: tokens.surface3,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            final id = int.tryParse(_manualTmdbIdController.text.trim()) ?? 0;
                            final title = _queryController.text.trim().isNotEmpty
                                ? _queryController.text.trim()
                                : widget.item.title;
                            if (id > 0 && title.isNotEmpty) {
                              unawaited(_lockMatch(tmdbId: id, title: title));
                            }
                          },
                    child: const Text('Lock match'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Figma v4 `Invite someone` dialog with expiration and usage limits.
class CreateInviteDialog extends StatefulWidget {
  const CreateInviteDialog({super.key});

  @override
  State<CreateInviteDialog> createState() => _CreateInviteDialogState();
}

class _CreateInviteDialogState extends State<CreateInviteDialog> {
  int _expiresInHours = 168;
  int _maxUses = 3;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Invite someone',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.text),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "They'll create an account using this code to connect to your server.",
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
            const SizedBox(height: 16),
            Text(
              'Link expires',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _expiresInHours,
              dropdownColor: tokens.surface3,
              decoration: InputDecoration(
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 24, child: Text('After 24 hours')),
                DropdownMenuItem(value: 168, child: Text('After 7 days')),
                DropdownMenuItem(value: 720, child: Text('After 30 days')),
                DropdownMenuItem(value: 87600, child: Text('Never (10 years)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _expiresInHours = v);
              },
            ),
            const SizedBox(height: 14),
            Text(
              'Can be used by',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _maxUses,
              dropdownColor: tokens.surface3,
              decoration: InputDecoration(
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 person')),
                DropdownMenuItem(value: 3, child: Text('3 people')),
                DropdownMenuItem(value: 5, child: Text('5 people')),
                DropdownMenuItem(value: 1000, child: Text('Unlimited (1000 uses)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _maxUses = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: tokens.text2)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            CreateInviteOptions(maxUses: _maxUses, expiresInHours: _expiresInHours),
          ),
          child: const Text('Create invite'),
        ),
      ],
    );
  }
}

/// Figma v4 `Invite ready` dialog displaying generated invite code, join URL, and copy action.
class InviteReadyDialog extends StatelessWidget {
  const InviteReadyDialog({
    super.key,
    required this.invite,
    required this.joinLink,
  });

  final InviteModel invite;
  final String joinLink;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final usesLabel = invite.maxUses >= 1000
        ? 'Unlimited uses'
        : '${invite.maxUses} ${invite.maxUses == 1 ? 'use' : 'uses'}';

    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Invite ready',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.text),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              invite.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$usesLabel • Expires ${invite.expiresAtUtc.toLocal().toString().substring(0, 10)}',
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: tokens.surface3,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      joinLink,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: tokens.text2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      unawaited(Clipboard.setData(ClipboardData(text: joinLink)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite link copied')),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 15),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _DialogInputField extends StatelessWidget {
  const _DialogInputField({
    required this.label,
    required this.controller,
    required this.hint,
    this.monospace = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool monospace;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.text),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          style: TextStyle(
            fontFamily: monospace ? 'monospace' : null,
            fontSize: 14,
            color: tokens.text,
          ),
          decoration: InputDecoration(
            hintText: hint,
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
}
