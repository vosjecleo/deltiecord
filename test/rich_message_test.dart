import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/ui/rich_message.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes rich text and Matrix spoilers with a plain fallback', () {
    final document = Document()..insert(0, 'bold secret');
    document.format(0, 4, Attribute.bold);
    document.format(5, 6, const BackgroundAttribute(spoilerEditorColor));

    final message = serializeRichMessage(document);

    expect(message.plainText, 'bold secret');
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('data-mx-spoiler'));
    expect(message.html, isNot(contains(spoilerEditorColor)));
  });

  test('converts typed markup without exposing formatting controls', () {
    final document = Document()..insert(0, '**bold** _italic_ ||hidden||');

    final message = serializeRichMessage(document);

    expect(message.plainText, '**bold** _italic_ ||hidden||');
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('<em>italic</em>'));
    expect(message.html, contains('data-mx-spoiler'));
  });

  test('keeps filesystem paths as literal plain text', () {
    final document = Document()
      ..insert(0, 'sudo apt install /path/to/deltiecord_0.3.6_amd64.deb');

    final message = serializeRichMessage(document);

    expect(
      message.plainText,
      'sudo apt install /path/to/deltiecord_0.3.6_amd64.deb',
    );
    expect(message.html, isNull);
  });

  test('serializes linked composer emoji as Matrix inline media', () {
    final emoji = CustomEmojiReference(
      id: Uri(scheme: 'mxc', host: 'example.org', path: '/stable'),
      name: 'wave',
    );
    final document = Document()..insert(0, ':wave:');
    document.format(0, 6, LinkAttribute(customEmojiEditorLink(emoji)));

    final message = serializeRichMessage(document);

    expect(message.plainText, ':wave:');
    expect(message.html, contains('data-mx-emoticon'));
    expect(message.html, contains('mxc://example.org/stable'));
    expect(message.html, isNot(contains('emoji.deltiecord.invalid')));
  });

  testWidgets('rich paragraphs do not retain an empty trailing row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MatrixHtmlText(
              html: '<p>sudo apt install /path/to/file_name.deb</p>',
              fallback: 'sudo apt install /path/to/file_name.deb',
            ),
          ),
        ),
      ),
    );

    final height = tester.getSize(find.byType(SelectableText)).height;
    expect(height, lessThan(30));
  });
}
