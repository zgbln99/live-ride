import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Co ekran logowania robi w tej chwili.
enum LoginMode { signIn, register, reset }

/// Logowanie, zakładanie konta i reset hasła na serwerze Live Ride.
///
/// Jeden ekran, trzy tryby: rowerzysta, który pomylił hasło, ma do resetu
/// jedno dotknięcie, a nie wyjście z aplikacji i szukanie strony.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSignedIn,
    this.notice,
    this.initialMode = LoginMode.signIn,
  });

  final VoidCallback onSignedIn;

  /// Komunikat pokazywany nad formularzem, np. o wygasłej sesji.
  final String? notice;

  @visibleForTesting
  final LoginMode initialMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identity = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();

  late LoginMode _mode = widget.initialMode;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _error = widget.notice;
  }

  @override
  void dispose() {
    _identity.dispose();
    _username.dispose();
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    super.dispose();
  }

  void _switchTo(LoginMode mode) => setState(() {
    _mode = mode;
    _error = null;
    _info = null;
  });

  /// Sprawdza formularz przed wysłaniem i zwraca pierwszy problem.
  ///
  /// Walidacja jest tu, a nie tylko na serwerze, bo odpowiedź „nieprawidłowe
  /// dane" po sekundzie czekania nie mówi, KTÓRE pole jest nie tak.
  String? _validate() {
    switch (_mode) {
      case LoginMode.signIn:
        if (_identity.text.trim().isEmpty) return S.identityRequired;
        if (_password.text.isEmpty) return S.passwordTooShort;
      case LoginMode.reset:
        return _emailProblem(_email.text);
      case LoginMode.register:
        final username = _username.text.trim();
        if (username.isEmpty) return S.usernameRequired;
        if (username.length < 3) return S.usernameTooShort;
        if (!RegExp(r'^[\w][\w.]*$').hasMatch(username)) {
          return S.usernameInvalidChars;
        }
        if (_displayName.text.trim().isEmpty) return S.displayNameRequired;
        final emailProblem = _emailProblem(_email.text);
        if (emailProblem != null) return emailProblem;
        if (_password.text.length < 8) return S.passwordTooShort;
        if (_password.text != _passwordRepeat.text) {
          return S.passwordsDoNotMatch;
        }
    }
    return null;
  }

  static String? _emailProblem(String value) {
    final email = value.trim();
    if (email.isEmpty) return S.emailRequired;
    // Celowo luźne: e-maile bywają dziwniejsze niż każde wyrażenie regularne,
    // a ostatnie słowo i tak ma serwer. Chodzi o wyłapanie literówki.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return S.emailInvalid;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _validate();
    if (problem != null) {
      setState(() {
        _error = problem;
        _info = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    final services = AppServices.of(context);
    try {
      switch (_mode) {
        case LoginMode.reset:
          await services.api.requestPasswordReset(_email.text);
          if (mounted) setState(() => _info = S.resetPasswordSent);
        case LoginMode.signIn:
          final identity = await services.api.login(
            _identity.text,
            _password.text,
          );
          await _adopt(services, identity);
        case LoginMode.register:
          final identity = await services.api.register(
            username: _username.text,
            email: _email.text,
            password: _password.text,
            name: _displayName.text,
          );
          await _adopt(services, identity);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Live Ride: logowanie: $e\n$stack');
      if (mounted) setState(() => _error = S.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adopt(AppServices services, AccountIdentity identity) async {
    await services.profile.adoptAccount(
      username: identity.username,
      name: identity.name,
      email: identity.email,
    );
    if (mounted) widget.onSignedIn();
  }

  String get _title => switch (_mode) {
    LoginMode.signIn => S.signInTitle,
    LoginMode.register => S.registerTitle,
    LoginMode.reset => S.resetPasswordTitle,
  };

  String get _action => switch (_mode) {
    LoginMode.signIn => S.signIn,
    LoginMode.register => S.createAccountAction,
    LoginMode.reset => S.sendResetLink,
  };

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
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                // Adres serwera świadomie nie jest tutaj pokazywany: dla
                // rowerzysty to szum, a dla kogoś obok — informacja, gdzie
                // pukać.
                const SizedBox(height: 24),
                ..._fields(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    text: _error!,
                    color: LR.alert,
                    icon: Icons.error_outline,
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    text: _info!,
                    color: LR.accent,
                    icon: Icons.mark_email_read_outlined,
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
                      : Text(_action),
                ),
                const SizedBox(height: 4),
                ..._links(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _fields() {
    switch (_mode) {
      case LoginMode.signIn:
        return [
          _field(_identity, S.identityLabel, autofocus: true),
          const SizedBox(height: 12),
          _field(_password, S.password, obscure: true),
        ];
      case LoginMode.reset:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              S.resetPasswordIntro,
              style: const TextStyle(color: Color(0xFF8DA2B1), fontSize: 13),
            ),
          ),
          _field(
            _email,
            S.email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
          ),
        ];
      case LoginMode.register:
        return [
          _field(_username, S.username, autofocus: true),
          const SizedBox(height: 12),
          _field(_displayName, S.displayName, hint: S.displayNameHint),
          const SizedBox(height: 12),
          _field(_email, S.email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _field(_password, S.password, obscure: true),
          const SizedBox(height: 12),
          _field(_passwordRepeat, S.repeatPassword, obscure: true),
        ];
    }
  }

  List<Widget> _links() {
    final links = <(String, LoginMode)>[
      if (_mode == LoginMode.signIn) ...[
        (S.forgotPassword, LoginMode.reset),
        (S.createAccount, LoginMode.register),
      ],
      if (_mode == LoginMode.register) (S.haveAccount, LoginMode.signIn),
      if (_mode == LoginMode.reset) (S.backToSignIn, LoginMode.signIn),
    ];
    return [
      for (final (label, mode) in links)
        TextButton(
          onPressed: _busy ? null : () => _switchTo(mode),
          child: Text(label, style: const TextStyle(color: LR.accent)),
        ),
    ];
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    bool autofocus = false,
    String? hint,
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
      helperText: hint,
      helperStyle: const TextStyle(color: Color(0xFF7D93A4), fontSize: 11.5),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
