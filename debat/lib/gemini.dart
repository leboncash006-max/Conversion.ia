import 'dart:convert';

import 'package:http/http.dart' as http;

import 'data.dart';

/// Appels à l'API Gemini. Aucune consigne n'est écrite en dur ici :
/// les instructions viennent uniquement des réglages de l'utilisateur,
/// plus un bloc de contexte factuel (partis, orientations, sujet).
class Gemini {
  static Future<Map<String, dynamic>> _call(
      Settings s, Map<String, dynamic> body) async {
    if (s.apiKey.trim().isEmpty) {
      throw Exception('Aucune clé API : ajoute-la dans les paramètres.');
    }
    final uri = Uri.https(
        'generativelanguage.googleapis.com', '/v1beta/models/${s.model.trim()}:generateContent');
    final r = await http
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': s.apiKey.trim(),
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      var msg = r.body;
      try {
        msg = jsonDecode(r.body)['error']['message'];
      } catch (_) {}
      throw Exception('Gemini ${r.statusCode} : $msg');
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static String _text(Map<String, dynamic> j) {
    final c = j['candidates'] as List?;
    final parts = (c == null || c.isEmpty) ? null : c[0]['content']?['parts'] as List?;
    if (parts == null) {
      throw Exception('Réponse vide (bloquée par les filtres de Gemini ?)');
    }
    return parts.map((p) => p['text'] ?? '').join().trim();
  }

  /// Réponse de l'adversaire.
  static Future<String> opponent(
      Settings s, String system, List<Msg> messages) async {
    final body = <String, dynamic>{
      if (system.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
      'contents': [
        for (final m in messages)
          {
            'role': m.role == 'me' ? 'user' : 'model',
            'parts': [
              {'text': m.text}
            ]
          }
      ],
    };
    return _text(await _call(s, body));
  }

  /// Réaction du public (réponse JSON structurée par schéma).
  static Future<({int shift, String comment})> audience(
      Settings s, String system, String transcript) async {
    final body = <String, dynamic>{
      if (system.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': transcript}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'shift': {
              'type': 'INTEGER',
              'description':
                  'Variation du public entre -15 et 15. Positif = le public penche vers le joueur humain, négatif = vers l\'adversaire.'
            },
            'comment': {
              'type': 'STRING',
              'description': 'Réaction courte d\'un spectateur (une phrase).'
            },
          },
          'required': ['shift', 'comment'],
        },
      },
    };
    final j = jsonDecode(_text(await _call(s, body)));
    final shift = ((j['shift'] as num?) ?? 0).toInt().clamp(-15, 15);
    return (shift: shift, comment: (j['comment'] ?? '').toString());
  }
}
