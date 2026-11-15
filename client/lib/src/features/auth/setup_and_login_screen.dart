import 'package:material_ui/material_ui.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/endpoint_resolver.dart';
import '../../core/theme/hermes_theme_tokens.dart';

class SetupAndLoginScreen extends StatefulWidget {
  const SetupAndLoginScreen({
    super.key,
    required this.endpointResolver,
    required this.authService,
    required this.deviceId,
    required this.deviceName,
    required this.onAuthenticated,
  });

  final EndpointResolver endpointResolver;
  final AuthService authService;
  final String deviceId;
  final String deviceName;
  final void Function(HermesSession session, ResolvedEndpoint endpoint) onAuthenticated;

  @override
  State<SetupAndLoginScreen> createState() => _SetupAndLoginScreenState();
}

class _SetupAndLoginScreenState extends State<SetupAndLoginScreen> {
  final _primaryUrlController = TextEditingController(text: 'http://localhost:5000');
  final _lanUrlController = TextEditingController();
  final _serverNameController = TextEditingController(text: 'Hermes Home');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  ResolvedEndpoint? _resolved;
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _primaryUrlController.dispose();
    _lanUrlController.dispose();
    _serverNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _connectServer() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final resolved = await widget.endpointResolver.resolve(
        primaryUrl: _primaryUrlController.text,
        lanFallbackUrl: _lanUrlController.text,
      );
      setState(() => _resolved = resolved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submitAuth() async {
    final resolved = _resolved;
    if (resolved == null) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final baseUrl = resolved.baseUri.toString();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (!resolved.info.setupCompleted) {
        await widget.authService.setupServer(
          baseUrl: baseUrl,
          adminUsername: username,
          adminPassword: password,
          serverName: _serverNameController.text.trim(),
        );
      } else if (_registerMode) {
        await widget.authService.registerWithInvite(
          baseUrl: baseUrl,
          username: username,
          password: password,
          inviteCode: _inviteCodeController.text.trim(),
        );
      }

      final session = await widget.authService.login(
        primaryUrl: _primaryUrlController.text.trim(),
        lanFallbackUrl: _lanUrlController.text.trim().isEmpty ? null : _lanUrlController.text.trim(),
        resolvedBaseUrl: baseUrl,
        serverId: resolved.info.serverId,
        username: username,
        password: password,
        deviceId: widget.deviceId,
        deviceName: widget.deviceName,
      );

      widget.onAuthenticated(session, resolved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final resolved = _resolved;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hermes Media Server',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    resolved == null
                        ? 'Connect via Tailscale HTTPS or Direct LAN'
                        : '${resolved.info.serverName} (${resolved.usedFallback ? 'LAN fallback' : 'Primary'})',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x33EF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (resolved == null) ...[
                    TextField(
                      controller: _primaryUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Primary URL (Tailscale / HTTPS)',
                        hintText: 'https://hermes.tailnet.ts.net',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lanUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Optional LAN Fallback URL',
                        hintText: 'http://192.168.1.50:5000',
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _connectServer,
                      child: Text(_busy ? 'Probing...' : 'Connect Server'),
                    ),
                  ] else ...[
                    if (!resolved.info.setupCompleted) ...[
                      TextField(
                        controller: _serverNameController,
                        decoration: const InputDecoration(labelText: 'Server Display Name'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: resolved.info.setupCompleted ? 'Username' : 'Admin Username',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (resolved.info.setupCompleted && _registerMode) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inviteCodeController,
                        decoration: const InputDecoration(labelText: 'Invite Code'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submitAuth,
                      child: Text(
                        !resolved.info.setupCompleted
                            ? 'Initialize Server & Sign In'
                            : (_registerMode ? 'Redeem Invite & Sign In' : 'Sign In'),
                      ),
                    ),
                    if (resolved.info.setupCompleted)
                      TextButton(
                        onPressed: () => setState(() => _registerMode = !_registerMode),
                        child: Text(
                          _registerMode ? 'Already have an account? Sign In' : 'Have an invite code? Create account',
                        ),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _resolved = null),
                      child: const Text('Change Server'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
