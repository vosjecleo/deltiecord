import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _homeserver = TextEditingController(text: 'https://matrix.deltie.net');
  final _username = TextEditingController();
  final _password = TextEditingController();

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final uri = normalizedHomeserverUri(_homeserver.text);
    if (uri == null) return;
    await widget.backend.login(
      homeserver: uri,
      username: normalizedMatrixLoginName(_username.text),
      password: _password.text,
    );
    if (widget.backend.status == SessionStatus.signedIn) {
      TextInput.finishAutofillContext();
    }
  }

  @override
  void dispose() {
    _homeserver.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.backend.status == SessionStatus.signingIn;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.forum_rounded,
                          size: 54,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Deltiecord',
                          style: Theme.of(context).textTheme.headlineLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to Matrix',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _homeserver,
                          autofillHints: const [AutofillHints.url],
                          keyboardType: TextInputType.url,
                          enabled: !loading,
                          decoration: const InputDecoration(
                            labelText: 'Homeserver',
                            hintText: 'https://matrix.example.org',
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            final uri = normalizedHomeserverUri(value ?? '');
                            return uri == null
                                ? 'Enter a valid homeserver address.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _username,
                          autofillHints: const [AutofillHints.username],
                          enabled: !loading,
                          decoration: const InputDecoration(
                            labelText: 'Username or Matrix ID',
                            border: InputBorder.none,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your username.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          autofillHints: const [AutofillHints.password],
                          enabled: !loading,
                          obscureText: true,
                          onFieldSubmitted: (_) {
                            if (!loading) _login();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: InputBorder.none,
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password.'
                              : null,
                        ),
                        if (widget.backend.error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: loading ? null : _login,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Text(loading ? 'Signing in…' : 'Sign in'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Deltiecord works with compatible Matrix homeservers. '
                          'A custom server may not provide Deltiecord’s dedicated '
                          'push endpoint, media conversion, or link-preview service, '
                          'and server policy can limit uploads or account features.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accepts the hostname-oriented input people commonly use for homeservers.
Uri? normalizedHomeserverUri(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final withScheme = value.contains('://') ? value : 'https://$value';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) return null;
  return uri;
}

/// Synapse accepts a localpart consistently even when deployments reject a
/// fully-qualified Matrix ID in the password-login identifier.
String normalizedMatrixLoginName(String input) {
  final value = input.trim();
  if (!value.startsWith('@')) return value;
  final separator = value.indexOf(':', 1);
  return separator > 1 ? value.substring(1, separator) : value;
}
