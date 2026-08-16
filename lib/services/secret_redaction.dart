/// Removes credentials and secret-bearing local URLs before text reaches logs,
/// diagnostics, or user-visible error surfaces.
String redactSecrets(String input) {
  var output = input;
  output = output.replaceAllMapped(
    RegExp(
      r'(authorization\s*[:=]\s*bearer\s+)[^\s,;}]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  output = output.replaceAllMapped(
    RegExp(r'(bearer\s+)[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  output = output.replaceAllMapped(
    RegExp(
      r'([?&](?:access_token|token|key|iv|recovery_key)=)[^&#\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  output = output.replaceAllMapped(
    RegExp(
      r'''((?:"|')?(?:access_token|authorization|recovery_key|cross_signing_key|media_key|iv)(?:"|')?\s*:\s*(?:"|'))[^"']+''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  output = output.replaceAll(
    RegExp(r'https?://(?:127\.0\.0\.1|\[::1\]):\d+/media/[A-Za-z0-9_-]+'),
    'http://loopback/media/[REDACTED]',
  );
  return output;
}

String safeErrorMessage(Object error, {int maximumLength = 240}) {
  final text = redactSecrets(
    error.toString().replaceFirst(RegExp(r'^(?:Exception|Error):\s*'), ''),
  );
  return text.length > maximumLength
      ? '${text.substring(0, maximumLength)}…'
      : text;
}
