import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'admin_models.dart';
import 'admin_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.adminService,
  });

  final AdminService adminService;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<LibraryRootModel> _libraries = [];
  List<InviteModel> _invites = [];
  List<UserSummaryModel> _users = [];
  bool _loading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final libraries = await widget.adminService.listLibraries();
      final invites = await widget.adminService.listInvites();
      final users = await widget.adminService.listUsers();
      if (mounted) {
        setState(() {
          _libraries = libraries;
          _invites = invites;
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Load error: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _scanLibrary(String id) async {
    try {
      final summary = await widget.adminService.scanLibrary(id);
      if (mounted) {
        setState(() {
          _statusMessage =
              'Scan finished: ${summary.filesDiscovered} files, ${summary.sourcesUpserted} upserted.';
        });
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Scan error: $e');
      }
    }
  }

  Future<void> _scanAllLibraries() async {
    try {
      var totalFiles = 0;
      var totalUpserted = 0;
      for (final lib in _libraries) {
        final summary = await widget.adminService.scanLibrary(lib.id);
        totalFiles += summary.filesDiscovered;
        totalUpserted += summary.sourcesUpserted;
      }
      if (mounted) {
        setState(() {
          _statusMessage =
              'Scanned ${_libraries.length} library(ies): $totalFiles files discovered, $totalUpserted upserted.';
        });
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Scan error: $e');
      }
    }
  }

  Future<void> _openAddLibraryDialog() async {
    final nameController = TextEditingController();
    final pathController = TextEditingController(text: '/media/Movies');
    var selectedType = 0;
    var watchEnabled = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Library Root'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Library Name',
                  hintText: 'Movies',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Movies'),
                    selected: selectedType == 0,
                    onSelected: (_) => setDialogState(() {
                      selectedType = 0;
                      if (pathController.text.startsWith('/media/')) {
                        pathController.text = '/media/Movies';
                      }
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Series'),
                    selected: selectedType == 1,
                    onSelected: (_) => setDialogState(() {
                      selectedType = 1;
                      if (pathController.text.startsWith('/media/')) {
                        pathController.text = '/media/Series';
                      }
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Music'),
                    selected: selectedType == 2,
                    onSelected: (_) => setDialogState(() {
                      selectedType = 2;
                      if (pathController.text.startsWith('/media/')) {
                        pathController.text = '/media/Music';
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: 'Server Folder Path',
                  hintText: '/media/Movies',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Watch for changes'),
                value: watchEnabled,
                onChanged: (value) => setDialogState(() => watchEnabled = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Add Library')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final name = nameController.text.trim();
      final rootPath = pathController.text.trim();
      if (name.isNotEmpty && rootPath.isNotEmpty) {
        try {
          final created = await widget.adminService.createLibrary(
            name: name,
            mediaType: selectedType,
            rootPath: rootPath,
            watchEnabled: watchEnabled,
          );
          final summary = await widget.adminService.scanLibrary(created.id);
          if (mounted) {
            setState(() {
              _statusMessage =
                  'Added "${created.name}": ${summary.filesDiscovered} files, ${summary.sourcesUpserted} upserted.';
            });
          }
          await _refresh();
        } catch (e) {
          if (mounted) {
            setState(() => _statusMessage = 'Add library error: $e');
          }
        }
      }
    }

    nameController.dispose();
    pathController.dispose();
  }

  Future<void> _createInvite() async {
    final invite = await widget.adminService.createInvite();
    if (mounted) {
      setState(() => _statusMessage = 'Created invite ${invite.code}');
    }
    await _refresh();
  }

  Future<void> _issueResetCode(String userId, String username) async {
    final code = await widget.adminService.issueResetCode(userId);
    if (mounted) {
      setState(() => _statusMessage = 'One-time reset code for $username: ${code.resetCode}');
    }
  }

  Future<void> _openIdentifyDialog() async {
    final mediaIdController = TextEditingController();
    final tmdbIdController = TextEditingController();
    final titleController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual TMDb Identify'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mediaIdController,
              decoration: const InputDecoration(labelText: 'Movie/Series ID (GUID)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tmdbIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'TMDb ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Verified Title'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Lock Match')),
        ],
      ),
    );

    if (confirmed == true) {
      final tmdbId = int.tryParse(tmdbIdController.text.trim()) ?? 0;
      if (tmdbId > 0 && titleController.text.trim().isNotEmpty) {
        final result = await widget.adminService.identifyMedia(
          mediaId: mediaIdController.text.trim(),
          tmdbId: tmdbId,
          title: titleController.text.trim(),
        );
        if (mounted) {
          setState(() => _statusMessage = 'Locked ${result.title} (TMDb ${result.tmdbId})');
        }
      }
    }

    mediaIdController.dispose();
    tmdbIdController.dispose();
    titleController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Admin'),
        actions: [
          IconButton(
            tooltip: 'Identify Media (TMDb)',
            icon: const Icon(Icons.find_replace),
            onPressed: _openIdentifyDialog,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_statusMessage != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_statusMessage!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Libraries (${_libraries.length})', style: Theme.of(context).textTheme.titleLarge),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_libraries.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _scanAllLibraries,
                            icon: const Icon(Icons.sync),
                            label: const Text('Scan All'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: _openAddLibraryDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Library'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_libraries.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'No library roots configured yet. Click "Add Library" to add /media/Movies, /media/Series, or /media/Music.',
                      ),
                    ),
                  )
                else
                  ..._libraries.map((lib) => Card(
                        child: ListTile(
                          title: Text(lib.name),
                          subtitle: Text(lib.rootPath),
                          trailing: FilledButton.tonal(
                            onPressed: () => unawaited(_scanLibrary(lib.id)),
                            child: const Text('Scan Now'),
                          ),
                        ),
                      )),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Invite Codes (${_invites.length})', style: Theme.of(context).textTheme.titleLarge),
                    FilledButton.tonal(onPressed: _createInvite, child: const Text('Create Invite')),
                  ],
                ),
                const SizedBox(height: 8),
                ..._invites.map((inv) => Card(
                      child: ListTile(
                        title: Text(inv.code),
                        subtitle: Text('Uses: ${inv.usedCount}/${inv.maxUses}'),
                      ),
                    )),
                const SizedBox(height: 20),
                Text('Users (${_users.length})', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ..._users.map((user) => Card(
                      child: ListTile(
                        title: Text(user.username),
                        subtitle: Text('${user.role} • ${user.isActive ? 'Active' : 'Disabled'}'),
                        trailing: TextButton(
                          onPressed: () => unawaited(_issueResetCode(user.id, user.username)),
                          child: const Text('Reset Code'),
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}
