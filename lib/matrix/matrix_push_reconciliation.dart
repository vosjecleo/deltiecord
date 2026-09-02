import 'package:matrix/matrix.dart';

import '../services/unified_push.dart';

const _deltiecordPusherAppId = 'net.deltie.deltiecord';

enum MatrixPusherReconciliation { verified, repaired }

/// Verifies that Matrix points at the distributor's current private endpoint.
///
/// Endpoint rotation is expected UnifiedPush behavior. The capability is
/// compared only in memory and is never included in diagnostics or logs.
Future<MatrixPusherReconciliation> reconcileMatrixUnifiedPushPusher(
  Client client,
  String endpoint,
) async {
  final normalized = normalizeUnifiedPushEndpoint(endpoint);
  final gateway = matrixPushGatewayForUnifiedPushEndpoint(endpoint);
  final deviceId = client.deviceID;
  if (!client.isLogged() ||
      normalized == null ||
      gateway == null ||
      deviceId == null) {
    throw StateError(
      'A signed-in Matrix device and valid endpoint are required.',
    );
  }
  final profileTag = 'mobile_$deviceId';

  bool matches(Pusher pusher) =>
      pusher.appId == _deltiecordPusherAppId &&
      pusher.profileTag == profileTag &&
      pusher.pushkey == normalized &&
      pusher.kind == 'http' &&
      pusher.data.url == gateway &&
      pusher.data.format == 'event_id_only';

  final existing = await client.getPushers() ?? const <Pusher>[];
  final current = existing.any(matches);
  final stale = existing.where(
    (pusher) =>
        pusher.appId == _deltiecordPusherAppId &&
        pusher.profileTag == profileTag &&
        !matches(pusher),
  );
  var cleanedStalePusher = false;
  for (final pusher in stale) {
    await client.deletePusher(
      PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
    );
    cleanedStalePusher = true;
  }
  if (current) {
    return cleanedStalePusher
        ? MatrixPusherReconciliation.repaired
        : MatrixPusherReconciliation.verified;
  }

  await client.postPusher(
    Pusher(
      appId: _deltiecordPusherAppId,
      pushkey: normalized,
      appDisplayName: 'Deltiecord',
      deviceDisplayName: 'Deltiecord Android',
      kind: 'http',
      lang: 'en',
      profileTag: profileTag,
      data: PusherData(
        url: gateway,
        format: 'event_id_only',
        additionalProperties: {'client_name': client.clientName},
      ),
    ),
    append: true,
  );
  final verified = await client.getPushers() ?? const <Pusher>[];
  if (!verified.any(matches)) {
    throw StateError('Matrix did not retain the refreshed pusher.');
  }
  return MatrixPusherReconciliation.repaired;
}
