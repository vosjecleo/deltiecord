import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Reads a response without allowing an endpoint to grow process memory without
/// bound. The inactivity timeout is reset by each received chunk.
Future<Uint8List> readBoundedResponse(
  Stream<List<int>> response, {
  required int maximumBytes,
  Duration inactivityTimeout = const Duration(seconds: 10),
}) async {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(maximumBytes, 'maximumBytes');
  }
  final output = BytesBuilder(copy: false);
  await for (final chunk in response.timeout(inactivityTimeout)) {
    if (output.length + chunk.length > maximumBytes) {
      throw const HttpException('HTTP response exceeded its safe size limit.');
    }
    output.add(chunk);
  }
  return output.takeBytes();
}

bool hasContentType(HttpClientResponse response, Iterable<String> allowed) {
  final value = response.headers.contentType?.mimeType.toLowerCase();
  return value != null &&
      allowed.any((type) => value == type || value.startsWith('$type/'));
}
