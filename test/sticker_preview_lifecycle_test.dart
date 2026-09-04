import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed sticker preview futures complete instead of awaiting themselves',
    () async {
      final backend = MatrixBackend();
      addTearDown(backend.dispose);
      final sticker = StickerSummary(
        id: 'missing',
        name: 'missing',
        mxcUri: Uri.parse('mxc://example.org/missing'),
      );

      final results = await Future.wait([
        backend.loadStickerPreview(sticker),
        backend.loadStickerPreview(sticker),
      ]).timeout(const Duration(seconds: 1));

      expect(results, [null, null]);
    },
  );
}
