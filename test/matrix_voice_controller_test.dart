import 'package:deltiecord/matrix/matrix_voice_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('audio output selection reaches platform and updates state', () async {
    final selector = _FakeAudioOutputSelector();
    final client = await _testClient();
    final controller = MatrixVoiceController(
      client,
      friendlyError: (error) => error.toString(),
      audioOutputSelector: selector,
    );

    await controller.selectAudioOutput('headphones');

    expect(selector.selections, ['headphones']);
    expect(controller.selectedAudioOutputId, 'headphones');
    expect(controller.error, isNull);
    controller.dispose();
    client.dispose();
  });

  test('audio output failure is visible and does not change state', () async {
    final selector = _FakeAudioOutputSelector(error: StateError('missing'));
    final client = await _testClient();
    final controller = MatrixVoiceController(
      client,
      friendlyError: (error) => 'Audio output unavailable',
      audioOutputSelector: selector,
    );

    await controller.selectAudioOutput('missing-device');

    expect(controller.selectedAudioOutputId, isNull);
    expect(controller.error, 'Audio output unavailable');
    controller.dispose();
    client.dispose();
  });
}

Future<Client> _testClient() async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  final sdkDatabase = await MatrixSdkDatabase.init(
    'deltiecord-output-test',
    database: database,
    sqfliteFactory: databaseFactoryFfi,
  );
  return Client('deltiecord-output-test', database: sdkDatabase);
}

final class _FakeAudioOutputSelector implements RtcAudioOutputSelector {
  _FakeAudioOutputSelector({this.error});

  final Object? error;
  final selections = <String>[];

  @override
  Future<void> select(String deviceId) async {
    selections.add(deviceId);
    if (error != null) throw error!;
  }
}
