import 'dart:io';

import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deltiecordRoomPresentationEventType = 'net.deltiecord.room.presentation';
const deltiecordSpaceChannelsEventType = 'net.deltiecord.space.channels';

/// Creates the Matrix SDK client and its platform-appropriate persistent store.
///
/// Session tokens, Olm state, and cached room keys stay in the application data
/// directory rather than the repository. Desktop SQLite uses the FFI factory;
/// Android can use the native sqflite plugin through the same SDK database.
Future<Client> createMatrixClient() async {
  final dataDirectory = await getDeltiecordDataDirectory();
  await dataDirectory.create(recursive: true);
  await _restrictPermissions(dataDirectory.path, '700');

  final databasePath = p.join(dataDirectory.path, 'matrix.db');
  late final sqflite.Database database;
  DatabaseFactory? ffiFactory;
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    ffiFactory = databaseFactoryFfi;
    database = await ffiFactory.openDatabase(databasePath);
  } else {
    database = await sqflite.openDatabase(databasePath);
  }
  await _restrictPermissions(databasePath, '600');

  final sdkDatabase = await MatrixSdkDatabase.init(
    'deltiecord',
    database: database,
    sqfliteFactory: ffiFactory,
    fileStorageLocation: dataDirectory.uri,
  );
  return Client(
    'Deltiecord',
    database: sdkDatabase,
    // Room presentation controls whether a room exposes a timeline/composer or
    // MatrixRTC controls. Load it with the initial room state so a fresh device
    // cannot briefly (or permanently, without another rebuild) treat a voice
    // room as a text room while the SDK lazily hydrates custom state.
    importantStateEvents: {
      deltiecordRoomPresentationEventType,
      deltiecordSpaceChannelsEventType,
    },
    // Deltiecord warns about verification separately. Excluding an unverified
    // device here would create ciphertext its owner cannot decrypt.
    shareKeysWith: ShareKeysWith.all,
  );
}

Future<Directory> getDeltiecordDataDirectory() async {
  final supportDirectory = await getApplicationSupportDirectory();
  return Directory(p.join(supportDirectory.path, 'deltiecord'));
}

Future<void> _restrictPermissions(String path, String mode) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('Could not secure Deltiecord data', path);
  }
}
