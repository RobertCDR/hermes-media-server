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
    final summary = await widget.adminService.scanLibrary(id);
    if (mounted) {
      setState(() {
        _statusMessage =
            'Scan finished: ${summary.filesDiscovered} files, ${summary.sourcesUpserted} upserted.';
      });
    }
    await _refresh();
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
                Text('Libraries (${_libraries.length})', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
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
