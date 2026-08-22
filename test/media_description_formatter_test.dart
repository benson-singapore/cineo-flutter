import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/text/media_description_formatter.dart';

void main() {
  test('converts safe HTML descriptions into readable paragraphs', () {
    expect(
      formatMediaDescription(
        '<p>第一段&nbsp;&amp; 片名</p><p>第二段<br>继续</p>',
      ),
      '第一段 & 片名\n\n第二段\n继续',
    );
  });

  test('removes comments, scripts, styles, and remaining tags', () {
    expect(
      formatMediaDescription(
        '<!-- hidden --><style>.x { color: red; }</style>'
        '<p>可见内容</p><script>alert("ignored")</script>'
        '<span>后续</span>',
      ),
      '可见内容\n后续',
    );
  });

  test('decodes named, decimal, and hexadecimal entities', () {
    expect(
      formatMediaDescription(
        '&quot;Cineo&quot; &#x4F60;&#22909; &lt;片名&gt; &copy; &#x1F3AC;',
      ),
      '"Cineo" 你好 <片名> © 🎬',
    );
  });

  test('normalizes whitespace and repeated blank lines', () {
    expect(
      formatMediaDescription('  第一行 \t\n\n\n <div> 第二行 </div>  '),
      '第一行\n\n第二行',
    );
  });

  test('returns empty text for blank input and invalid numeric entities', () {
    expect(formatMediaDescription(' \n\t '), isEmpty);
    expect(
        formatMediaDescription('&#x110000; &#xD800;'), '&#x110000; &#xD800;');
  });
}
