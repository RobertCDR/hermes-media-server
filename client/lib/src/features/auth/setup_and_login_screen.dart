import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/session_store.dart';
import '../../core/network/endpoint_resolver.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_icons.dart';

enum HermesAuthMode { signIn, invite, setup }

class SetupAndLoginScreen extends StatefulWidget {
  const SetupAndLoginScreen({
    super.key,
    required this.endpointResolver,
    required this.authService,
    required this.deviceId,
    required this.deviceName,
    required this.onAuthenticated,
    this.initialPrimaryUrl = 'http://localhost:5000',
    this.initialLanUrl = '',
    this.initialEndpoint,
    this.initialMode,
    this.onCancel,
  });

  final EndpointResolver endpointResolver;
  final AuthService authService;
  final String deviceId;
  final String deviceName;
  final void Function(HermesSession session, ResolvedEndpoint endpoint)
      onAuthenticated;
  final String initialPrimaryUrl;
  final String initialLanUrl;
  final ResolvedEndpoint? initialEndpoint;
  final HermesAuthMode? initialMode;
  final VoidCallback? onCancel;

  @override
  State<SetupAndLoginScreen> createState() => _SetupAndLoginScreenState();
}

class _SetupAndLoginScreenState extends State<SetupAndLoginScreen> {
  late final TextEditingController _primaryUrlController;
  late final TextEditingController _lanUrlController;
  final _serverNameController = TextEditingController(text: 'Hermes Home');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  ResolvedEndpoint? _resolved;
  late HermesAuthMode _mode;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primaryUrlController = TextEditingController(text: widget.initialPrimaryUrl);
    _lanUrlController = TextEditingController(text: widget.initialLanUrl);
    _resolved = widget.initialEndpoint;
    _mode = widget.initialMode ??
        (_resolved != null && !_resolved!.info.setupCompleted
            ? HermesAuthMode.setup
            : HermesAuthMode.signIn);
    if (_resolved != null && _resolved!.info.serverName.trim().isNotEmpty) {
      _serverNameController.text = _resolved!.info.serverName;
    }
  }

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

  Future<void> _connectEndpoint() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resolved = await widget.endpointResolver.resolve(
        primaryUrl: _primaryUrlController.text,
        lanFallbackUrl: _lanUrlController.text.trim().isEmpty
            ? null
            : _lanUrlController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _resolved = resolved;
        _mode = resolved.info.setupCompleted
            ? HermesAuthMode.signIn
            : HermesAuthMode.setup;
        if (resolved.info.serverName.trim().isNotEmpty) {
          _serverNameController.text = resolved.info.serverName;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitAuth() async {
    final resolved = _resolved;
    if (resolved == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseUrl = resolved.baseUri.toString();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (_mode == HermesAuthMode.setup) {
        await widget.authService.setupServer(
          baseUrl: baseUrl,
          serverName: _serverNameController.text.trim(),
          adminUsername: username,
          adminPassword: password,
        );
      } else if (_mode == HermesAuthMode.invite) {
        await widget.authService.registerWithInvite(
          baseUrl: baseUrl,
          username: username,
          password: password,
          inviteCode: _inviteCodeController.text.trim(),
        );
      }

      final lanFallback = _lanUrlController.text.trim();
      final session = await widget.authService.login(
        primaryUrl: _primaryUrlController.text.trim(),
        lanFallbackUrl: lanFallback.isEmpty ? null : lanFallback,
        resolvedBaseUrl: baseUrl,
        serverId: resolved.info.serverId,
        username: username,
        password: password,
        deviceId: widget.deviceId,
        deviceName: widget.deviceName,
      );

      if (!mounted) return;
      widget.onAuthenticated(session, resolved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.bgSunken,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.05),
                    radius: 1.15,
                    colors: [
                      tokens.accent.withValues(alpha: 0.16),
                      tokens.bgSunken.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          HermesMarkIcon(size: 26, color: tokens.accent),
                          const SizedBox(width: 12),
                          Text(
                            'Hermes',
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.36,
                              color: tokens.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      if (_resolved == null)
                        _buildConnectStep(tokens)
                      else
                        _buildAuthStep(tokens, _resolved!),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectStep(HermesThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Connect to server',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.56,
            color: tokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use your Tailscale HTTPS address with an optional direct LAN fallback.',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            height: 1.5,
            color: tokens.text2,
          ),
        ),
        const SizedBox(height: 24),
        _AuthField(
          label: 'Primary URL (Tailscale / HTTPS)',
          controller: _primaryUrlController,
          hintText: 'https://hermes.tailnet.ts.net',
          monospace: true,
          autofocus: true,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _loading ? null : _connectEndpoint(),
          tokens: tokens,
        ),
        const SizedBox(height: 14),
        _AuthField(
          label: 'LAN fallback URL (optional)',
          controller: _lanUrlController,
          hintText: 'http://192.168.1.50:5258',
          monospace: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _connectEndpoint(),
          tokens: tokens,
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFFF6B7D), fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: _loading ? null : _connectEndpoint,
            child: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accentInk,
                    ),
                  )
                : const Text('Connect server'),
          ),
        ),
        if (widget.onCancel != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onCancel,
              child: const Text('Return to app'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAuthStep(HermesThemeTokens tokens, ResolvedEndpoint resolved) {
    final title = switch (_mode) {
      HermesAuthMode.signIn => 'Sign in to Hermes',
      HermesAuthMode.invite => 'Create account',
      HermesAuthMode.setup => 'Initialize server',
    };
    final subtitle = switch (_mode) {
      HermesAuthMode.signIn => 'Sign in with your Hermes account credentials.',
      HermesAuthMode.invite =>
        'Enter your invite code to unlock access to your shared libraries.',
      HermesAuthMode.setup =>
        'Create the initial owner account and display name for this server.',
    };
    final ctaLabel = switch (_mode) {
      HermesAuthMode.signIn => 'Sign in',
      HermesAuthMode.invite => 'Redeem invite & sign in',
      HermesAuthMode.setup => 'Initialize server & sign in',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tokens.line),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF3ECF72),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resolved.usedFallback
                      ? '${resolved.info.serverName} · LAN fallback'
                      : resolved.info.serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _resolved = null;
                  _error = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Change',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.text2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
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
                _AuthModeTab(
                  label: 'Sign in',
                  active: _mode == HermesAuthMode.signIn,
                  tokens: tokens,
                  onTap: () => setState(() {
                    _mode = HermesAuthMode.signIn;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 20),
                _AuthModeTab(
                  label: 'Invite code',
                  active: _mode == HermesAuthMode.invite,
                  tokens: tokens,
                  onTap: () => setState(() {
                    _mode = HermesAuthMode.invite;
                    _error = null;
                  }),
                ),
                const SizedBox(width: 20),
                _AuthModeTab(
                  label: 'First setup',
                  active: _mode == HermesAuthMode.setup,
                  tokens: tokens,
                  onTap: () => setState(() {
                    _mode = HermesAuthMode.setup;
                    _error = null;
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.56,
            color: tokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            height: 1.5,
            color: tokens.text2,
          ),
        ),
        const SizedBox(height: 22),
        if (_mode == HermesAuthMode.setup) ...[
          _AuthField(
            label: 'Server display name',
            controller: _serverNameController,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
        ],
        _AuthField(
          label: _mode == HermesAuthMode.setup ? 'Owner username' : 'Username',
          controller: _usernameController,
          autofocus: true,
          tokens: tokens,
        ),
        const SizedBox(height: 14),
        _AuthField(
          label: 'Password',
          controller: _passwordController,
          obscureText: true,
          textInputAction: _mode == HermesAuthMode.invite
              ? TextInputAction.next
              : TextInputAction.done,
          onSubmitted: (_) {
            if (_mode != HermesAuthMode.invite && !_loading) {
              _submitAuth();
            }
          },
          tokens: tokens,
        ),
        if (_mode == HermesAuthMode.invite) ...[
          const SizedBox(height: 14),
          _AuthField(
            label: 'Invite code',
            controller: _inviteCodeController,
            hintText: 'HRM-9421-X8TQ',
            monospace: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loading ? null : _submitAuth(),
            tokens: tokens,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFFF6B7D), fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: _loading ? null : _submitAuth,
            child: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accentInk,
                    ),
                  )
                : Text(ctaLabel),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _resolved = null;
                _error = null;
              }),
              child: const Text('Switch server'),
            ),
            if (widget.onCancel != null)
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Return to app'),
              ),
          ],
        ),
      ],
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
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
        padding: const EdgeInsets.symmetric(vertical: 8),
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
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? tokens.text : tokens.text2,
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.tokens,
    this.hintText,
    this.obscureText = false,
    this.monospace = false,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final HermesThemeTokens tokens;
  final String? hintText;
  final bool obscureText;
  final bool monospace;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.text2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: TextStyle(
            fontFamily: monospace ? 'monospace' : 'Figtree',
            fontSize: monospace ? 13 : 14,
            color: tokens.text,
          ),
          decoration: InputDecoration(
            hintText: hintText,
          ),
        ),
      ],
    );
  }
}
