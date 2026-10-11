import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../secrets.dart';
import 'deepseek_web.dart';

class _KeyError implements Exception {}

/// Quota atteint (429) pour la clé en cours : on passe à la clé suivante.
class _QuotaError implements Exception {}

const _quotaMessage = 'Quota Gemini atteint sur toutes les clés. Réessaie dans quelques minutes.';

class _ModelError implements Exception {}

class _ToolError implements Exception {}

/// Réponse texte libre du chat, avec les sources web de la recherche Google.
class ChatReply {
  final String text;
  final List<({String uri, String title})> sources;
  final bool searched; // false si la recherche web a dû être désactivée
  ChatReply(this.text, this.sources, this.searched);
}


/// Appel à l'API Gemini avec réponse JSON imposée par un schéma.
/// - Modèles essayés dans l'ordre de [geminiModels] (repli si l'alias n'existe pas).
/// - Clés de [geminiKeys] (même compte) : on passe à la suivante si la clé en
///   cours est invalide ou si son quota est atteint (429) ; la clé qui marche est
///   gardée pour la suite de la session.
class GeminiService {
  final List<String> keys;
  final List<String> models;
  final http.Client _client;

  static int _keyIndex = 0; // clé valide mémorisée pour la session
  static String? _workingModel;

  GeminiService({List<String>? keys, List<String>? models, http.Client? client})
      : keys = keys ?? geminiKeys,
        models = models ?? geminiModels,
        _client = client ?? http.Client();

  /// [temperature] : 0 pour l'analyse (réponses stables), plus haut pour les
  /// messages aux vendeurs (jamais deux textes identiques).
  /// [images] : photos JPEG envoyées en inline_data (analyse des photos).
  Future<Map<String, dynamic>> generateJson(String prompt, Map<String, dynamic> schema,
      {double temperature = 0, List<Uint8List> images = const []}) async {
    // DeepSeek (chat web gratuit) d'abord pour le texte : ça économise le quota
    // Gemini. Les photos restent à Gemini (le chat web DeepSeek ne les « voit » pas).
    // Au moindre souci, on retombe sur les clés Gemini.
    if (images.isEmpty && await DeepSeekWeb.available()) {
      try {
        return await DeepSeekWeb.generateJson(prompt, schema);
      } catch (_) {
        // repli sur Gemini ci-dessous (DeepSeekWeb se suspend seul si la panne est durable)
      }
    }
    final modelOrder = [
      if (_workingModel != null) _workingModel!,
      ...models.where((m) => m != _workingModel),
    ];
    for (final model in modelOrder) {
      var quotaHits = 0;
      while (_keyIndex < keys.length) {
        try {
          final res =
              await _call(keys[_keyIndex], model, prompt, schema, temperature: temperature, images: images);
          _workingModel = model;
          return res;
        } on _KeyError {
          _keyIndex++; // clé invalide : on passe à la clé de secours suivante
        } on _QuotaError {
          // quota épuisé sur cette clé : clé suivante (toutes essayées → erreur)
          if (++quotaHits >= keys.length) throw Exception(_quotaMessage);
          _keyIndex = (_keyIndex + 1) % keys.length;
        } on _ModelError {
          break; // modèle inconnu : on essaie le modèle suivant
        }
      }
      if (_keyIndex >= keys.length) {
        _keyIndex = 0;
        throw Exception('Aucune clé Gemini valide (vérifie lib/secrets.dart).');
      }
    }
    throw Exception('Aucun modèle Gemini disponible : ${models.join(", ")}.');
  }

  Future<Map<String, dynamic>> _call(String key, String model, String prompt,
      Map<String, dynamic> schema, {double temperature = 0, List<Uint8List> images = const []}) async {
    final uri = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent');
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            for (final img in images) {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(img)}
            },
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        'responseMimeType': 'application/json',
        'responseSchema': schema,
      },
    });

    late http.Response r;
    for (var attempt = 0;; attempt++) {
      r = await _client
          .post(uri,
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
              body: body)
          .timeout(Duration(seconds: images.isEmpty ? 40 : 90));
      // limite par minute : on patiente un peu et on réessaie la même clé
      if (r.statusCode == 429 && attempt < 1) {
        await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
        continue;
      }
      break;
    }

    if (r.statusCode != 200) {
      String msg = r.body;
      try {
        msg = jsonDecode(r.body)['error']['message'].toString();
      } catch (_) {}
      final low = msg.toLowerCase();
      if (r.statusCode == 404 || (low.contains('model') && low.contains('not found'))) {
        throw _ModelError();
      }
      if (r.statusCode == 401 ||
          r.statusCode == 403 ||
          (r.statusCode == 400 && (low.contains('api key') || low.contains('api_key')))) {
        throw _KeyError();
      }
      if (r.statusCode == 429) throw _QuotaError();
      throw Exception('Gemini ${r.statusCode} : $msg');
    }

    final data = jsonDecode(utf8.decode(r.bodyBytes));
    final parts = (data['candidates']?[0]?['content']?['parts'] as List?) ?? [];
    final text = parts
        .where((p) => p['thought'] != true && p['text'] != null)
        .map((p) => p['text'].toString())
        .join();
    if (text.trim().isEmpty) throw Exception('Réponse Gemini vide.');
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// Test d'une clé (test global), sans toucher à la clé en cours de l'appli.
  /// Rend « OK », « quota atteint », « invalide » ou le message d'erreur.
  Future<String> testKey(String key) async {
    final model = _workingModel ?? models.first;
    try {
      await _call(key, model, 'Réponds {"ok": true}.',
          const {'type': 'OBJECT', 'properties': {'ok': {'type': 'BOOLEAN'}}});
      return 'OK';
    } on _QuotaError {
      return 'quota atteint';
    } on _KeyError {
      return 'invalide';
    } on _ModelError {
      return 'modèle $model indisponible';
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  // ------------------------------------------------------------------ chat

  /// Conversation libre (pas de responseSchema) avec l'outil Google Search.
  /// Ordre : modèles flash-lite de [geminiModels] avec recherche, puis sans outil. Mêmes clés (et bascule sur quota) que [generateJson].
  Future<ChatReply> chat(
      String systemInstruction, List<({String role, String text})> turns,
      {bool allowDeepSeek = true}) async {
    // Chat via DeepSeek seulement si activé dans les réglages (pas de recherche Google).
    if (allowDeepSeek && await DeepSeekWeb.available() && await DeepSeekWeb.chatEnabled()) {
      try {
        return ChatReply(await DeepSeekWeb.chatText(systemInstruction, turns), const [], false);
      } catch (_) {
        // repli sur Gemini ci-dessous
      }
    }
    final primary = [
      if (_workingModel != null) _workingModel!,
      ...models.where((m) => m != _workingModel),
    ];
    final attempts = <({String model, bool search})>[
      for (final m in primary) (model: m, search: true),
      for (final m in primary) (model: m, search: false),
    ];
    Object? lastError;
    for (final a in attempts) {
      var quotaHits = 0;
      while (_keyIndex < keys.length) {
        try {
          return await _chatCall(keys[_keyIndex], a.model, systemInstruction, turns, a.search);
        } on _KeyError {
          _keyIndex++;
        } on _QuotaError {
          if (++quotaHits >= keys.length) throw Exception(_quotaMessage);
          _keyIndex = (_keyIndex + 1) % keys.length;
        } on _ModelError catch (e) {
          lastError = e;
          break;
        } on _ToolError catch (e) {
          lastError = e;
          break;
        }
      }
      if (_keyIndex >= keys.length) {
        _keyIndex = 0;
        throw Exception('Aucune clé Gemini valide (vérifie lib/secrets.dart).');
      }
    }
    throw Exception(lastError is _ToolError
        ? 'Gemini refuse la requête, même sans recherche web.'
        : 'Aucun modèle Gemini disponible pour le chat.');
  }

  Future<ChatReply> _chatCall(String key, String model, String system,
      List<({String role, String text})> turns, bool search) async {
    final uri = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent');
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': [
        for (final t in turns)
          {
            'role': t.role,
            'parts': [
              {'text': t.text}
            ]
          }
      ],
      if (search)
        'tools': [
          {'google_search': {}}
        ],
      'generationConfig': {'temperature': 0.4},
    });

    late http.Response r;
    for (var attempt = 0;; attempt++) {
      r = await _client
          .post(uri,
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
              body: body)
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 429 && attempt < 1) {
        await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
        continue;
      }
      break;
    }

    if (r.statusCode != 200) {
      String msg = r.body;
      try {
        msg = jsonDecode(r.body)['error']['message'].toString();
      } catch (_) {}
      final low = msg.toLowerCase();
      if (r.statusCode == 404 || (low.contains('model') && low.contains('not found'))) {
        throw _ModelError();
      }
      if (r.statusCode == 401 ||
          r.statusCode == 403 ||
          (r.statusCode == 400 && (low.contains('api key') || low.contains('api_key')))) {
        throw _KeyError();
      }
      if (r.statusCode == 429) throw _QuotaError();
      if (search &&
          r.statusCode == 400 &&
          (low.contains('tool') || low.contains('search') || low.contains('grounding'))) {
        throw _ToolError();
      }
      throw Exception('Gemini ${r.statusCode} : $msg');
    }

    final data = jsonDecode(utf8.decode(r.bodyBytes));
    final cand = (data['candidates'] as List?)?.firstOrNull;
    final parts = (cand?['content']?['parts'] as List?) ?? [];
    final text = parts
        .where((p) => p['thought'] != true && p['text'] != null)
        .map((p) => p['text'].toString())
        .join()
        .trim();
    if (text.isEmpty) throw Exception('Réponse Gemini vide.');

    final sources = <({String uri, String title})>[];
    final seen = <String>{};
    for (final c in (cand?['groundingMetadata']?['groundingChunks'] as List?) ?? []) {
      final web = c['web'];
      final u = web?['uri']?.toString();
      if (u == null || u.isEmpty || !seen.add(u)) continue;
      final t = web['title']?.toString() ?? '';
      sources.add((uri: u, title: t.isEmpty ? Uri.tryParse(u)?.host ?? u : t));
    }
    return ChatReply(text, sources, search);
  }
}
