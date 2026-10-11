import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../radar/native_browser.dart';

// ============================================================================
// DeepSeek via le chat web (https://chat.deepseek.com/), piloté dans une
// WebView invisible : gratuit, sans clé API. Il partage la session (cookies)
// de la WebView visible : on se connecte une fois dans Paramètres → DeepSeek.
//
// ⚠️ Fragile par nature : si le site change, seuls les sélecteurs de [DsSite]
// sont à corriger. Ils n'ont PAS été testés sur le vrai site au moment de
// l'écriture : les boutons « Tester » des paramètres servent à ça.
// ============================================================================

/// Sélecteurs CSS et textes du site — à ajuster ici si DeepSeek change.
class DsSite {
  /// Le CHAT (et non le site vitrine www.deepseek.com).
  static const url = 'https://chat.deepseek.com/';
  static const chatHost = 'chat.deepseek.com';

  /// Zone de saisie du message.
  static const input = 'textarea';

  /// Bloc de réponse de l'IA (un par réponse).
  static const response = '.ds-markdown';

  /// Champ d'envoi de fichiers / de photos.
  static const fileInput = 'input[type="file"]';

  /// Page/texte qui trahit une session non connectée.
  static const loginHints = ['/sign_in', '/login', 'Log in', 'Se connecter', 'Sign up'];

  /// Texte qui trahit une vérification anti-robot.
  static const blockHints = ['captcha', 'verify you are human', 'Just a moment', 'vérifiez que vous êtes'];

  /// Texte qui trahit un serveur saturé.
  static const busyHints = ['Server is busy', 'server busy', 'serveur occupé', 'Too many requests'];

  /// Vrai pour le site vitrine (www.deepseek.com/en/…), qui n'est pas le chat.
  static bool isMarketingHost(String host) => host == 'deepseek.com' || host == 'www.deepseek.com';
}

/// Erreur DeepSeek. [fatal] : on suspend DeepSeek un moment (connexion perdue,
/// anti-robot, site changé) ; sinon l'erreur ne concerne que cette demande.
class DsException implements Exception {
  final String message;
  final bool fatal;
  DsException(this.message, {this.fatal = false});
  @override
  String toString() => message;
}

/// Extrait le premier objet JSON d'un texte de réponse (accepte les blocs
/// ```json, le texte autour, les en-têtes « json Copier » du site).
Map<String, dynamic> extractJsonObject(String text) {
  final a = text.indexOf('{');
  final b = text.lastIndexOf('}');
  if (a < 0 || b <= a) throw DsException('Réponse DeepSeek sans JSON.');
  final raw = text.substring(a, b + 1);
  try {
    final v = jsonDecode(raw);
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  throw DsException('JSON DeepSeek illisible.');
}

/// Vérifie que les clés « required » du schéma Gemini sont présentes.
String? missingRequiredKey(Map<String, dynamic> json, Map<String, dynamic> schema) {
  final req = (schema['required'] as List?) ?? const [];
  for (final k in req) {
    if (!json.containsKey(k)) return k.toString();
  }
  return null;
}

/// Fichier (photo, texte…) à joindre à une conversation DeepSeek.
class DsFile {
  final String name;
  final Uint8List bytes;
  final String mime;
  DsFile(this.name, this.bytes, {this.mime = 'text/plain'});
}

class DeepSeekWeb {
  static const _kEnabled = 'ds_enabled';
  static const _kChat = 'ds_chat';
  static const _kPhotos = 'ds_photos';
  static const _kVision = 'ds_vision_ok';

  static final _browser = NativeBrowser('deepseek');
  static Future<void> _queue = Future.value(); // une demande à la fois
  static DateTime? _downUntil;

  /// Dernier état connu, affiché dans les paramètres.
  static String lastStatus = 'pas encore utilisé';

  // ------------------------------------------------------------- réglages

  static Future<bool> _flag(String k) async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); // valeur à jour aussi dans le moteur du radar
    return p.getBool(k) ?? false;
  }

  static Future<void> _setFlag(String k, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(k, v);
  }

  static Future<bool> enabled() => _flag(_kEnabled);
  static Future<void> setEnabled(bool v) async {
    await _setFlag(_kEnabled, v);
    if (v) _downUntil = null;
  }

  /// DeepSeek aussi pour le chat « Questions » (sans recherche Google).
  static Future<bool> chatEnabled() => _flag(_kChat);
  static Future<void> setChatEnabled(bool v) => _setFlag(_kChat, v);

  /// Envoi des photos à DeepSeek (analyse visuelle) au lieu de Gemini.
  static Future<bool> photosEnabled() => _flag(_kPhotos);
  static Future<void> setPhotosEnabled(bool v) => _setFlag(_kPhotos, v);

  /// Le test « DeepSeek voit-il vraiment les photos ? » a réussi.
  static Future<bool> visionVerified() => _flag(_kVision);

  /// Réactive DeepSeek (après une reconnexion, par exemple).
  static void resume() => _downUntil = null;

  /// Activé et pas suspendu après une panne récente.
  static Future<bool> available() async {
    if (!await enabled()) return false;
    final d = _downUntil;
    return d == null || DateTime.now().isAfter(d);
  }

  /// DeepSeek utilisable pour les photos : activé, option cochée ET vision vérifiée.
  static Future<bool> photosAvailable() async =>
      await available() && await photosEnabled() && await visionVerified();

  // ------------------------------------------------------------ API haut niveau

  /// Équivalent de GeminiService.generateJson. [files] : photos ou documents joints.
  static Future<Map<String, dynamic>> generateJson(String prompt, Map<String, dynamic> schema,
      {List<DsFile> files = const []}) async {
    final full = '$prompt\n\n'
        'Réponds UNIQUEMENT par un objet JSON valide, sans aucun texte autour et sans bloc de code, '
        'qui respecte ce schéma (types en majuscules : STRING, NUMBER, BOOLEAN, ARRAY, OBJECT) :\n'
        '${jsonEncode(schema)}';
    String? lastProblem;
    for (var attempt = 0; attempt < 2; attempt++) {
      final text = await ask(
          attempt == 0
              ? full
              : '$full\n\nTa réponse précédente était inutilisable ($lastProblem). '
                  'Recommence : uniquement le JSON.',
          files: files);
      try {
        final j = extractJsonObject(text);
        final miss = missingRequiredKey(j, schema);
        if (miss == null) return j;
        lastProblem = 'clé « $miss » manquante';
      } on DsException catch (e) {
        lastProblem = e.message;
      }
    }
    throw DsException('DeepSeek : $lastProblem');
  }

  /// Équivalent de GeminiService.chat : la conversation est aplatie en un
  /// seul message (un nouveau chat DeepSeek par demande).
  static Future<String> chatText(String system, List<({String role, String text})> turns) =>
      ask(flattenConversation(system, turns));

  static String flattenConversation(String system, List<({String role, String text})> turns) {
    final b = StringBuffer('$system\n\nConversation jusqu\'ici :\n');
    for (final t in turns) {
      b.writeln('${t.role == 'user' ? 'Utilisateur' : 'Assistant'} : ${t.text}');
    }
    b.write('\nRéponds maintenant au dernier message de l\'utilisateur.');
    return b.toString();
  }

  /// Test complet (connexion, envoi, lecture) : rend un message lisible.
  static Future<String> test() async {
    final t0 = DateTime.now();
    try {
      final r = await ask('Réponds exactement par le mot : OK');
      final s = DateTime.now().difference(t0).inSeconds;
      return 'OK en $s s — réponse : ${r.trim().replaceAll('\n', ' ')}';
    } on DsException catch (e) {
      return 'Échec : ${e.message}';
    } catch (e) {
      return 'Échec : $e';
    }
  }

  /// Test de vision : envoie une image générée (fond et forme de couleurs tirées
  /// au hasard, sans texte) et vérifie que la réponse les décrit. Si oui, les
  /// photos pourront être envoyées à DeepSeek ; sinon elles restent à Gemini.
  static Future<({bool ok, String message})> testVision() async {
    final rnd = Random();
    const bgs = [
      ('jaune', 255, 214, 0, ['jaune', 'yellow']),
      ('bleu', 30, 100, 230, ['bleu', 'blue']),
      ('rose', 255, 105, 180, ['rose', 'pink']),
      ('noir', 15, 15, 15, ['noir', 'black']),
    ];
    const fgs = [
      ('rouge', 220, 30, 30, ['rouge', 'red']),
      ('vert', 30, 170, 60, ['vert', 'green']),
      ('blanc', 250, 250, 250, ['blanc', 'white']),
      ('orange', 255, 130, 0, ['orange']),
    ];
    final bg = bgs[rnd.nextInt(bgs.length)];
    final fg = fgs[rnd.nextInt(fgs.length)];
    final im = img.Image(width: 256, height: 256);
    img.fill(im, color: img.ColorRgb8(bg.$2, bg.$3, bg.$4));
    img.fillCircle(im, x: 128, y: 128, radius: 70, color: img.ColorRgb8(fg.$2, fg.$3, fg.$4));
    final png = Uint8List.fromList(img.encodePng(im));
    try {
      final r = (await ask(
              'Cette image montre une forme sur un fond uni. En une phrase : donne la couleur du fond, '
              'la couleur de la forme et le nom de la forme. Si tu ne reçois aucune image, dis-le.',
              files: [DsFile('test_vision.png', png, mime: 'image/png')]))
          .toLowerCase();
      final okBg = bg.$5.any(r.contains);
      final okFg = fg.$5.any(r.contains);
      final okShape = ['cercle', 'rond', 'disque', 'circle', 'round', 'dot'].any(r.contains);
      final ok = okBg && okFg && okShape;
      await _setFlag(_kVision, ok);
      return (
        ok: ok,
        message: ok
            ? 'DeepSeek voit bien les images (fond ${bg.$1}, cercle ${fg.$1} reconnus).'
            : 'DeepSeek n\'a pas décrit l\'image correctement (attendu : fond ${bg.$1}, cercle ${fg.$1}). '
                'Réponse : ${r.trim().replaceAll('\n', ' ')}'
      );
    } on DsException catch (e) {
      await _setFlag(_kVision, false);
      return (ok: false, message: 'Échec : ${e.message}');
    } catch (e) {
      await _setFlag(_kVision, false);
      return (ok: false, message: 'Échec : $e');
    }
  }

  // ------------------------------------------------------------------- noyau

  /// Ouvre un nouveau chat, envoie [prompt] (et [files] éventuels), rend la
  /// réponse. Les demandes sont traitées l'une après l'autre.
  static Future<String> ask(String prompt, {List<DsFile> files = const []}) {
    final done = Completer<String>();
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        done.complete(await askOn(_browser, prompt, files: files, newChat: true).timeout(
            Duration(seconds: 150 + 40 * files.length),
            onTimeout: () => throw DsException('DeepSeek ne répond pas (délai dépassé).')));
      } catch (e) {
        if (e is DsException && e.fatal) {
          _downUntil = DateTime.now().add(const Duration(minutes: 10));
        }
        lastStatus = e is DsException ? e.message : '$e';
        done.completeError(e);
      }
    });
    return done.future;
  }

  /// Envoie [prompt] dans l'onglet [b]. [newChat] : recharge d'abord la page de
  /// chat (nouvelle conversation) ; sinon continue la conversation en cours.
  static Future<String> askOn(NativeBrowser b, String prompt,
      {List<DsFile> files = const [], required bool newChat}) async {
    if (newChat) {
      final l = await b.load(DsSite.url, timeoutMs: 30000);
      if (!l.ok) throw DsException('DeepSeek : chargement impossible (${l.error}).');
      await _waitReady(b);
    } else {
      final s = await _state(b);
      if (s == null || s['hasInput'] != true) {
        throw DsException('DeepSeek : la conversation n\'est plus ouverte.');
      }
    }

    for (final f in files) {
      await _upload(b, f);
    }

    final before = await _state(b);
    final sent = await b.evalJson(_sendScript(prompt));
    if (sent == null || sent['ok'] != true) {
      throw DsException('DeepSeek : envoi impossible (${sent?['why'] ?? 'zone de saisie introuvable'}).',
          fatal: true);
    }

    // attente : un nouveau bloc de réponse apparaît, puis son texte se stabilise
    final deadline = DateTime.now().add(const Duration(seconds: 130));
    var lastText = '';
    var stable = 0;
    final baseCount = (before?['count'] as num?)?.toInt() ?? 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 1000));
      final s = await _state(b);
      if (s == null) continue;
      _checkPage(s);
      final count = (s['count'] as num?)?.toInt() ?? 0;
      final text = (s['text'] ?? '').toString();
      if (count <= baseCount || text.isEmpty) {
        if (_hasAny(s['body'], DsSite.busyHints)) {
          throw DsException('DeepSeek est saturé (serveur occupé).');
        }
        continue;
      }
      if (text == lastText) {
        stable++;
      } else {
        stable = 0;
        lastText = text;
      }
      if (stable >= 3) {
        lastStatus = 'OK (dernière réponse ${DateTime.now().toIso8601String().substring(11, 19)})';
        return text;
      }
    }
    throw DsException('DeepSeek : réponse trop longue ou bloquée.');
  }

  /// Attend que la page de chat (zone de saisie) soit prête, sinon : pas connecté.
  /// Si on a atterri sur le site vitrine (www.deepseek.com), on retourne sur le chat.
  static Future<void> _waitReady(NativeBrowser b) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var redirected = false;
    while (DateTime.now().isBefore(deadline)) {
      final s = await _state(b);
      if (s != null) {
        if (!redirected && DsSite.isMarketingHost((s['host'] ?? '').toString())) {
          redirected = true;
          await b.load(DsSite.url, timeoutMs: 30000);
          continue;
        }
        _checkPage(s);
        if (s['hasInput'] == true) return;
      }
      await Future.delayed(const Duration(milliseconds: 1000));
    }
    throw DsException('DeepSeek : zone de saisie introuvable (connecte-toi dans Paramètres ?).', fatal: true);
  }

  static void _checkPage(Map<String, dynamic> s) {
    // zone de saisie présente = page de chat normale : le texte de la page
    // (prompt, annonce, réponse) ne doit pas déclencher de faux positif
    if (s['hasInput'] == true) return;
    final url = (s['url'] ?? '').toString();
    final body = (s['body'] ?? '').toString();
    if (DsSite.loginHints.any((h) => url.contains(h)) || _hasAny(body, DsSite.loginHints)) {
      throw DsException('DeepSeek : session expirée, reconnecte-toi dans Paramètres.', fatal: true);
    }
    if (_hasAny(body, DsSite.blockHints)) {
      throw DsException('DeepSeek : vérification anti-robot à passer dans Paramètres.', fatal: true);
    }
  }

  static bool _hasAny(Object? haystack, List<String> needles) {
    final h = (haystack ?? '').toString().toLowerCase();
    return needles.any((n) => h.contains(n.toLowerCase()));
  }

  static Future<Map<String, dynamic>?> _state(NativeBrowser b) => b.evalJson('''
(() => {
  const blocks = document.querySelectorAll(${jsonEncode(DsSite.response)});
  const last = blocks.length ? blocks[blocks.length - 1] : null;
  return JSON.stringify({
    url: location.href,
    host: location.host,
    hasInput: !!document.querySelector(${jsonEncode(DsSite.input)}),
    count: blocks.length,
    text: last ? last.innerText : '',
    body: (document.body ? document.body.innerText : '').slice(0, 1500),
  });
})()
''');

  /// Remplit la zone de saisie (setter natif + événement input, comme React
  /// l'attend) puis envoie avec Entrée ; à défaut clique sur le bouton d'envoi.
  static String _sendScript(String prompt) => '''
(() => {
  const ta = document.querySelector(${jsonEncode(DsSite.input)});
  if (!ta) return JSON.stringify({ok: false, why: 'zone de saisie absente'});
  ta.focus();
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
  setter.call(ta, ${jsonEncode(prompt)});
  ta.dispatchEvent(new Event('input', {bubbles: true}));
  setTimeout(() => {
    const ev = (type) => new KeyboardEvent(type, {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true});
    ta.dispatchEvent(ev('keydown'));
    ta.dispatchEvent(ev('keyup'));
    setTimeout(() => {
      // si le texte est toujours là, l'Entrée n'a pas suffi : bouton d'envoi
      if (ta.value && ta.value.length > 0) {
        const btns = Array.from(document.querySelectorAll('div[role="button"], button'))
          .filter(b => !b.disabled && b.getAttribute('aria-disabled') !== 'true');
        const send = btns.reverse().find(b => b.querySelector('svg'));
        if (send) send.click();
      }
    }, 600);
  }, 400);
  return JSON.stringify({ok: true});
})()
''';

  static Future<void> _upload(NativeBrowser b, DsFile f) async {
    if (f.bytes.length > 5 * 1024 * 1024) {
      throw DsException('Fichier ${f.name} trop gros pour l\'envoi (5 Mo max).');
    }
    final r = await b.evalJson('''
(() => {
  const inp = document.querySelector(${jsonEncode(DsSite.fileInput)});
  if (!inp) return JSON.stringify({ok: false});
  const bin = atob(${jsonEncode(base64Encode(f.bytes))});
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  const file = new File([arr], ${jsonEncode(f.name)}, {type: ${jsonEncode(f.mime)}});
  const dt = new DataTransfer();
  dt.items.add(file);
  inp.files = dt.files;
  inp.dispatchEvent(new Event('change', {bubbles: true}));
  return JSON.stringify({ok: true});
})()
''');
    if (r == null || r['ok'] != true) {
      throw DsException('DeepSeek : champ d\'envoi de fichier introuvable.');
    }
    // attend que le nom du fichier apparaisse dans la page (envoi terminé)
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      final s = await _state(b);
      if (s != null && (s['body'] ?? '').toString().contains(f.name)) {
        await Future.delayed(const Duration(seconds: 2));
        return;
      }
    }
    throw DsException('DeepSeek : l\'envoi de ${f.name} n\'a pas abouti.');
  }
}

/// Conversation DeepSeek qui reste ouverte (onglet invisible à part) : la
/// première question part avec tout le contexte (et les photos), les suivantes
/// continuent dans le même chat sans rien renvoyer.
class DeepSeekChatSession {
  final NativeBrowser _b = NativeBrowser('deepseek_chat');
  bool _started = false;

  bool get started => _started;

  /// [firstPrompt] : message complet (contexte + historique) pour ouvrir le chat ;
  /// [followUp] : seulement la nouvelle question, si le chat est déjà ouvert.
  /// Si le chat a été perdu, on repart d'un nouveau avec [firstPrompt].
  Future<String> send(String firstPrompt, String followUp, {List<DsFile> files = const []}) async {
    Future<String> go(String prompt, bool fresh, List<DsFile> f) => DeepSeekWeb
        .askOn(_b, prompt, files: f, newChat: fresh)
        .timeout(Duration(seconds: 150 + 40 * f.length),
            onTimeout: () => throw DsException('DeepSeek ne répond pas (délai dépassé).'));
    if (_started) {
      try {
        return await go(followUp, false, const []);
      } on DsException {
        _started = false; // chat perdu : on rouvre avec tout le contexte
      }
    }
    final r = await go(firstPrompt, true, files);
    _started = true;
    return r;
  }

  Future<void> dispose() => _b.dispose();
}
