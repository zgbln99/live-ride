import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';
import 'package:wanderer/components/base/wanderer_button.dart';
import 'package:wanderer/components/base/wanderer_text_field.dart';
import 'package:wanderer/models/api_error.dart';
import 'package:wanderer/provider/auth_provider.dart';
import 'package:wanderer/provider/toast_provider.dart';

import '/i18n/app_localizations.dart';

class LoginScreen extends ConsumerWidget {
  LoginScreen({super.key});

  final _formKey = GlobalKey<FormBuilderState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loginState = ref.watch(authProvider);
    final l10n = AppLocalizations.of(context)!;

    void submit() {
      if (_formKey.currentState?.saveAndValidate() ?? false) {
        final data = _formKey.currentState!.value;
        ref.read(authProvider.notifier).login(data['username'], data['password']);
      }
    }

    ref.listen(authProvider, (previous, next) {
      if (next is AsyncData && next.value != null) {
        TextInput.finishAutofillContext();
      }
      next.whenOrNull(
        error: (error, _) {
          String displayMessage = 'An unexpected error occurred';
          if (error is DioException) {
            try {
              final apiError = ApiError.fromJson(error.response?.data);
              displayMessage = apiError.message == 'Failed to authenticate.'
                  ? l10n.wrong_username_or_password
                  : apiError.message;
            } catch (_) {
              displayMessage = error.message ?? 'Network connection issue';
            }
          } else {
            displayMessage = error.toString();
          }
          ref.read(toastProvider.notifier).add(
                ToastMessage(
                  type: ToastType.error,
                  icon: FontAwesomeIcons.circleExclamation,
                  text: displayMessage,
                ),
              );
        },
      );
    });

    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF070B10) : const Color(0xFFF7FAFC);
    final fg = dark ? Colors.white : const Color(0xFF071018);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 8,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: FormBuilder(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUnfocus,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _LiveRideAuthHeader(),
                          const SizedBox(height: 34),
                          Text(
                            l10n.login,
                            style: TextStyle(
                              color: fg,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Zaloguj się do swojego Live Ride.',
                            style: TextStyle(
                              color: fg.withValues(alpha: .55),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 26),
                          WandererTextField(
                            name: 'username',
                            label: '${l10n.username}/${l10n.email}',
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: FormBuilderValidators.required(),
                          ),
                          const SizedBox(height: 12),
                          WandererTextField(
                            name: 'password',
                            label: l10n.password,
                            isPassword: true,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => submit(),
                            validator: FormBuilderValidators.compose([
                              FormBuilderValidators.required(),
                              FormBuilderValidators.minLength(8),
                            ]),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 54,
                            child: WandererButton(
                              primary: true,
                              large: true,
                              loading: loginState.isLoading,
                              onPressed: submit,
                              child: Text(l10n.login),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'ride.76-13-3-214.sslip.io',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: fg.withValues(alpha: .30),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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

class _LiveRideAuthHeader extends StatelessWidget {
  const _LiveRideAuthHeader();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF071018);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF18D9FF),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.navigation_rounded, size: 42, color: Color(0xFF061017)),
        ),
        const SizedBox(height: 16),
        Text(
          'LIVE RIDE',
          style: TextStyle(
            color: fg,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.8,
          ),
        ),
      ],
    );
  }
}
