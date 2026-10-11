import 'package:flutter_test/flutter_test.dart';
import 'package:mpb_check/services/deepseek_web.dart';

void main() {
  group('extractJsonObject', () {
    test('JSON nu', () {
      expect(extractJsonObject('{"a": 1}'), {'a': 1});
    });

    test('bloc de code avec en-tête du site', () {
      const t = 'json\nCopier\nTélécharger\n{"model": "Sony A6000", "ok": true}';
      expect(extractJsonObject(t)['model'], 'Sony A6000');
    });

    test('texte autour du JSON', () {
      expect(extractJsonObject('Voici :\n{"x": "y"}\nBonne journée')['x'], 'y');
    });

    test('pas de JSON → erreur', () {
      expect(() => extractJsonObject('désolé'), throwsA(isA<DsException>()));
    });

    test('JSON cassé → erreur', () {
      expect(() => extractJsonObject('{"a": }'), throwsA(isA<DsException>()));
    });
  });

  test('clés obligatoires du schéma', () {
    final schema = {'required': ['a', 'b']};
    expect(missingRequiredKey({'a': 1, 'b': 2}, schema), isNull);
    expect(missingRequiredKey({'a': 1}, schema), 'b');
  });

  test('site vitrine ≠ chat', () {
    expect(DsSite.isMarketingHost('www.deepseek.com'), isTrue);
    expect(DsSite.isMarketingHost('deepseek.com'), isTrue);
    expect(DsSite.isMarketingHost('chat.deepseek.com'), isFalse);
    expect(DsSite.url, startsWith('https://chat.deepseek.com'));
  });
}
