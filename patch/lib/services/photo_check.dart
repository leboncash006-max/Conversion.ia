import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models.dart';
import 'deepseek_web.dart';
import 'gemini_service.dart';
import 'v3_models.dart';

/// Analyse des photos de l'annonce par Gemini (gemini-flash-lite-latest) :
/// modèle visible, cohérence avec l'annonce, état visuel, défauts, accessoires.
/// Jusqu'à 6 photos, redimensionnées à ~1024 px et envoyées en JPEG.
class PhotoChecker {
  static const maxPhotos = 6;
  static const maxSide = 1024;

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'modele_visible': {'type': 'STRING'},
      'coherent_avec_annonce': {
        'type': 'STRING',
        'enum': ['oui', 'non', 'doute'],
      },
      'raison': {'type': 'STRING'},
      'etat_visuel': {
        'type': 'STRING',
        'enum': ['like-new', 'excellent', 'good', 'well-used', 'heavily-used', 'inconnu'],
      },
      'defauts': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'type': {'type': 'STRING'},
            'gravite': {
              'type': 'STRING',
              'enum': ['mineur', 'majeur'],
            },
            'photo_index': {'type': 'INTEGER'},
          },
          'required': ['type', 'gravite'],
        },
      },
      'accessoires_visibles': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': ['modele_visible', 'coherent_avec_annonce', 'raison', 'etat_visuel', 'defauts', 'accessoires_visibles'],
  };

  final GeminiService gemini;
  final http.Client _http;
  PhotoChecker(this.gemini, {http.Client? client}) : _http = client ?? http.Client();

  /// Télécharge et réduit les photos (dans un isolat : pas de saccade).
  Future<(List<String>, List<Uint8List>)> _download(List<String> urls) async {
    final okUrls = <String>[];
    final out = <Uint8List>[];
    for (final u in urls.take(maxPhotos)) {
      try {
        final r = await _http.get(Uri.parse(u), headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14)'}).timeout(
            const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) continue;
        final jpg = await compute(_shrink, r.bodyBytes);
        if (jpg == null) continue;
        okUrls.add(u);
        out.add(jpg);
      } catch (_) {}
    }
    return (okUrls, out);
  }

  /// Photos réduites (JPEG ~1024 px), par exemple pour le chat DeepSeek.
  Future<List<Uint8List>> downloadPhotos(List<String> urls, {int max = 4}) async {
    final (_, photos) = await _download(urls.take(max).toList());
    return photos;
  }

  /// Analyse. null si aucune photo n'a pu être lue (l'analyse continue sans).
  Future<PhotoCheck?> check(List<String> urls, String title, String description, Analysis a) async {
    if (urls.isEmpty) return null;
    final (okUrls, photos) = await _download(urls);
    if (photos.isEmpty) return null;
    final models = a.items.map((i) => '- ${i.item.type} : ${i.mpbModel ?? i.item.nameGuess}').join('\n');
    final prompt = '''
Tu es expert en matériel photo d'occasion. Voici ${photos.length} photo(s) d'une annonce Leboncoin
(photo_index 0 = première photo).
Titre : $title
Description : """
${description.length > 1500 ? description.substring(0, 1500) : description}
"""
Modèles identifiés :
$models

Réponds :
- modele_visible : le ou les modèles que tu vois (marque, référence lisible), "" si illisible.
- coherent_avec_annonce : « oui » si les photos montrent bien les modèles identifiés, « non » si
  c'est clairement autre chose (autre modèle, autre marque, compact au lieu d'un reflex…),
  « doute » si on ne peut pas trancher (photo floue, référence invisible, photo de catalogue).
- etat_visuel (barème MPB) : like-new (aucune trace), excellent (traces infimes), good (traces
  d'usage légères), well-used (usure nette, rayures), heavily-used (très usé, chocs), inconnu.
- defauts : chaque défaut VISIBLE avec sa gravité. majeur = écran cassé ou fissuré, lentille
  rayée, champignon, buée dans l'objectif, pièce cassée ou manquante, choc important.
  mineur = petites rayures sur le boîtier, usure de la peinture, caoutchouc décollé.
  photo_index = numéro de la photo où on le voit.
- accessoires_visibles : batterie, chargeur, bouchons, pare-soleil, boîte, sangle…
Ne devine pas : ne signale que ce qui se voit.''';
    // DeepSeek (chat web gratuit) d'abord si l'option est cochée ET que le test de
    // vision a réussi ; au moindre doute (pas d'image reçue, erreur), Gemini prend le relais.
    if (await DeepSeekWeb.photosAvailable()) {
      final n = photos.length < dsMaxPhotos ? photos.length : dsMaxPhotos; // moins de photos = envoi plus rapide
      try {
        final j = await DeepSeekWeb.generateJson(
          '$prompt\n\nIMPORTANT : $n photo(s) sont jointes à ce message. Si tu ne les vois pas '
          '(aucune image reçue), réponds modele_visible \"\", coherent_avec_annonce \"doute\", '
          'etat_visuel \"inconnu\", raison \"aucune image reçue\", defauts [] et accessoires_visibles [].',
          _schema,
          files: [
            for (var i = 0; i < n; i++) DsFile('photo_${i + 1}.jpg', photos[i], mime: 'image/jpeg'),
          ],
        );
        if (!_noImageSeen(j)) return PhotoCheck.fromJson(j, images: okUrls.take(n).toList());
      } catch (_) {
        // repli sur Gemini ci-dessous
      }
    }
    final j = await gemini.generateJson(prompt, _schema, images: photos);
    return PhotoCheck.fromJson(j, images: okUrls);
  }

  /// DeepSeek a répondu qu'il n'a reçu aucune image : résultat inutilisable.
  static bool _noImageSeen(Map<String, dynamic> j) {
    final raison = (j['raison'] ?? '').toString().toLowerCase();
    return RegExp(r"aucune image|pas d'image|no image|n'ai pas (reçu|vu)").hasMatch(raison);
  }

  /// Nombre maximal de photos envoyées à DeepSeek (envoi une par une, donc plus lent).
  static const dsMaxPhotos = 4;
}

/// Décode, réduit à [PhotoChecker.maxSide] px et réencode en JPEG (qualité 80).
Uint8List? _shrink(Uint8List bytes) {
  try {
    final im = img.decodeImage(bytes);
    if (im == null) return null;
    final big = im.width > im.height ? im.width : im.height;
    final resized = big <= PhotoChecker.maxSide
        ? im
        : (im.width >= im.height
            ? img.copyResize(im, width: PhotoChecker.maxSide)
            : img.copyResize(im, height: PhotoChecker.maxSide));
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  } catch (_) {
    return null;
  }
}
