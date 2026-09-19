import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Sign in or create an account on the rider's own Live Ride server.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final services = AppServices.of(context);
    try {
      final identity = _register
          ? await services.api.register(
              _username.text,
              _email.text,
              _password.text,
            )
          : await services.api.login(_username.text, _password.text);
      await services.profile.adoptAccount(
        username: identity.username,
        name: identity.name,
      );
      if (mounted) widget.onSignedIn();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LR.night,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LrWordmark(dark: true),
                const SizedBox(height: 26),
                Text(
                  _register ? 'Create your rider account' : 'Sign in to ride',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  ApiClient.serverOrigin,
                  style: TextStyle(color: Color(0xFF7D93A4), fontSize: 12.5),
                ),
                const SizedBox(height: 28),
                _field(_username, 'Username', autofocus: true),
                if (_register) ...[
                  const SizedBox(height: 12),
                  _field(
                    _email,
                    'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
                const SizedBox(height: 12),
                _field(_password, 'Password', obscure: true),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: LR.alert.withValues(alpha: 0.14),
                      border: Border.all(color: LR.alert),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: LR.alert,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: LR.accent,
                    foregroundColor: LR.ink,
                    disabledBackgroundColor: LR.nightLine,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LR.ink,
                          ),
                        )
                      : Text(_register ? 'CREATE ACCOUNT' : 'SIGN IN'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                  child: Text(
                    _register
                        ? 'I already have an account'
                        : 'Create a new account',
                    style: const TextStyle(color: LR.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    bool autofocus = false,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    autofocus: autofocus,
    keyboardType: keyboardType,
    autocorrect: false,
    enableSuggestions: !obscure,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF8DA2B1)),
      filled: true,
      fillColor: LR.nightPanel,
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(color: LR.nightLine),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
        borderSide: BorderSide(color: LR.accent, width: 1.6),
      ),
    ),
  );
}
