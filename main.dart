// ============================================================
//  Messagerie façon WhatsApp avec une IA 100 % locale
//  (flutter_litert_lm + path_provider uniquement)
//
//  - Plusieurs contacts IA (nom, âge >= 18, personnalité, couleur)
//  - Conversations sauvegardées sur le téléphone
//  - Gestionnaire de modèles : Qwen 2.5 1.5B, Qwen 3 0.6B,
//    un modèle non censuré (abliterated) et un dépôt Hugging Face libre
//  - Choix CPU / GPU, temps de réponse affiché
//  - Photo de profil par contact, mémoire persistante de l'IA,
//    plusieurs messages d'affilée et temps d'écriture simulé
//  - Relances spontanées, groupes de discussion, vocal (lecture +
//    dictée), sauvegarde / restauration, recherche dans les messages
//  - Messages vocaux de l'IA : voix neuronale hors ligne (ado 14-15 ans
//    par défaut), expressive selon le ton de chaque phrase
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const MessengerApp());

const _waGreen = Color(0xFF075E54);
const _waLight = Color(0xFF25D366);
const _bubbleMe = Color(0xFFDCF8C6);
const _chatBg = Color(0xFFECE5DD);

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IA Messenger',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: _waGreen,
          appBarTheme: const AppBarTheme(
            backgroundColor: _waGreen,
            foregroundColor: Colors.white,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: _waLight,
            foregroundColor: Colors.white,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: _waGreen,
          appBarTheme: const AppBarTheme(
            backgroundColor: _waGreen,
            foregroundColor: Colors.white,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: _waLight,
            foregroundColor: Colors.white,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const Bootstrap(),
      );
}

// ---------------------------------------------------------------
//  Modèles
// ---------------------------------------------------------------
class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    required this.note,
    this.url,
    this.repo,
    this.sizeBytes = 0,
  });
  final String id;
  final String name;
  final String note;
  final String? url; // URL directe, ou…
  final String? repo; // …dépôt Hugging Face dont on prend le 1er .litertlm
  final int sizeBytes;
}

const _customId = 'custom';

const baseModels = <ModelOption>[
  ModelOption(
    id: 'qwen25-1.5b',
    name: 'Qwen 2.5 1.5B',
    note: '1,6 Go · recommandé, rapide',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    sizeBytes: 1604270080,
  ),
  ModelOption(
    id: 'qwen3-0.6b',
    name: 'Qwen 3 0.6B',
    note: '0,6 Go · très léger',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    sizeBytes: 614235648,
  ),
  ModelOption(
    id: 'qwen35-4b-abliterated',
    name: 'Qwen 3.5 4B non censuré',
    note: 'abliterated · lourd (≈ 3-4 Go), lent sur 6 Go de RAM',
    repo: 'DuoNeural/Qwen3.5-4B-Abliterated-LiteRT-LM',
  ),
];

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.age,
    required this.description,
    required this.color,
    this.script = '',
    this.photo,
    this.length = 1,
    this.multi = true,
    this.memoryOn = true,
    this.isGroup = false,
    this.nudge = true,
    this.nudges = 0,
    this.unread = 0,
    this.autoSpeak = false,
    this.pitch = 1.0,
    this.vocal = true,
    this.voice = 'ado',
    List<String>? members,
    List<String>? memory,
    List<Msg>? messages,
  })  : members = members ?? [],
        memory = memory ?? [],
        messages = messages ?? [];

  final String id;
  String name;
  int age;
  String description; // personnalité, ou sujet du groupe
  int color;
  String script; // réponses préenregistrées (texte du .txt importé)
  String? photo; // nom du fichier image dans le dossier de l'app
  int length; // 0 = messages courts, 1 = variable, 2 = longs
  bool multi; // l'IA peut envoyer plusieurs messages d'affilée
  bool memoryOn; // l'IA retient des infos d'une session à l'autre
  bool isGroup; // discussion de groupe
  List<String> members; // ids des contacts du groupe
  bool nudge; // l'IA peut relancer d'elle-même
  int nudges; // relances envoyées depuis ton dernier message
  int unread; // messages non lus
  bool autoSpeak; // lecture à voix haute des nouveaux messages
  double pitch; // ancien réglage de voix (gardé pour compatibilité)
  bool vocal; // peut envoyer des messages vocaux
  String voice; // voix des vocaux (clé de voicePresets)
  List<String> memory; // souvenirs enregistrés par l'IA
  final List<Msg> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'description': description,
        'color': color,
        'script': script,
        if (photo != null) 'photo': photo,
        'length': length,
        'multi': multi,
        'memoryOn': memoryOn,
        'isGroup': isGroup,
        'members': members,
        'nudge': nudge,
        'nudges': nudges,
        'unread': unread,
        'autoSpeak': autoSpeak,
        'pitch': pitch,
        'vocal': vocal,
        'voice': voice,
        'memory': memory,
        'messages': [for (final m in messages) m.toJson()],
      };

  static Contact fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] as String,
        name: j['name'] as String,
        age: (j['age'] as num?)?.toInt() ?? 10,
        description: j['description'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF128C7E,
        script: j['script'] as String? ?? '',
        photo: j['photo'] as String?,
        length: (j['length'] as num?)?.toInt() ?? 1,
        multi: j['multi'] as bool? ?? true,
        memoryOn: j['memoryOn'] as bool? ?? true,
        isGroup: j['isGroup'] as bool? ?? false,
        members: [
          for (final m in (j['members'] as List? ?? const [])) m.toString(),
        ],
        nudge: j['nudge'] as bool? ?? true,
        nudges: (j['nudges'] as num?)?.toInt() ?? 0,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        autoSpeak: j['autoSpeak'] as bool? ?? false,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 1.0,
        vocal: j['vocal'] as bool? ?? true,
        voice: j['voice'] as String? ?? 'ado',
        memory: [
          for (final m in (j['memory'] as List? ?? const [])) m.toString(),
        ],
        messages: [
          for (final m in (j['messages'] as List? ?? const []))
            Msg.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
      );
}

class Msg {
  Msg(this.text,
      {required this.fromMe,
      DateTime? time,
      this.seconds,
      this.from,
      this.audio,
      this.dur,
      this.wave})
      : time = time ?? DateTime.now();
  final String text; // pour un vocal : sa transcription
  final bool fromMe;
  final DateTime time;
  final double? seconds;
  final String? from; // dans un groupe : id du contact qui a écrit
  final String? audio; // message vocal : fichier .wav dans le dossier de l'app
  final int? dur; // durée du vocal (ms)
  final List<double>? wave; // forme d'onde du vocal

  Map<String, dynamic> toJson() => {
        't': text,
        'me': fromMe,
        'ts': time.millisecondsSinceEpoch,
        if (seconds != null) 's': seconds,
        if (from != null) 'f': from,
        if (audio != null) 'a': audio,
        if (dur != null) 'd': dur,
        if (wave != null)
          'w': [for (final w in wave!) (w * 100).round()],
      };

  static Msg fromJson(Map<String, dynamic> j) => Msg(
        j['t'] as String? ?? '',
        fromMe: j['me'] as bool? ?? false,
        time: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num?)?.toInt() ?? 0),
        seconds: (j['s'] as num?)?.toDouble(),
        from: j['f'] as String?,
        audio: j['a'] as String?,
        dur: (j['d'] as num?)?.toInt(),
        wave: j['w'] == null
            ? null
            : [for (final w in j['w'] as List) (w as num) / 100],
      );
}

// ---------------------------------------------------------------
//  Réponses préenregistrées (fichier .txt importé)
//
//  Format, une règle par ligne :
//    # commentaire
//    bonjour | salut | coucou => Salut ! | Hey, ça va ?
//    ça va => Super, et toi ?
//    * => Réponse quand rien ne correspond
//  - à gauche : un ou plusieurs mots/phrases déclencheurs (séparés par |)
//  - à droite : une ou plusieurs réponses (séparées par |), une est tirée
//    au hasard ; \\n dans une réponse = retour à la ligne
//  - la casse, les accents et la ponctuation sont ignorés
// ---------------------------------------------------------------
class ScriptRule {
  ScriptRule(this.triggers, this.replies);
  final List<String> triggers;
  final List<String> replies;
}

class ScriptBook {
  ScriptBook(this.rules, this.fallback);
  final List<ScriptRule> rules;
  final List<String> fallback;

  static final _rng = Random();

  static const _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'œ': 'oe', 'æ': 'ae',
  };

  static String norm(String s) {
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(_accents[ch] ?? ch);
    }
    return b
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static ScriptBook parse(String raw) {
    final rules = <ScriptRule>[];
    final fallback = <String>[];
    for (var line in raw.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf('=>');
      if (i < 0) continue;
      final left = line.substring(0, i).trim();
      final replies = [
        for (final r in line.substring(i + 2).split('|'))
          if (r.trim().isNotEmpty) r.trim().replaceAll('\\n', '\n'),
      ];
      if (replies.isEmpty) continue;
      if (left == '*') {
        fallback.addAll(replies);
        continue;
      }
      final triggers = [
        for (final t in left.split('|'))
          if (norm(t).isNotEmpty) norm(t),
      ];
      if (triggers.isNotEmpty) rules.add(ScriptRule(triggers, replies));
    }
    return ScriptBook(rules, fallback);
  }

  bool get isEmpty => rules.isEmpty && fallback.isEmpty;

  String? reply(String message) {
    final n = norm(message);
    ScriptRule? best;
    var bestLen = -1;
    for (final r in rules) {
      for (final t in r.triggers) {
        if (n == t) {
          return r.replies[_rng.nextInt(r.replies.length)];
        }
        if (' $n '.contains(' $t ') && t.length > bestLen) {
          best = r;
          bestLen = t.length;
        }
      }
    }
    if (best != null) return best.replies[_rng.nextInt(best.replies.length)];
    if (fallback.isNotEmpty) return fallback[_rng.nextInt(fallback.length)];
    return null;
  }
}

const _palette = <int>[
  0xFF128C7E,
  0xFF5E35B1,
  0xFFD81B60,
  0xFFEF6C00,
  0xFF1E88E5,
  0xFF43A047,
  0xFF6D4C41,
  0xFF546E7A,
];

// Dossier de l'app (photos de profil), renseigné au démarrage.
String _appDirPath = '';

File? _photoFile(String? name) {
  if (name == null || name.isEmpty || _appDirPath.isEmpty) return null;
  final f = File('$_appDirPath/$name');
  return f.existsSync() ? f : null;
}

void _deletePhoto(String? name) {
  if (name == null || name.isEmpty || _appDirPath.isEmpty) return;
  try {
    final f = File('$_appDirPath/$name');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

// Vitesse de frappe simulée (caractères / seconde), 0 = désactivée.
const _typingSpeeds = <int, String>{
  0: 'Désactivé',
  40: 'Rapide',
  20: 'Normal',
  9: 'Réaliste',
};

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return _hhmm(t);
  if (diff == 1) return 'Hier';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------
//  Voix : lecture à voix haute (TTS) et dictée (reconnaissance vocale)
// ---------------------------------------------------------------
// Voix proposées pour les vocaux : (nom, demi-tons, débit).
const voicePresets = <String, (String, double, double)>{
  'ado': ('Ado · fille 14-15 ans', 2.5, 1.08),
  'jeune': ('Jeune femme', 0.8, 1.02),
  'douce': ('Douce et posée', 1.5, 0.92),
  'grave': ('Plus grave', -1.5, 0.98),
};

const voiceModelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/'
    'download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2';

class Voice {
  static final FlutterTts _tts = FlutterTts();
  static final SpeechToText stt = SpeechToText();
  static bool _ttsReady = false;
  static Future<void> _queue = Future.value();
  static Future<void> _synthQueue = Future.value();
  static int _gen = 0; // incrémenté par stop() : vide la file
  static int _tmp = 0;

  static String get modelDir => '$_appDirPath/vits-piper-$voiceModelName';

  /// La voix neuronale (vocaux réalistes) est installée.
  static bool get neuralReady =>
      _appDirPath.isNotEmpty &&
      File('$modelDir/$voiceModelName.onnx').existsSync() &&
      File('$modelDir/tokens.txt').existsSync() &&
      Directory('$modelDir/espeak-ng-data').existsSync();

  /// Des vocaux peuvent être fabriqués (ElevenLabs ou voix locale).
  static bool get available => Eleven.ready || neuralReady;

  /// Fabrique un vocal : ElevenLabs si configuré (repli sur la voix
  /// locale en cas d'erreur réseau), sinon voix locale.
  static Future<({int ms, List<double> wave})> synth(
      String text, String outPath, String preset) async {
    if (Eleven.ready) {
      try {
        return await Eleven.synth(text, outPath);
      } catch (e) {
        if (!neuralReady) rethrow;
      }
    }
    return _synthLocal(stripVoiceTags(text), outPath, preset);
  }

  static Future<({int ms, List<double> wave})> _synthLocal(
      String text, String outPath, String preset) {
    final (_, semi, speed) = voicePresets[preset] ?? voicePresets['ado']!;
    final dir = modelDir;
    final run = _synthQueue.then((_) => Isolate.run(() => synthVoiceFile(
        modelDir: dir,
        text: text,
        outPath: outPath,
        semi: semi,
        speed: speed)));
    _synthQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<void> _init() async {
    if (_ttsReady) return;
    _ttsReady = true;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
  }

  /// Lit un message à voix haute avec la voix du contact (file d'attente).
  static void speak(String text, Contact who) {
    final clean = text.replaceAll(_emojiRe, '').trim();
    if (clean.isEmpty) return;
    final g = _gen;
    _queue = _queue.then((_) async {
      if (g != _gen) return;
      try {
        if (available) {
          final path = '$_appDirPath/lecture_${_tmp++ % 3}.wav';
          await synth(text, path, who.voice);
          if (g != _gen) return;
          await AudioHub.i.playAndWait(path);
        } else {
          final semi = (voicePresets[who.voice] ?? voicePresets['ado']!).$2;
          await _init();
          await _tts.setPitch(pow(2, semi / 12).toDouble());
          await _tts.speak(clean);
        }
      } catch (_) {}
    });
  }

  static Future<void> stop() async {
    _gen++;
    _queue = Future.value();
    await AudioHub.i.stop();
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Lecteur audio partagé (un seul son à la fois).
class AudioHub extends ChangeNotifier {
  AudioHub._() {
    _p.onPositionChanged.listen((d) {
      pos = d;
      notifyListeners();
    });
    _p.onDurationChanged.listen((d) {
      dur = d;
      notifyListeners();
    });
    _p.onPlayerComplete.listen((_) => _finish());
  }
  static final i = AudioHub._();

  final AudioPlayer _p = AudioPlayer();
  String? path;
  bool playing = false;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  Completer<void>? _done;

  void _finish() {
    playing = false;
    path = null;
    pos = Duration.zero;
    _done?.complete();
    _done = null;
    notifyListeners();
  }

  Future<void> toggle(String file) async {
    if (path == file) {
      if (playing) {
        await _p.pause();
      } else {
        await _p.resume();
      }
      playing = !playing;
      notifyListeners();
      return;
    }
    await play(file);
  }

  Future<void> play(String file, {Duration? from}) async {
    _done?.complete();
    _done = null;
    path = file;
    pos = from ?? Duration.zero;
    dur = Duration.zero;
    playing = true;
    notifyListeners();
    await _p.play(DeviceFileSource(file), position: from);
  }

  Future<void> seek(String file, double fraction, int totalMs) async {
    final at = Duration(milliseconds: (totalMs * fraction).round());
    if (path != file) {
      await play(file, from: at);
    } else {
      await _p.seek(at);
      pos = at;
      notifyListeners();
    }
  }

  Future<void> playAndWait(String file) async {
    final c = Completer<void>();
    await play(file);
    _done = c;
    await c.future;
  }

  Future<void> stop() async {
    if (path == null && !playing) return;
    try {
      await _p.stop();
    } catch (_) {}
    _finish();
  }
}

// ---------------------------------------------------------------
//  Messages vocaux : voix neuronale hors ligne (Piper « siwis »,
//  via sherpa-onnx), rajeunie et rendue expressive phrase par phrase.
// ---------------------------------------------------------------
const voiceModelName = 'fr_FR-siwis-medium';

enum _Tone { neutre, joie, triste, question, colere }

final _laughRe = RegExp(r'\b(x?p?tdr+|mdr+|lol|ha(ha)+|hi(hi)+)\b',
    caseSensitive: false);
final _emojiRe = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}\u{2764}]',
    unicode: true);

// Langage SMS → ce qu'on dirait à l'oral.
const _spokenWords = {
  'jsp': 'je sais pas',
  'jpp': "j'en peux plus",
  'tkt': "t'inquiète",
  'pk': 'pourquoi',
  'pq': 'pourquoi',
  'bcp': 'beaucoup',
  'stp': "s'il te plaît",
  'svp': "s'il te plaît",
  'dsl': 'désolée',
  'slt': 'salut',
  'cc': 'coucou',
  'wsh': 'wesh',
  'mtn': 'maintenant',
  'tjr': 'toujours',
  'tjrs': 'toujours',
  'jtm': "je t'aime",
  'oklm': 'au calme',
  'pcq': 'parce que',
  'psk': 'parce que',
  'qd': 'quand',
  'rdv': 'rendez-vous',
  'auj': "aujourd'hui",
  'ajd': "aujourd'hui",
  'bjr': 'bonjour',
  'bsr': 'bonsoir',
  'vrmt': 'vraiment',
  'chui': 'chuis',
  'nn': 'non',
  'ok': 'okay',
};

_Tone _toneOf(String s) {
  final t = s.toLowerCase().trimRight();
  final letters = s.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (RegExp(r'😡|🤬|😤|énervée?|saoulée?|j.en ai marre').hasMatch(t) ||
      (letters.length > 5 && letters == letters.toUpperCase())) {
    return _Tone.colere;
  }
  if (RegExp(r'😢|😭|😔|😞|🥺|💔|triste|désolée?|\bdsl\b|fatiguée?|snif|déprim')
          .hasMatch(t) ||
      t.endsWith('…') ||
      t.endsWith('...')) {
    return _Tone.triste;
  }
  if (_laughRe.hasMatch(t) ||
      RegExp(r'😂|🤣|😍|🥰|😁|😆|😄|🤩|❤|trop bien|génial|trop cool|\bouf\b')
          .hasMatch(t) ||
      t.endsWith('!')) {
    return _Tone.joie;
  }
  if (t.endsWith('?')) return _Tone.question;
  return _Tone.neutre;
}

String _spoken(String s, {bool keepTags = false}) {
  var t = s
      .replaceAll(_emojiRe, ' ')
      .replaceAll(_laughRe, keepTags ? ' [laughs] ' : ' ');
  t = t.replaceAllMapped(RegExp(r"[A-Za-zÀ-ÿ']+"), (m) {
    final w = m.group(0)!;
    return _spokenWords[w.toLowerCase()] ?? w;
  });
  return t
      .replaceAll(RegExp(keepTags ? r'[*#_~<>]' : r'[*#_~<>\[\]]'), ' ')
      .replaceAll(RegExp(r'([!?])\1+'), r'$1')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// Rééchantillonne [x] d'un facteur [p] (p > 1 : voix plus aiguë et plus
// rapide), avec une montée finale pour les questions.
void _shiftInto(List<double> out, Float32List x, double p, double gain,
    {bool rise = false, int fade = 180}) {
  final n = x.length;
  final start = out.length;
  var pos = 0.0;
  while (pos < n - 1) {
    final i = pos.floor();
    final f = pos - i;
    out.add((x[i] * (1 - f) + x[i + 1] * f) * gain);
    final t = pos / n;
    pos += rise && t > 0.65 ? p * pow(2, (t - 0.65) / 0.35 * 2.5 / 12) : p;
  }
  final len = out.length - start;
  final fl = min(fade, len ~/ 2);
  for (var k = 0; k < fl; k++) {
    final g = k / fl;
    out[start + k] *= g;
    out[out.length - 1 - k] *= g;
  }
}

/// Crée le fichier WAV d'un message vocal. [semi] : demi-tons ajoutés à la
/// voix de base (≈ +2,5 pour une ado de 14-15 ans), [speed] : débit.
/// Renvoie la durée et une forme d'onde (48 barres entre 0 et 1).
/// Fonction synchrone et lourde : à lancer dans un isolate.
({int ms, List<double> wave}) synthVoiceFile({
  required String modelDir,
  required String text,
  required String outPath,
  double semi = 2.5,
  double speed = 1.08,
}) {
  sherpa.initBindings();
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: '$modelDir/$voiceModelName.onnx',
        tokens: '$modelDir/tokens.txt',
        dataDir: '$modelDir/espeak-ng-data',
      ),
      numThreads: 2,
      debug: false,
    ),
  ));
  try {
    final rng = Random();
    // Découpage en phrases, chacune avec son ton.
    final segs = <(String, _Tone)>[];
    for (final m in RegExp(r'[^.!?…]+[.!?…]*').allMatches(text)) {
      final raw = m.group(0)!.trim();
      if (raw.isEmpty) continue;
      final tone = _toneOf(raw);
      final say = _spoken(raw);
      if (!RegExp(r'[A-Za-zÀ-ÿ0-9]').hasMatch(say)) {
        // Juste un emoji ou un rire : il colore la phrase d'avant.
        if (segs.isNotEmpty && segs.last.$2 == _Tone.neutre) {
          segs.last = (segs.last.$1, tone);
        }
        continue;
      }
      segs.add((say, tone));
    }
    if (segs.isEmpty) throw Exception('rien à dire');
    var sr = 22050;
    final out = <double>[];
    var first = true;
    for (final (say, tone) in segs) {
      final (dSemi, dSpeed, gain) = switch (tone) {
        _Tone.joie => (1.5, 1.12, 1.1),
        _Tone.triste => (-1.2, 0.86, 0.85),
        _Tone.question => (0.6, 1.0, 1.0),
        _Tone.colere => (0.3, 1.12, 1.2),
        _Tone.neutre => (0.0, 1.0, 1.0),
      };
      final p = pow(2, (semi + dSemi + (rng.nextDouble() - 0.5) * 0.6) / 12)
          .toDouble();
      final a = tts.generate(text: say, sid: 0, speed: speed * dSpeed / p);
      sr = a.sampleRate;
      if (first) {
        out.addAll(List.filled((sr * 0.15).round(), 0.0));
        first = false;
      }
      _shiftInto(out, a.samples, p, gain, rise: tone == _Tone.question);
      final pause = switch (tone) {
            _Tone.triste => 0.5,
            _Tone.question => 0.3,
            _ => 0.22,
          } +
          rng.nextDouble() * 0.12;
      out.addAll(List.filled((sr * pause).round(), 0.0));
    }
    return writeWav(out, sr, outPath);
  } finally {
    tts.free();
  }
}

/// Écrit [out] (échantillons -1…1) en WAV 16 bits mono normalisé, et
/// renvoie la durée et la forme d'onde (48 barres) du vocal.
({int ms, List<double> wave}) writeWav(
    List<double> out, int sr, String outPath) {
  var peak = 0.0;
  for (final v in out) {
    peak = max(peak, v.abs());
  }
  final k = peak > 0 ? 0.9 / peak : 1.0;
  // WAV 16 bits mono.
  final data = ByteData(44 + out.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + out.length * 2, Endian.little);
  str(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, out.length * 2, Endian.little);
  for (var i = 0; i < out.length; i++) {
    data.setInt16(44 + i * 2,
        (out[i] * k * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  File(outPath).writeAsBytesSync(data.buffer.asUint8List());
  // Forme d'onde pour la bulle.
  const bars = 48;
  final wave = <double>[];
  final step = max(1, out.length ~/ bars);
  for (var b = 0; b < bars; b++) {
    var s = 0.0;
    final from = b * step;
    final to = min(out.length, from + step);
    for (var i = from; i < to; i++) {
      s += out[i] * out[i];
    }
    wave.add(to > from ? sqrt(s / (to - from)) * k : 0);
  }
  final top = wave.fold<double>(0, max);
  return (
    ms: out.length * 1000 ~/ sr,
    wave: [for (final w in wave) top > 0 ? (w / top).clamp(0.08, 1.0) : 0.08],
  );
}

// ---------------------------------------------------------------
//  ElevenLabs : voix ultra réaliste (en ligne, avec la clé API de
//  l'utilisateur). Le modèle v3 comprend les émotions entre crochets.
// ---------------------------------------------------------------
const elevenDefaultDescription =
    'A 15-year-old French teenage girl. Young, bright, slightly high-pitched '
    'voice, lively and very expressive, casual and friendly, speaks naturally '
    'and a bit fast like when sending a voice message to her best friend. '
    'Native French accent from Paris, clear close-mic phone recording.';

const elevenPreviewText =
    'Coucou ! Ça va toi ? Franchement aujourd\'hui j\'ai trop rigolé avec '
    'Inès, on s\'est fait virer du CDI tellement on riait. Par contre j\'ai '
    'raté mon contrôle de maths… Tu fais quoi ce week-end ?';

// Indications d'émotion comprises par eleven_v3.
final _elTagRe = RegExp(r'\[([a-zA-Z][a-zA-Z ]{1,24})\]');

/// Texte d'un vocal sans les indications d'émotion (pour la transcription).
String stripVoiceTags(String t) =>
    t.replaceAll(_elTagRe, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// Prépare un texte pour eleven_v3 : langage oral + émotions par phrase.
String elevenText(String text) {
  final b = StringBuffer();
  for (final m in RegExp(r'[^.!?…]+[.!?…]*').allMatches(text)) {
    final raw = m.group(0)!.trim();
    if (raw.isEmpty) continue;
    final say = _spoken(raw, keepTags: true);
    if (!RegExp(r'[A-Za-zÀ-ÿ0-9]').hasMatch(stripVoiceTags(say))) {
      if (say.contains('[')) b.write('$say ');
      continue;
    }
    if (!_elTagRe.hasMatch(say)) {
      final tag = switch (_toneOf(raw)) {
        _Tone.triste => '[sad] ',
        _Tone.colere => '[annoyed] ',
        _Tone.joie when raw.trimRight().endsWith('!') => '[excited] ',
        _ => '',
      };
      b.write(tag);
    }
    b.write('$say ');
  }
  final out = b.toString().trim();
  return out.isEmpty ? text : out;
}

class Eleven {
  static String key = '';
  static String voiceId = '';
  static String voiceName = '';

  static bool get ready => key.isNotEmpty && voiceId.isNotEmpty;

  static Future<List<int>> _post(String path, Map<String, dynamic> body,
      {String? apiKey}) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('https://api.elevenlabs.io$path'));
      req.headers
        ..set('xi-api-key', apiKey ?? key)
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close();
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      if (res.statusCode != 200) {
        var msg = utf8.decode(bytes, allowMalformed: true);
        try {
          final d = (jsonDecode(msg) as Map)['detail'];
          msg = d is Map ? '${d['message'] ?? d}' : '$d';
        } catch (_) {}
        throw ElevenError(res.statusCode, msg);
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  /// Fabrique un vocal WAV avec la voix ElevenLabs choisie.
  static Future<({int ms, List<double> wave})> synth(
      String text, String outPath) async {
    List<int> pcm;
    try {
      pcm = await _post(
          '/v1/text-to-speech/$voiceId?output_format=pcm_22050', {
        'text': elevenText(text),
        'model_id': 'eleven_v3',
        'language_code': 'fr',
        'voice_settings': {'stability': 0.5},
      });
    } on ElevenError catch (e) {
      if (e.code == 401 || e.code == 429) rethrow;
      // Modèle v3 indisponible : modèle multilingue classique, sans balises.
      pcm = await _post(
          '/v1/text-to-speech/$voiceId?output_format=pcm_22050', {
        'text': stripVoiceTags(_spoken(text)),
        'model_id': 'eleven_multilingual_v2',
        'voice_settings': {'stability': 0.35, 'similarity_boost': 0.8},
      });
    }
    final bd = ByteData.sublistView(Uint8List.fromList(pcm));
    final out = <double>[
      for (var i = 0; i + 1 < pcm.length; i += 2)
        bd.getInt16(i, Endian.little) / 32768,
    ];
    if (out.isEmpty) throw Exception('audio vide');
    return writeWav(out, 22050, outPath);
  }

  /// Propose plusieurs voix à partir d'une description.
  /// Renvoie (id provisoire, fichier audio d'essai).
  static Future<List<(String, String)>> design(
      String description, String apiKey) async {
    List<int> bytes;
    try {
      bytes = await _post(
          '/v1/text-to-voice/design',
          {
            'voice_description': description,
            'model_id': 'eleven_ttv_v3',
            'text': elevenPreviewText,
          },
          apiKey: apiKey);
    } on ElevenError catch (e) {
      if (e.code == 401) rethrow;
      bytes = await _post(
          '/v1/text-to-voice/create-previews',
          {'voice_description': description, 'text': elevenPreviewText},
          apiKey: apiKey);
    }
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    final res = <(String, String)>[];
    var n = 0;
    for (final p in (j['previews'] as List? ?? const [])) {
      final m = p as Map;
      final type = '${m['media_type'] ?? 'audio/mpeg'}';
      final ext = type.contains('wav') ? 'wav' : 'mp3';
      final path = '$_appDirPath/essai_voix_${n++}.$ext';
      await File(path).writeAsBytes(base64Decode(m['audio_base_64'] as String));
      res.add((m['generated_voice_id'] as String, path));
    }
    if (res.isEmpty) throw Exception('aucune voix proposée');
    return res;
  }

  /// Enregistre une voix proposée dans le compte ElevenLabs.
  static Future<String> save(String generatedId, String name,
      String description, String apiKey) async {
    final body = {
      'voice_name': name,
      'voice_description': description,
      'generated_voice_id': generatedId,
    };
    List<int> bytes;
    try {
      bytes = await _post('/v1/text-to-voice', body, apiKey: apiKey);
    } on ElevenError catch (e) {
      if (e.code == 401) rethrow;
      bytes = await _post('/v1/text-to-voice/create-voice-from-preview', body,
          apiKey: apiKey);
    }
    return (jsonDecode(utf8.decode(bytes)) as Map)['voice_id'] as String;
  }
}

class ElevenError implements Exception {
  ElevenError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => code == 401
      ? 'clé API ElevenLabs refusée'
      : code == 429
          ? 'quota ElevenLabs atteint'
          : 'ElevenLabs ($code) : $message';
}

// ---------------------------------------------------------------
//  Cerveau : stockage + modèle + conversations
// ---------------------------------------------------------------
class Brain extends ChangeNotifier {
  final List<Contact> contacts = [];

  // Réglages
  String modelId = baseModels.first.id;
  LiteLmBackend backend = LiteLmBackend.cpu;
  String customRepo = '';
  int typingCps = 20; // vitesse de frappe simulée, 0 = instantané

  // État modèle
  final Set<String> downloaded = {};
  double? progress; // null = pas de téléchargement
  String? downloadingId;
  bool loading = false;
  String status = '';
  String? loadedId;
  LiteLmBackend? loadedBackend;
  LiteLmEngine? _engine;
  final Map<String, LiteLmConversation> _convs = {};
  final Set<String> generating = {};
  // Dans un groupe : nom du membre en train d'écrire.
  final Map<String, String> typingName = {};
  // Discussions où l'IA est en train d'enregistrer un vocal.
  final Set<String> recording = {};
  // Installation de la voix des vocaux.
  double? voiceProgress;
  String voiceStatus = '';
  // Incrémenté quand une discussion est vidée : stoppe une rafale en cours.
  final Map<String, int> _epoch = {};
  // Une seule génération à la fois sur le moteur.
  Future<void> _modelQueue = Future.value();
  // Discussion actuellement ouverte à l'écran (pour les non-lus).
  String? openChatId;
  Timer? _nudgeTimer;
  static final _rng = Random();

  late Directory _dir;
  Timer? _saveTimer;

  ModelOption get model => modelId == _customId
      ? ModelOption(
          id: _customId,
          name: 'Modèle perso',
          note: customRepo.isEmpty ? 'dépôt Hugging Face' : customRepo,
          repo: customRepo.contains('://') ? null : customRepo,
          url: customRepo.contains('://') ? customRepo : null,
        )
      : baseModels.firstWhere((m) => m.id == modelId,
          orElse: () => baseModels.first);

  bool get ready => _engine != null;

  // ----- Stockage -----
  File get _dataFile => File('${_dir.path}/app_data.json');
  File modelFile(String id) => File('${_dir.path}/$id.litertlm');

  Future<void> init() async {
    _dir = await getApplicationSupportDirectory();
    _appDirPath = _dir.path;
    try {
      if (await _dataFile.exists()) {
        final j = jsonDecode(await _dataFile.readAsString()) as Map;
        modelId = j['modelId'] as String? ?? modelId;
        customRepo = j['customRepo'] as String? ?? '';
        backend = (j['gpu'] as bool? ?? false)
            ? LiteLmBackend.gpu
            : LiteLmBackend.cpu;
        typingCps = (j['typingCps'] as num?)?.toInt() ?? typingCps;
        Eleven.key = j['elevenKey'] as String? ?? '';
        Eleven.voiceId = j['elevenVoiceId'] as String? ?? '';
        Eleven.voiceName = j['elevenVoiceName'] as String? ?? '';
        for (final c in (j['contacts'] as List? ?? const [])) {
          contacts.add(Contact.fromJson(Map<String, dynamic>.from(c as Map)));
        }
      }
    } catch (_) {}
    if (contacts.isEmpty) {
      contacts.add(Contact(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: 'Léo',
        age: 12,
        description: 'pote un peu sarcastique mais sympa, passionné de jeux '
            'vidéo et de voitures',
        color: _palette[0],
      ));
    }
    await refreshDownloaded();
    _nudgeTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => _nudgeTick());
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Map<String, dynamic> _toJson() => {
        'modelId': modelId,
        'customRepo': customRepo,
        'gpu': backend == LiteLmBackend.gpu,
        'typingCps': typingCps,
        'elevenKey': Eleven.key,
        'elevenVoiceId': Eleven.voiceId,
        'elevenVoiceName': Eleven.voiceName,
        'contacts': [for (final c in contacts) c.toJson()],
      };

  Future<void> saveNow() async {
    try {
      await _dataFile.writeAsString(jsonEncode(_toJson()));
    } catch (_) {}
  }

  // ----- Sauvegarde / restauration -----
  /// Contacts, souvenirs, discussions et photos dans un seul fichier JSON.
  Future<Uint8List> exportBackup() async {
    final photos = <String, String>{};
    for (final c in contacts) {
      final f = _photoFile(c.photo);
      if (f != null) photos[c.photo!] = base64Encode(await f.readAsBytes());
    }
    return utf8.encode(jsonEncode({
      'app': 'ia_messenger',
      'version': 1,
      'typingCps': typingCps,
      'contacts': [for (final c in contacts) c.toJson()],
      'photos': photos,
    }));
  }

  /// Remplace tous les contacts par ceux de la sauvegarde.
  /// Renvoie le nombre de discussions restaurées.
  Future<int> importBackup(List<int> bytes) async {
    var txt = utf8.decode(bytes, allowMalformed: true);
    if (txt.startsWith('﻿')) txt = txt.substring(1);
    final j = jsonDecode(txt);
    if (j is! Map || j['app'] != 'ia_messenger' || j['contacts'] is! List) {
      throw Exception('ce fichier n\'est pas une sauvegarde IA Messenger');
    }
    final restored = [
      for (final c in j['contacts'] as List)
        Contact.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
    final photos = Map<String, dynamic>.from(j['photos'] as Map? ?? const {});
    for (final e in photos.entries) {
      // Nom de fichier simple uniquement (pas de chemin).
      if (e.key.contains('/') || e.key.contains('\\')) continue;
      await File('${_dir.path}/${e.key}')
          .writeAsBytes(base64Decode(e.value as String));
    }
    await Voice.stop();
    for (final c in contacts) {
      _bump(c);
      _dropAudio(c.messages);
      if (!photos.containsKey(c.photo)) _deletePhoto(c.photo);
    }
    for (final c in _convs.values) {
      await c.dispose();
    }
    _convs.clear();
    contacts
      ..clear()
      ..addAll(restored);
    typingCps = (j['typingCps'] as num?)?.toInt() ?? typingCps;
    await saveNow();
    notifyListeners();
    return restored.length;
  }

  Future<void> refreshDownloaded() async {
    downloaded.clear();
    for (final id in [...baseModels.map((m) => m.id), _customId]) {
      if (await modelFile(id).exists()) downloaded.add(id);
    }
    notifyListeners();
  }

  // ----- Contacts -----
  void addOrUpdate(Contact c) {
    if (!contacts.contains(c)) contacts.insert(0, c);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  // Supprime les fichiers audio des messages retirés.
  void _dropAudio(Iterable<Msg> msgs) {
    for (final m in msgs) {
      if (m.audio != null) _deletePhoto(m.audio);
    }
  }

  void deleteContact(Contact c) {
    _dropAudio(c.messages);
    contacts.remove(c);
    for (final g in contacts) {
      g.members.remove(c.id);
    }
    _bump(c);
    _deletePhoto(c.photo);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  void clearChat(Contact c) {
    _dropAudio(c.messages);
    c.messages.clear();
    _bump(c);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  void clearMemory(Contact c) {
    c.memory.clear();
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  List<Contact> membersOf(Contact g) => [
        for (final id in g.members)
          ...contacts.where((c) => c.id == id && !c.isGroup),
      ];

  Contact? byId(String? id) {
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  void openChat(Contact c) {
    openChatId = c.id;
    if (c.unread != 0) {
      c.unread = 0;
      _scheduleSave();
      notifyListeners();
    }
  }

  void closeChat(Contact c) {
    if (openChatId == c.id) openChatId = null;
  }

  void setAutoSpeak(Contact c, bool v) {
    c.autoSpeak = v;
    if (!v) Voice.stop();
    _scheduleSave();
    notifyListeners();
  }

  void _bump(Contact c) => _epoch[c.id] = (_epoch[c.id] ?? 0) + 1;

  void _dropConv(String id) {
    final conv = _convs.remove(id);
    conv?.dispose();
  }

  // ----- Réglages -----
  void selectModel(String id) {
    modelId = id;
    _scheduleSave();
    notifyListeners();
  }

  void setBackend(LiteLmBackend b) {
    backend = b;
    _scheduleSave();
    notifyListeners();
  }

  void setTypingCps(int v) {
    typingCps = v;
    _scheduleSave();
    notifyListeners();
  }

  void setCustomRepo(String v) {
    customRepo = v.trim();
    _scheduleSave();
    notifyListeners();
  }

  // ----- Téléchargement -----
  Future<String> _resolveUrl(ModelOption m) async {
    if (m.url != null) return m.url!;
    final repo = m.repo;
    if (repo == null || repo.isEmpty) {
      throw Exception('Aucun dépôt renseigné');
    }
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('https://huggingface.co/api/models/$repo'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw Exception('Hugging Face : HTTP ${res.statusCode} pour $repo');
      }
      final j = jsonDecode(body) as Map;
      final files = [
        for (final s in (j['siblings'] as List? ?? const []))
          (s as Map)['rfilename'] as String,
      ].where((f) => f.endsWith('.litertlm')).toList();
      if (files.isEmpty) {
        throw Exception('Aucun fichier .litertlm dans $repo');
      }
      files.sort();
      return 'https://huggingface.co/$repo/resolve/main/${files.first}';
    } finally {
      client.close();
    }
  }

  Future<void> download() async {
    final m = model;
    progress = 0;
    downloadingId = m.id;
    status = 'Préparation du téléchargement…';
    notifyListeners();
    final file = modelFile(m.id);
    final part = File('${file.path}.part');
    final client = HttpClient();
    IOSink? sink;
    try {
      final url = await _resolveUrl(m);
      var offset = await part.exists() ? await part.length() : 0;
      final req = await client.getUrl(Uri.parse(url));
      if (offset > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        status = 'Reprise du téléchargement…';
        notifyListeners();
      }
      final res = await req.close();
      if (res.statusCode == 416) {
        if (await part.exists()) await part.delete();
        throw Exception('fichier partiel invalide, relance le téléchargement');
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw Exception('HTTP ${res.statusCode}');
      }
      if (res.statusCode == 200) offset = 0;
      final total =
          res.contentLength > 0 ? offset + res.contentLength : m.sizeBytes;
      sink = part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      var received = offset;
      var lastPct = -1;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = received * 100 ~/ total;
          if (pct != lastPct) {
            lastPct = pct;
            progress = received / total;
            status = 'Téléchargement… ${(received / 1e6).toStringAsFixed(0)} Mo';
            notifyListeners();
          }
        }
      }
      await sink.close();
      sink = null;
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      status = 'Téléchargement terminé';
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      status = 'Erreur de téléchargement : $e '
          '(le fichier partiel est gardé : relance pour reprendre)';
    } finally {
      client.close();
      progress = null;
      downloadingId = null;
      await refreshDownloaded();
    }
  }

  Future<void> deleteModel() async {
    final m = model;
    if (loadedId == m.id) await unload();
    try {
      final f = modelFile(m.id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    status = 'Modèle supprimé';
    await refreshDownloaded();
  }

  // ----- Voix des messages vocaux -----
  Future<void> downloadVoice() async {
    if (voiceProgress != null) return;
    voiceProgress = 0;
    voiceStatus = 'Téléchargement de la voix…';
    notifyListeners();
    final archive = File('${_dir.path}/voix.tar.bz2');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(voiceModelUrl))).close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : 67207459;
      final sink = archive.openWrite();
      var got = 0;
      var lastPct = -1;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        final pct = got * 100 ~/ total;
        if (pct != lastPct) {
          lastPct = pct;
          voiceProgress = min(1, got / total) * 0.8;
          voiceStatus = 'Téléchargement de la voix… '
              '${(got / 1e6).toStringAsFixed(0)} Mo';
          notifyListeners();
        }
      }
      await sink.close();
      voiceProgress = 0.85;
      voiceStatus = 'Installation de la voix (≈ 1 min)…';
      notifyListeners();
      final src = archive.path;
      final dest = _dir.path;
      await Isolate.run(() {
        final tar = arc.BZip2Decoder().decodeBytes(File(src).readAsBytesSync());
        for (final f in arc.TarDecoder().decodeBytes(tar)) {
          if (!f.isFile || f.name.contains('..')) continue;
          File('$dest/${f.name}')
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content);
        }
      });
      if (!Voice.neuralReady) throw Exception('fichiers de voix incomplets');
      // Les consignes changent (vocaux possibles) : on recrée les discussions.
      for (final c in _convs.values) {
        await c.dispose();
      }
      _convs.clear();
      voiceStatus = 'Voix installée ✅ : les contacts peuvent envoyer des vocaux.';
    } catch (e) {
      voiceStatus = 'Erreur d\'installation de la voix : $e';
    } finally {
      client.close();
      try {
        if (await archive.exists()) await archive.delete();
      } catch (_) {}
      voiceProgress = null;
      notifyListeners();
    }
  }

  /// Règle ElevenLabs (clé et/ou voix). Les consignes de l'IA changent.
  Future<void> setEleven({String? key, String? voiceId, String? name}) async {
    if (key != null) Eleven.key = key.trim();
    if (voiceId != null) Eleven.voiceId = voiceId.trim();
    if (name != null) Eleven.voiceName = name.trim();
    for (final c in _convs.values) {
      await c.dispose();
    }
    _convs.clear();
    _scheduleSave();
    notifyListeners();
  }

  Future<void> deleteVoice() async {
    await Voice.stop();
    try {
      final d = Directory(Voice.modelDir);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    for (final c in _convs.values) {
      await c.dispose();
    }
    _convs.clear();
    voiceStatus = 'Voix supprimée';
    notifyListeners();
  }

  // ----- Chargement -----
  Future<void> unload() async {
    for (final c in _convs.values) {
      await c.dispose();
    }
    _convs.clear();
    await _engine?.dispose();
    _engine = null;
    loadedId = null;
    loadedBackend = null;
  }

  Future<bool> load() async {
    final m = model;
    loading = true;
    status = 'Chargement du modèle…';
    notifyListeners();
    try {
      await unload();
      final sw = Stopwatch()..start();
      _engine = await LiteLmEngine.create(
        LiteLmEngineConfig(modelPath: modelFile(m.id).path, backend: backend),
      );
      sw.stop();
      loadedId = m.id;
      loadedBackend = backend;
      status =
          '${m.name} chargé en ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
          '(${backend == LiteLmBackend.gpu ? 'GPU' : 'CPU'})';
      return true;
    } catch (e) {
      _engine = null;
      status = 'Erreur de chargement : $e';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ----- Conversation -----
  // Personnalité, style et mémoire, communs aux discussions et aux groupes.
  void _persona(StringBuffer buf, Contact c) {
    final desc = c.description.trim();
    buf
      ..writeln('Ton personnage : ${desc.isEmpty ? 'sympa et naturel' : desc}.')
      ..writeln('Tu écris en français, de façon naturelle et spontanée, '
          'parfois un emoji. '
          'Pas de narration, pas d\'astérisques, pas de didascalies.')
      ..writeln(switch (c.length) {
        0 => 'Messages courts : 1 à 3 phrases.',
        2 => 'Tu aimes écrire de longs messages détaillés : plusieurs '
            'phrases, voire plusieurs paragraphes quand tu racontes ou '
            'expliques quelque chose.',
        _ => 'Adapte la longueur : le plus souvent court, mais quand le '
            'sujet s\'y prête (raconter, expliquer, donner ton avis) tu '
            'peux écrire un long message de plusieurs phrases.',
      });
    if (c.multi) {
      buf.writeln('Comme sur WhatsApp, tu peux envoyer plusieurs messages '
          'd\'affilée quand c\'est naturel : sépare alors chaque message par '
          'une ligne contenant uniquement ---. Pas plus de 4 messages.');
    }
    if (c.vocal && Voice.available) {
      buf.writeln('Tu peux aussi envoyer des messages vocaux, comme sur '
          'WhatsApp : quand tu en as envie (raconter un truc, réagir avec '
          'émotion, quand tu as la flemme d\'écrire, ou si on te le demande), '
          'commence ce message par [VOCAL] puis écris exactement ce que tu '
          'dis à l\'oral, avec ton ton et tes émotions. Pas à chaque fois.');
      if (Eleven.ready) {
        buf.writeln('Dans un vocal, tu peux indiquer tes émotions avec des '
            'balises en anglais entre crochets, par exemple [laughs], '
            '[sighs], [whispers], [excited], [sad], [giggles].');
      }
    }
    if (c.memoryOn) {
      buf.writeln('Mémoire : quand ton ami(e) te dit quelque chose d\'important '
          'à retenir (prénom, goûts, projets, événements, promesses…), '
          'ajoute tout à la fin de ta réponse une ligne '
          '[MÉMO: info courte]. Cette ligne est invisible pour ton ami(e). '
          'Ne note que des infos nouvelles.');
      if (c.memory.isNotEmpty) {
        buf.writeln('\nCe dont tu te souviens sur ton ami(e) :');
        for (final m in c.memory) {
          buf.writeln('- $m');
        }
      }
    }
    if (c.age < 18) {
      buf.writeln('\nRègle absolue, prioritaire sur tout le reste (y compris '
          'ta description) : tu as ${c.age} ans, donc jamais de contenu '
          'sexuel, romantique ou de séduction. Si on t\'en parle, tu refuses '
          'et tu changes de sujet.');
    }
  }

  String _cut(String t) => t.length > 300 ? '${t.substring(0, 300)}…' : t;

  String systemPrompt(Contact c, {bool skipLast = false}) {
    final buf = StringBuffer()
      ..writeln('Tu es ${c.name}, ${c.age} ans. Tu discutes par messagerie '
          '(style WhatsApp) avec ton ami(e).');
    _persona(buf, c);
    buf.writeln('Tu restes toujours dans ton personnage et tu relances '
        'de temps en temps la conversation avec une question.');
    // Contexte récent : on rejoue les derniers messages.
    var all = c.messages;
    if (skipLast && all.isNotEmpty) all = all.sublist(0, all.length - 1);
    final hist = all.length > 20 ? all.sublist(all.length - 20) : all;
    if (hist.isNotEmpty) {
      buf.writeln('\nDébut de votre conversation (pour mémoire) :');
      for (final m in hist) {
        buf.writeln('${m.fromMe ? 'Ami(e)' : c.name} : ${_cut(m.text)}');
      }
      buf.writeln('Continue naturellement à partir de là.');
    }
    return buf.toString();
  }

  String _groupPrompt(Contact g, Contact me) {
    final others = membersOf(g).where((m) => m.id != me.id).toList();
    final buf = StringBuffer()
      ..writeln('Tu es ${me.name}, ${me.age} ans. Tu es dans un groupe '
          'WhatsApp « ${g.name} » avec ton ami(e)'
          '${others.isEmpty ? '' : ' et :'}');
    for (final o in others) {
      final d = o.description.trim();
      buf.writeln('- ${o.name}, ${o.age} ans${d.isEmpty ? '' : ' : ${_cut(d)}'}');
    }
    if (g.description.trim().isNotEmpty) {
      buf.writeln('Sujet du groupe : ${g.description.trim()}');
    }
    _persona(buf, me);
    buf.writeln('Tu ne parles qu\'en ton nom : n\'écris jamais les messages '
        'des autres. Tu peux répondre à ton ami(e) ou réagir à ce qu\'ont '
        'dit les autres en les appelant par leur prénom.');
    final hist = g.messages.length > 25
        ? g.messages.sublist(g.messages.length - 25)
        : g.messages;
    if (hist.isNotEmpty) {
      buf.writeln('\nDerniers messages du groupe :');
      for (final m in hist) {
        final who = m.fromMe ? 'Ami(e)' : (byId(m.from)?.name ?? '?');
        buf.writeln('$who : ${_cut(m.text)}');
      }
    }
    return buf.toString();
  }

  LiteLmConversationConfig _cfg(String system) => LiteLmConversationConfig(
        systemInstruction: system,
        samplerConfig: const LiteLmSamplerConfig(
          temperature: 0.8,
          topK: 40,
          topP: 0.95,
        ),
      );

  // Les générations passent l'une après l'autre sur le moteur.
  Future<T> _exclusive<T>(Future<T> Function() f) {
    final run = _modelQueue.then((_) => f());
    _modelQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<LiteLmConversation> _convFor(Contact c, {bool skipLast = false}) async {
    final existing = _convs[c.id];
    if (existing != null) return existing;
    final conv = await _engine!
        .createConversation(_cfg(systemPrompt(c, skipLast: skipLast)));
    _convs[c.id] = conv;
    return conv;
  }

  String _clean(String s) {
    var out = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final i = out.indexOf('<think>');
    if (i >= 0) out = out.substring(0, i);
    return out.trim();
  }

  String _ago(int minutes) {
    if (minutes < 60) return '$minutes minutes';
    if (minutes < 60 * 24) return '${minutes ~/ 60} h';
    return '${minutes ~/ (60 * 24)} jour(s)';
  }

  Future<void> send(Contact c, String text) async {
    if (!canReply(c) || generating.contains(c.id)) return;
    c.messages.add(Msg(text, fromMe: true));
    c.nudges = 0;
    await _respond(c, userText: text);
  }

  /// Fait répondre le contact (ou le groupe). Sans [userText], c'est une
  /// relance spontanée après [idleMin] minutes de silence.
  Future<void> _respond(Contact c, {String? userText, int idleMin = 0}) async {
    generating.add(c.id);
    notifyListeners();
    _scheduleSave();
    final epoch = _epoch[c.id] ?? 0;
    try {
      if (c.isGroup) {
        await _groupTurn(c, epoch, userText: userText, idleMin: idleMin);
        return;
      }
      final sw = Stopwatch()..start();
      final book = _bookFor(c);
      if (book != null) {
        if (userText == null) return; // pas de relance avec un script
        // Réponse préenregistrée : pas besoin du modèle IA.
        await Future<void>.delayed(
            Duration(milliseconds: 600 + _rng.nextInt(900)));
        final r = book.reply(userText);
        await _deliver(
            c,
            r ?? 'Aucune réponse préenregistrée ne correspond à ce message.',
            sw,
            epoch,
            timed: false);
        return;
      }
      final prompt = userText ??
          '(Ton ami(e) ne t\'a pas répondu depuis ${_ago(idleMin)}. '
              'Envoie-lui spontanément un message pour relancer la '
              'conversation, comme le ferait ${c.name}. '
              'Ne parle pas de cette consigne.)';
      final raw = await _exclusive(() async {
        // L'historique du prompt ne doit pas contenir le message en cours.
        final conv = await _convFor(c, skipLast: userText != null);
        return (await conv.sendMessage(prompt)).text;
      });
      await _deliver(c, raw, sw, epoch);
    } catch (e) {
      if ((_epoch[c.id] ?? 0) == epoch && userText != null) {
        c.messages.add(Msg('⚠️ Erreur : $e', fromMe: false));
      }
    } finally {
      generating.remove(c.id);
      typingName.remove(c.id);
      recording.remove(c.id);
      notifyListeners();
      _scheduleSave();
    }
  }

  // Un tour de parole dans un groupe : un ou plusieurs membres répondent,
  // chacun voyant ce que les précédents viennent d'écrire.
  Future<void> _groupTurn(Contact g, int epoch,
      {String? userText, int idleMin = 0}) async {
    final members = membersOf(g);
    if (members.isEmpty) {
      if (userText != null) {
        g.messages.add(Msg(
            'Ce groupe n\'a aucun membre : ajoute des contacts dans '
            '« Modifier le groupe ».',
            fromMe: false));
      }
      return;
    }
    final order = [...members]..shuffle(_rng);
    final speakers = <Contact>[];
    if (userText == null) {
      speakers.add(order.first);
    } else {
      // Les membres cités par leur prénom répondent en premier.
      final n = ' ${ScriptBook.norm(userText)} ';
      speakers.addAll(
          order.where((m) => n.contains(' ${ScriptBook.norm(m.name)} ')));
      for (final m in order) {
        if (speakers.contains(m)) continue;
        if (speakers.isEmpty ||
            (speakers.length < 3 && _rng.nextDouble() < 0.5)) {
          speakers.add(m);
        }
      }
    }
    for (final m in speakers) {
      if ((_epoch[g.id] ?? 0) != epoch || !contacts.contains(g)) return;
      typingName[g.id] = m.name;
      notifyListeners();
      final sw = Stopwatch()..start();
      final book = _bookFor(m);
      String? raw;
      if (book != null) {
        if (userText == null) continue;
        await Future<void>.delayed(
            Duration(milliseconds: 600 + _rng.nextInt(900)));
        raw = book.reply(userText);
      } else if (ready) {
        final system = _groupPrompt(g, m);
        final instr = userText == null
            ? '(Le groupe est calme depuis ${_ago(idleMin)}. Écris un '
                'message spontané : lance un sujet ou interpelle quelqu\'un.)'
            : '(Écris maintenant ton message dans le groupe, en tant que '
                '${m.name}. Seulement ton message, sans ton prénom devant.)';
        final out = await _exclusive(() async {
          final conv = await _engine!.createConversation(_cfg(system));
          try {
            return (await conv.sendMessage(instr)).text;
          } finally {
            await conv.dispose();
          }
        });
        raw = out.replaceFirst(
            RegExp('^\\s*${RegExp.escape(m.name)}\\s*:\\s*',
                caseSensitive: false),
            '');
      }
      if (raw == null || raw.trim().isEmpty) continue;
      await _deliver(g, raw, sw, epoch, author: m);
    }
  }

  // Relances : si tu ne réponds plus, le contact t'écrit de lui-même
  // (2 fois maximum, puis il attend ton prochain message).
  void _nudgeTick() {
    if (!ready) return;
    final now = DateTime.now();
    for (final c in contacts) {
      if (!c.nudge || c.nudges >= 2 || c.messages.isEmpty) continue;
      if (generating.contains(c.id)) continue;
      if (c.isGroup ? membersOf(c).isEmpty : _bookFor(c) != null) continue;
      final last = c.messages.last;
      if (last.fromMe || last.text.startsWith('⚠️')) continue;
      final idle = now.difference(last.time).inMinutes;
      if (idle < (c.nudges == 0 ? 6 : 45) || idle > 7 * 24 * 60) continue;
      if (_rng.nextDouble() > 0.35) continue; // un peu d'imprévu
      c.nudges++;
      unawaited(_respond(c, idleMin: idle));
      return; // une relance à la fois
    }
  }

  // ----- Réponses préenregistrées -----
  ScriptBook? _bookFor(Contact c) {
    if (c.script.trim().isEmpty) return null;
    final b = ScriptBook.parse(c.script);
    return b.isEmpty ? null : b;
  }

  bool canReply(Contact c) => c.isGroup
      ? ready || membersOf(c).any((m) => _bookFor(m) != null)
      : ready || _bookFor(c) != null;

  // ----- Confort de chat -----
  Future<void> regenerate(Contact c) async {
    if (generating.contains(c.id) || !canReply(c)) return;
    while (c.messages.isNotEmpty && !c.messages.last.fromMe) {
      _dropAudio([c.messages.removeLast()]);
    }
    if (c.messages.isEmpty) return;
    final last = c.messages.removeLast();
    _dropConv(c.id);
    await send(c, last.text);
  }

  void deleteMessage(Contact c, Msg m) {
    if (generating.contains(c.id)) return;
    c.messages.remove(m);
    _dropAudio([m]);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> editAndResend(Contact c, Msg m, String text) async {
    if (generating.contains(c.id) || !canReply(c)) return;
    final i = c.messages.indexOf(m);
    if (i < 0) return;
    _dropAudio(c.messages.sublist(i));
    c.messages.removeRange(i, c.messages.length);
    _dropConv(c.id);
    await send(c, text);
  }

  String exportText(Contact c) {
    final b = StringBuffer('Discussion avec ${c.name}\n\n');
    for (final m in c.messages) {
      final t = m.time;
      b.writeln('[${t.day.toString().padLeft(2, '0')}/'
          '${t.month.toString().padLeft(2, '0')} ${_hhmm(t)}] '
          '${m.fromMe ? 'Moi' : (byId(m.from) ?? c).name} : ${m.text}');
    }
    return b.toString();
  }

  // Chargement automatique au lancement. Un fichier témoin évite une boucle
  // de plantage si le modèle est trop lourd pour le téléphone.
  Future<void> autoLoad() async {
    if (!downloaded.contains(modelId)) return;
    final flag = File('${_dir.path}/loading.flag');
    if (await flag.exists()) {
      await flag.delete();
      status = 'Le dernier chargement automatique a échoué : '
          'charge le modèle à la main (ou choisis un modèle plus léger).';
      notifyListeners();
      return;
    }
    await flag.writeAsString('1');
    await load();
    if (await flag.exists()) await flag.delete();
  }

  // ----- Mémoire, rafales de messages et temps d'écriture -----
  static final _memoRe = RegExp(
      r'\[\s*m[ée]mo(?:ire)?\s*:\s*([^\]\n]*)\]?',
      caseSensitive: false);

  String _extractMemory(Contact c, String text) {
    for (final m in _memoRe.allMatches(text)) {
      final info = (m.group(1) ?? '').trim();
      if (info.isEmpty || !c.memoryOn) continue;
      final n = ScriptBook.norm(info);
      if (c.memory.any((e) => ScriptBook.norm(e) == n)) continue;
      c.memory.add(info);
    }
    while (c.memory.length > 60) {
      c.memory.removeAt(0);
    }
    return text.replaceAll(_memoRe, '').trim();
  }

  static final _sepRe = RegExp(r'^\s*(?:-{3,}|\|{3})\s*$', multiLine: true);

  // Découpe en bulles ; un [VOCAL] au milieu d'un message en démarre un
  // nouveau (le texte avant part écrit, la suite part en vocal).
  List<String> _split(String text) => [
        for (final p in text.split(_sepRe))
          for (final q in p.split(
              RegExp(r'(?=\[\s*vocal\s*\])', caseSensitive: false)))
            if (q.trim().isNotEmpty) q.trim(),
      ];

  // Temps qu'aurait mis une personne à taper ce message.
  Duration _typingTime(String text) {
    if (typingCps <= 0) return Duration.zero;
    final ms = (text.characters.length * 1000 / typingCps).round();
    return Duration(milliseconds: ms.clamp(700, 30000));
  }

  static final _vocalRe =
      RegExp(r'^\s*\[\s*vocal\s*\]', caseSensitive: false);
  static final _vocalTagRe =
      RegExp(r'\[\s*vocal\s*\]\s*:?\s*', caseSensitive: false);

  /// L'IA « enregistre » un vocal : l'audio est fabriqué, puis on attend à
  /// peu près sa durée (le temps de parler) avant de l'envoyer.
  /// Renvoie false si la voix a échoué (le message part alors en texte).
  Future<bool> _sendVocal(Contact c, String text, Stopwatch sw, int epoch,
      bool first, Contact? author) async {
    final who = author ?? c;
    recording.add(c.id);
    notifyListeners();
    final sw2 = Stopwatch()..start();
    final name = 'vocal_${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      final r = await Voice.synth(text, '$_appDirPath/$name', who.voice);
      if (typingCps > 0) {
        var wait = Duration(milliseconds: min(r.ms, 60000)) - sw2.elapsed;
        if (first) wait -= sw.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      if ((_epoch[c.id] ?? 0) != epoch || !contacts.contains(c)) {
        _deletePhoto(name);
        return true;
      }
      c.messages.add(Msg(stripVoiceTags(text),
          fromMe: false,
          from: author?.id,
          audio: name,
          dur: r.ms,
          wave: r.wave,
          seconds: first ? sw.elapsedMilliseconds / 1000 : null));
      if (openChatId != c.id) c.unread++;
      _scheduleSave();
      return true;
    } catch (_) {
      _deletePhoto(name);
      return false;
    } finally {
      recording.remove(c.id);
      notifyListeners();
    }
  }

  Future<void> _deliver(Contact c, String raw, Stopwatch sw, int epoch,
      {bool timed = true, Contact? author}) async {
    final who = author ?? c; // dans un groupe : le membre qui écrit
    final genSeconds = sw.elapsedMilliseconds / 1000;
    final memBefore = who.memory.length;
    final text = _extractMemory(who, _clean(raw));
    var parts = _split(text);
    if (!who.multi && parts.length > 1 && !parts.any(_vocalRe.hasMatch)) {
      parts = [parts.join('\n\n')];
    }
    if (parts.isEmpty) parts = ['…'];
    if (who.memory.length != memBefore) _scheduleSave();
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      final isVocal = _vocalRe.hasMatch(p);
      p = p.replaceAll(_vocalTagRe, '').trim();
      if (p.isEmpty) continue;
      if (i > 0) {
        // Petite pause entre deux messages, comme une vraie personne.
        await Future<void>.delayed(
            Duration(milliseconds: 400 + _rng.nextInt(700)));
      }
      if (isVocal &&
          who.vocal &&
          Voice.available &&
          await _sendVocal(c, p, sw, epoch, i == 0, author)) {
        continue;
      }
      // Le temps de génération compte déjà comme temps d'écriture.
      var wait = _typingTime(p);
      if (i == 0) wait -= sw.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if ((_epoch[c.id] ?? 0) != epoch || !contacts.contains(c)) return;
      if (Eleven.ready) p = stripVoiceTags(p);
      if (p.isEmpty) continue;
      c.messages.add(Msg(
        p,
        fromMe: false,
        seconds: (timed && i == 0) ? genSeconds : null,
        from: author?.id,
      ));
      if (openChatId != c.id) {
        c.unread++;
      } else if (c.autoSpeak) {
        Voice.speak(p, who);
      }
      notifyListeners();
      _scheduleSave();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _nudgeTimer?.cancel();
    unload();
    super.dispose();
  }
}

// ---------------------------------------------------------------
//  Démarrage
// ---------------------------------------------------------------
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  final brain = Brain();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    brain.init().then((_) {
      if (mounted) setState(() => _ready = true);
      unawaited(brain.autoLoad());
    });
  }

  @override
  void dispose() {
    brain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ChatsPage(brain: brain);
  }
}

// ---------------------------------------------------------------
//  Liste des discussions
// ---------------------------------------------------------------
class Avatar extends StatelessWidget {
  const Avatar(this.c, {super.key, this.radius = 24});
  final Contact c;
  final double radius;

  @override
  Widget build(BuildContext context) => AvatarView(
      name: c.name, color: c.color, photo: c.photo, radius: radius);
}

class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.name,
    required this.color,
    this.photo,
    this.radius = 24,
  });
  final String name;
  final int color;
  final String? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final f = _photoFile(photo);
    // Décodage à la taille d'affichage (×2 pour garder de la marge au recadrage).
    final px = (radius * 4 * MediaQuery.of(context).devicePixelRatio).round();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(color),
      backgroundImage:
          f == null
          ? null
          : ResizeImage(FileImage(f),
              width: px, height: px, policy: ResizeImagePolicy.fit),
      onBackgroundImageError: f == null ? null : (_, __) {},
      child: f != null
          ? null
          : Text(
              name.trim().isEmpty
                  ? '?'
                  : name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.9,
                  fontWeight: FontWeight.bold),
            ),
    );
  }
}

Widget editPageFor(Brain brain, Contact c) => c.isGroup
    ? GroupEditPage(brain: brain, group: c)
    : ContactEditPage(brain: brain, contact: c);

/// Choisit une image dans la galerie et la copie dans le dossier de l'app.
/// Renvoie le nom du fichier créé (null si annulé).
Future<String?> pickPhotoFile() async {
  final res =
      await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  List<int>? bytes = f.bytes;
  if (bytes == null && f.path != null) {
    bytes = await File(f.path!).readAsBytes();
  }
  if (bytes == null) throw Exception('image illisible');
  final ext = (f.extension ?? 'jpg').toLowerCase();
  final name = 'avatar_${DateTime.now().microsecondsSinceEpoch}.$ext';
  await File('$_appDirPath/$name').writeAsBytes(bytes);
  return name;
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.brain});
  final Brain brain;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  Brain get brain => widget.brain;
  bool _searching = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: brain,
      builder: (context, _) {
        final list = [...brain.contacts]..sort((a, b) {
            final ta = a.messages.isEmpty
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : a.messages.last.time;
            final tb = b.messages.isEmpty
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : b.messages.last.time;
            return tb.compareTo(ta);
          });
        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty
            ? list
            : list.where((c) => c.name.toLowerCase().contains(q)).toList();
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un contact',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : const Text('IA Messenger',
                    style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
              ),
              IconButton(
                tooltip: 'Modèles IA',
                icon: Icon(brain.ready ? Icons.memory : Icons.memory_outlined,
                    color: brain.ready ? _waLight : Colors.white),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ModelsPage(brain: brain))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'group') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => GroupEditPage(brain: brain)));
                  } else if (v == 'backup') {
                    _backup();
                  } else if (v == 'restore') {
                    _restore();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'group', child: Text('Nouveau groupe')),
                  PopupMenuItem(value: 'backup', child: Text('Sauvegarder')),
                  PopupMenuItem(value: 'restore', child: Text('Restaurer')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (!brain.ready)
                Material(
                  color: Colors.amber.shade100,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber),
                    title: const Text('Aucun modèle chargé'),
                    subtitle: const Text('Touche pour télécharger / charger'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ModelsPage(brain: brain))),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    final last = c.messages.isEmpty ? null : c.messages.last;
                    final typing = brain.generating.contains(c.id);
                    final who = brain.typingName[c.id];
                    final author = last == null
                        ? ''
                        : last.fromMe
                            ? 'Toi : '
                            : (c.isGroup && last.from != null
                                ? '${brain.byId(last.from)?.name ?? '?'} : '
                                : '');
                    return Dismissible(
                      key: ValueKey(c.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async =>
                          await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Supprimer ${c.name} ?'),
                              content: Text(c.isGroup
                                  ? 'Le groupe et sa discussion seront effacés '
                                      '(pas ses membres).'
                                  : 'Le contact et sa discussion seront effacés.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Annuler')),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Supprimer')),
                              ],
                            ),
                          ) ??
                          false,
                      onDismissed: (_) => brain.deleteContact(c),
                      child: ListTile(
                      leading: Avatar(c),
                      title: Row(children: [
                        if (c.isGroup)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.groups, size: 18),
                          ),
                        Expanded(
                          child: Text(c.name,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      subtitle: Text(
                        typing
                            ? (brain.recording.contains(c.id)
                                ? '🎤 ${who != null ? '$who ' : ''}enregistre un audio…'
                                : who != null
                                    ? '$who est en train d\'écrire…'
                                    : 'en train d\'écrire…')
                            : (last == null
                                ? (c.isGroup
                                    ? brain.membersOf(c)
                                        .map((m) => m.name)
                                        .join(', ')
                                    : 'Dis bonjour 👋')
                                : last.audio != null
                                    ? '$author🎤 Message vocal (${_mmss(last.dur ?? 0)})'
                                    : '$author${last.text}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: typing ? _waLight : null,
                            fontStyle:
                                typing ? FontStyle.italic : FontStyle.normal),
                      ),
                      trailing: last == null
                          ? null
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_dayLabel(last.time),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: c.unread > 0
                                            ? _waLight
                                            : Theme.of(context).hintColor)),
                                if (c.unread > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: _waLight,
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text('${c.unread}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ChatPage(brain: brain, contact: c))),
                      onLongPress: () => _contactMenu(context, c),
                    ));
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ContactEditPage(brain: brain))),
            child: const Icon(Icons.person_add),
          ),
        );
      },
    );
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _backup() async {
    try {
      final bytes = await brain.exportBackup();
      final d = DateTime.now();
      final name = 'ia_messenger_${d.year}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde',
        fileName: name,
        bytes: bytes,
      );
      if (path != null) _snack('Sauvegarde enregistrée ✅');
    } catch (e) {
      _snack('Erreur de sauvegarde : $e');
    }
  }

  Future<void> _restore() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      List<int>? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null || !mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restaurer la sauvegarde ?'),
          content: const Text('Tous les contacts, groupes, souvenirs et '
              'discussions actuels seront remplacés par ceux du fichier.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remplacer')),
          ],
        ),
      );
      if (ok != true) return;
      final n = await brain.importBackup(bytes);
      _snack('$n discussion(s) restaurée(s) ✅');
    } catch (e) {
      _snack('Erreur de restauration : $e');
    }
  }

  void _contactMenu(BuildContext context, Contact c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(c.isGroup ? 'Modifier le groupe' : 'Modifier le contact'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => editPageFor(brain, c)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: const Text('Vider la discussion'),
            onTap: () {
              Navigator.pop(ctx);
              brain.clearChat(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(
                c.isGroup ? 'Supprimer le groupe' : 'Supprimer le contact'),
            onTap: () {
              Navigator.pop(ctx);
              brain.deleteContact(c);
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------
//  Création / édition d'un contact
// ---------------------------------------------------------------
class ContactEditPage extends StatefulWidget {
  const ContactEditPage({super.key, required this.brain, this.contact});
  final Brain brain;
  final Contact? contact;

  @override
  State<ContactEditPage> createState() => _ContactEditPageState();
}

class _ContactEditPageState extends State<ContactEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _memory;
  late double _age;
  late int _color;
  String _script = '';
  String? _photo;
  String? _origPhoto;
  bool _saved = false;
  int _length = 1;
  bool _multi = true;
  bool _memoryOn = true;
  bool _nudge = true;
  bool _vocal = true;
  String _voice = 'ado';

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nudge = c?.nudge ?? true;
    _vocal = c?.vocal ?? true;
    _voice = c?.voice ?? 'ado';
    _script = c?.script ?? '';
    _photo = _origPhoto = c?.photo;
    _length = c?.length ?? 1;
    _multi = c?.multi ?? true;
    _memoryOn = c?.memoryOn ?? true;
    _memory = TextEditingController(text: c?.memory.join('\n') ?? '');
    _name = TextEditingController(text: c?.name ?? '');
    _desc = TextEditingController(text: c?.description ?? '');
    _age = (c?.age ?? 12).clamp(10, 60).toDouble();
    _color = c?.color ?? _palette[widget.brain.contacts.length % _palette.length];
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _memory.dispose();
    // Photo choisie puis abandonnée : on ne garde pas le fichier.
    if (!_saved && _photo != _origPhoto) _deletePhoto(_photo);
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t)));

  Future<void> _importScript() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      List<int>? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) throw Exception('fichier illisible');
      var txt = utf8.decode(bytes, allowMalformed: true);
      if (txt.startsWith('\uFEFF')) txt = txt.substring(1);
      final book = ScriptBook.parse(txt);
      if (book.isEmpty) {
        _snack('Aucune ligne valide (format : déclencheur => réponse).');
        return;
      }
      setState(() => _script = txt);
      _snack('${book.rules.length} règle(s) importée(s) — '
          'touche ✓ pour enregistrer.');
    } catch (e) {
      _snack('Erreur d\'import : $e');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final name = await pickPhotoFile();
      if (name == null) return;
      if (_photo != _origPhoto) _deletePhoto(_photo);
      if (mounted) setState(() => _photo = name);
    } catch (e) {
      _snack('Erreur photo : $e');
    }
  }

  void _photoMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choisir une photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickPhoto();
            },
          ),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.hide_image, color: Colors.red),
              title: const Text('Retirer la photo'),
              onTap: () {
                Navigator.pop(ctx);
                if (_photo != _origPhoto) _deletePhoto(_photo);
                setState(() => _photo = null);
              },
            ),
        ]),
      ),
    );
  }

  void _scriptHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Format du fichier .txt'),
        content: const SingleChildScrollView(
          child: Text(
            '# ceci est un commentaire\n'
            'bonjour | salut | coucou => Salut ! | Hey, ça va ?\n'
            'ça va => Super, et toi ?\n'
            'tu fais quoi => Je joue à la console\\nEt toi ?\n'
            '* => Hmm, je ne sais pas quoi dire.\n\n'
            '• Gauche : un ou plusieurs déclencheurs séparés par |\n'
            '• Droite : une ou plusieurs réponses séparées par | '
            '(une est tirée au hasard)\n'
            '• \\n = retour à la ligne dans une réponse\n'
            '• \\n---\\n = envoyer la suite dans un 2e message\n'
            '• La ligne « * » sert quand rien ne correspond\n'
            '• Majuscules, accents et ponctuation sont ignorés',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final c = widget.contact ??
        Contact(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          age: _age.round(),
          description: '',
          color: _color,
        );
    c
      ..name = name
      ..age = _age.round()
      ..description = _desc.text.trim()
      ..color = _color
      ..script = _script
      ..photo = _photo
      ..length = _length
      ..multi = _multi
      ..memoryOn = _memoryOn
      ..nudge = _nudge
      ..vocal = _vocal
      ..voice = _voice
      ..memory = [
        for (final l in _memory.text.split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];
    if (_origPhoto != _photo) _deletePhoto(_origPhoto);
    _saved = true;
    widget.brain.addOrUpdate(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contact == null ? 'Nouveau contact' : 'Modifier'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _photoMenu,
              child: Stack(children: [
                AvatarView(
                    name: _name.text,
                    color: _color,
                    photo: _photo,
                    radius: 48),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: _waLight,
                    child: const Icon(Icons.photo_camera,
                        size: 18, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _photoMenu,
              child: Text(_photo == null
                  ? 'Ajouter une photo'
                  : 'Changer la photo'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final p in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = p),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(p),
                    child: _color == p
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Prénom', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('Âge : ${_age.round()} ans'),
          Slider(
            min: 10,
            max: 60,
            divisions: 50,
            value: _age,
            label: '${_age.round()}',
            onChanged: (v) => setState(() => _age = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Personnalité / contexte',
              hintText: 'ex : grand frère protecteur, calme, fan de foot…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Façon d\'écrire',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Courts')),
                      ButtonSegment(value: 1, label: Text('Variables')),
                      ButtonSegment(value: 2, label: Text('Longs')),
                    ],
                    selected: {_length},
                    onSelectionChanged: (v) =>
                        setState(() => _length = v.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Plusieurs messages d\'affilée'),
                    subtitle: const Text(
                        'L\'IA peut découper sa réponse en plusieurs bulles'),
                    value: _multi,
                    onChanged: (v) => setState(() => _multi = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('M\'écrit de lui-même'),
                    subtitle: const Text('Relance la discussion si tu ne '
                        'réponds plus (app ouverte)'),
                    value: _nudge,
                    onChanged: (v) => setState(() => _nudge = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Envoie des messages vocaux'),
                    subtitle: Text(Voice.available
                        ? 'Il/elle décide quand envoyer un vocal'
                        : 'Configure d\'abord une voix dans « Modèles IA »'),
                    value: _vocal,
                    onChanged: (v) => setState(() => _vocal = v),
                  ),
                  Row(children: [
                    const Text('Voix '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: voicePresets.containsKey(_voice) ? _voice : 'ado',
                        items: [
                          for (final e in voicePresets.entries)
                            DropdownMenuItem(
                                value: e.key, child: Text(e.value.$1)),
                        ],
                        onChanged: (v) => setState(() => _voice = v ?? 'ado'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tester la voix',
                      icon: const Icon(Icons.volume_up),
                      onPressed: () {
                        final who = Contact(
                            id: '_test',
                            name: _name.text,
                            age: _age.round(),
                            description: '',
                            color: _color,
                            voice: _voice);
                        Voice.stop();
                        Voice.speak(
                            'Coucou ! C\'est ${_name.text.trim().isEmpty ? 'moi' : _name.text.trim()}. '
                            'Ça va toi ? Moi trop bien !',
                            who);
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mémoire',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('L\'IA retient ce que tu lui dis '
                        'et s\'en souvient dans les prochaines discussions'),
                    value: _memoryOn,
                    onChanged: (v) => setState(() => _memoryOn = v),
                  ),
                  TextField(
                    controller: _memory,
                    minLines: 3,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: 'Souvenirs (un par ligne)',
                      hintText: 'ex : s\'appelle Lucas\naime le basket',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      suffixIcon: IconButton(
                        tooltip: 'Tout effacer',
                        icon: const Icon(Icons.delete_sweep),
                        onPressed: () => setState(_memory.clear),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Réponses préenregistrées',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_script.trim().isEmpty
                      ? 'Aucun fichier : ce contact répond avec l\'IA.'
                      : '${ScriptBook.parse(_script).rules.length} règle(s) '
                          'chargée(s) : ce contact répond avec le fichier, '
                          'sans IA.'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _importScript,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Importer un .txt'),
                    ),
                    if (_script.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _script = ''),
                        icon: const Icon(Icons.close),
                        label: const Text('Retirer'),
                      ),
                    TextButton(
                        onPressed: _scriptHelp, child: const Text('Format ?')),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
//  Création / édition d'un groupe
// ---------------------------------------------------------------
class GroupEditPage extends StatefulWidget {
  const GroupEditPage({super.key, required this.brain, this.group});
  final Brain brain;
  final Contact? group;

  @override
  State<GroupEditPage> createState() => _GroupEditPageState();
}

class _GroupEditPageState extends State<GroupEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _topic;
  late int _color;
  late final Set<String> _members;
  String? _photo;
  String? _origPhoto;
  bool _saved = false;
  bool _nudge = true;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _name = TextEditingController(text: g?.name ?? '');
    _topic = TextEditingController(text: g?.description ?? '');
    _color = g?.color ??
        _palette[widget.brain.contacts.length % _palette.length];
    _members = {...?g?.members};
    _photo = _origPhoto = g?.photo;
    _nudge = g?.nudge ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    if (!_saved && _photo != _origPhoto) _deletePhoto(_photo);
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final name = await pickPhotoFile();
      if (name == null) return;
      if (_photo != _origPhoto) _deletePhoto(_photo);
      if (mounted) setState(() => _photo = name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur photo : $e')));
      }
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donne un nom au groupe.')));
      return;
    }
    if (_members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choisis au moins 2 contacts pour le groupe.')));
      return;
    }
    final g = widget.group ??
        Contact(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          age: 18,
          description: '',
          color: _color,
          isGroup: true,
        );
    final contacts = widget.brain.contacts;
    g
      ..name = name
      ..description = _topic.text.trim()
      ..color = _color
      ..photo = _photo
      ..nudge = _nudge
      // On garde l'ordre des contacts.
      ..members = [
        for (final c in contacts)
          if (_members.contains(c.id)) c.id,
      ];
    if (_origPhoto != _photo) _deletePhoto(_origPhoto);
    _saved = true;
    widget.brain.addOrUpdate(g);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final people =
        widget.brain.contacts.where((c) => !c.isGroup).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? 'Nouveau groupe' : 'Modifier le groupe'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(children: [
                AvatarView(
                    name: _name.text,
                    color: _color,
                    photo: _photo,
                    radius: 48),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: _waLight,
                    child: Icon(Icons.photo_camera,
                        size: 18, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
          if (_photo != null)
            Center(
              child: TextButton(
                onPressed: () {
                  if (_photo != _origPhoto) _deletePhoto(_photo);
                  setState(() => _photo = null);
                },
                child: const Text('Retirer la photo'),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final p in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = p),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(p),
                    child: _color == p
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Nom du groupe', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topic,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Sujet / contexte (facultatif)',
              hintText: 'ex : les potes du lycée qui organisent un week-end',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Les membres écrivent d\'eux-mêmes'),
            subtitle: const Text('Le groupe s\'anime quand personne ne parle'),
            value: _nudge,
            onChanged: (v) => setState(() => _nudge = v),
          ),
          const SizedBox(height: 8),
          Text('Membres (${_members.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Crée d\'abord des contacts.'),
            ),
          for (final c in people)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Avatar(c, radius: 20),
              title: Text(c.name),
              subtitle: Text('${c.age} ans'),
              value: _members.contains(c.id),
              onChanged: (v) => setState(() =>
                  v == true ? _members.add(c.id) : _members.remove(c.id)),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
//  Discussion
// ---------------------------------------------------------------
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.brain, required this.contact});
  final Brain brain;
  final Contact contact;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = -1;
  bool _listening = false;
  bool _searching = false;
  String _query = '';
  Msg? _highlight;
  final Map<Msg, GlobalKey> _keys = {};

  Brain get brain => widget.brain;
  Contact get c => widget.contact;

  @override
  void initState() {
    super.initState();
    brain.openChatId = c.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => brain.openChat(c));
  }

  @override
  void dispose() {
    brain.closeChat(c);
    if (_listening) Voice.stt.stop();
    Voice.stop();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ----- Dictée -----
  Future<void> _toggleMic() async {
    if (_listening) {
      await Voice.stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final ok = await Voice.stt.initialize();
      Voice.stt.statusListener = (st) {
        if ((st == 'done' || st == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      };
      Voice.stt.errorListener = (_) {
        if (mounted) setState(() => _listening = false);
      };
      if (!ok) {
        _snack('Dictée indisponible : autorise le micro pour l\'app.');
        return;
      }
      final base = _ctrl.text.trim();
      setState(() => _listening = true);
      await Voice.stt.listen(
        onResult: (r) {
          final t = r.recognizedWords;
          _ctrl.text = base.isEmpty ? t : '$base $t';
          _ctrl.selection =
              TextSelection.collapsed(offset: _ctrl.text.length);
        },
        listenOptions: SpeechListenOptions(
          localeId: 'fr_FR',
          partialResults: true,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _listening = false);
      _snack('Erreur de dictée : $e');
    }
  }

  // ----- Recherche -----
  List<Msg> get _matches {
    final q = ScriptBook.norm(_query);
    if (q.isEmpty) return const [];
    return [
      for (final m in c.messages)
        if (ScriptBook.norm(m.text).contains(q)) m,
    ];
  }

  void _jumpTo(Msg m) {
    setState(() {
      _searching = false;
      _query = '';
      _highlight = m;
    });
    final i = c.messages.indexOf(m);
    var tries = 0;
    void attempt() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[m]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: 0.3, duration: const Duration(milliseconds: 250));
          return;
        }
        // Message pas encore construit : on saute à sa position estimée.
        if (_scroll.hasClients && i >= 0 && tries++ < 6) {
          final extent = _scroll.position.maxScrollExtent;
          _scroll.jumpTo(extent * i / max(1, c.messages.length - 1));
          attempt();
        }
      });
    }

    attempt();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && identical(_highlight, m)) setState(() => _highlight = null);
    });
  }

  Widget _searchResults() {
    final res = _matches;
    if (_query.trim().isEmpty) {
      return const Center(child: Text('Tape un mot à chercher'));
    }
    if (res.isEmpty) return const Center(child: Text('Aucun message trouvé'));
    return ListView.separated(
      itemCount: res.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = res[res.length - 1 - i]; // les plus récents en haut
        final who = m.fromMe ? 'Toi' : (brain.byId(m.from) ?? c).name;
        final t = m.time;
        return ListTile(
          title: Text('${m.audio != null ? '🎤 ' : ''}${m.text}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('$who · ${t.day.toString().padLeft(2, '0')}/'
              '${t.month.toString().padLeft(2, '0')} ${_hhmm(t)}'),
          onTap: () => _jumpTo(m),
        );
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (!brain.canReply(c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Charge d\'abord un modèle (icône puce en haut).')));
      return;
    }
    if (_listening) {
      await Voice.stt.stop();
      setState(() => _listening = false);
    }
    _ctrl.clear();
    unawaited(brain.send(c, text));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: brain,
      builder: (context, _) {
        final typing = brain.generating.contains(c.id);
        final count = c.messages.length + (typing ? 1 : 0);
        if (count != _lastCount) {
          _lastCount = count;
          _scrollToEnd();
        }
        return Scaffold(
          appBar: _searching
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() {
                      _searching = false;
                      _query = '';
                    }),
                  ),
                  title: TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher dans la discussion',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                )
              : AppBar(
            titleSpacing: 0,
            title: Row(children: [
              Avatar(c, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17)),
                    Text(
                        typing
                            ? (brain.recording.contains(c.id)
                                ? (brain.typingName[c.id] != null
                                    ? '${brain.typingName[c.id]} enregistre un audio…'
                                    : 'enregistre un audio…')
                                : brain.typingName[c.id] != null
                                    ? '${brain.typingName[c.id]} écrit…'
                                    : 'en train d\'écrire…')
                            : (c.isGroup
                                ? brain.membersOf(c).map((m) => m.name).join(', ')
                                : 'en ligne'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.normal)),
                  ],
                ),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'Rechercher',
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => editPageFor(brain, c)));
                  } else if (v == 'speak') {
                    brain.setAutoSpeak(c, !c.autoSpeak);
                  } else if (v == 'memory') {
                    _memoryDialog();
                  } else if (v == 'clear') {
                    brain.clearChat(c);
                  } else if (v == 'export') {
                    Clipboard.setData(
                        ClipboardData(text: brain.exportText(c)));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Discussion copiée dans le presse-papiers')));
                  } else if (v == 'models') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ModelsPage(brain: brain)));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit',
                      child: Text(c.isGroup
                          ? 'Modifier le groupe'
                          : 'Modifier le contact')),
                  if (!c.isGroup)
                    const PopupMenuItem(value: 'memory', child: Text('Mémoire')),
                  CheckedPopupMenuItem(
                      value: 'speak',
                      checked: c.autoSpeak,
                      child: const Text('Lire les messages à voix haute')),
                  const PopupMenuItem(value: 'models', child: Text('Modèles IA')),
                  const PopupMenuItem(
                      value: 'export', child: Text('Exporter (copier)')),
                  const PopupMenuItem(
                      value: 'clear', child: Text('Vider la discussion')),
                ],
              ),
            ],
          ),
          body: _searching
              ? _searchResults()
              : Container(
            color: _dark(context) ? const Color(0xFF0B141A) : _chatBg,
            child: Column(
              children: [
                Expanded(
                  child: Builder(builder: (context) {
                    final items = <Object>[];
                    DateTime? prev;
                    for (final m in c.messages) {
                      if (prev == null ||
                          prev.year != m.time.year ||
                          prev.month != m.time.month ||
                          prev.day != m.time.day) {
                        items.add(m.time);
                      }
                      items.add(m);
                      prev = m.time;
                    }
                    if (typing) items.add('typing');
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        if (it is DateTime) return _daySep(it);
                        if (it is Msg) return _bubble(it);
                        return _typingBubble();
                      },
                    );
                  }),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Message',
                              filled: true,
                              fillColor: _dark(context)
                                  ? const Color(0xFF202C33)
                                  : Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _ctrl,
                          builder: (context, v, _) {
                            final mic = v.text.trim().isEmpty || _listening;
                            return CircleAvatar(
                              backgroundColor:
                                  _listening ? Colors.red : _waGreen,
                              child: IconButton(
                                tooltip: mic
                                    ? (_listening ? 'Arrêter' : 'Dicter')
                                    : 'Envoyer',
                                icon: Icon(
                                    mic
                                        ? (_listening ? Icons.stop : Icons.mic)
                                        : Icons.send,
                                    color: Colors.white),
                                onPressed: mic
                                    ? _toggleMic
                                    : (typing ? null : _send),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Widget _daySep(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    final label = diff == 0
        ? 'Aujourd\'hui'
        : diff == 1
            ? 'Hier'
            : '${t.day.toString().padLeft(2, '0')}/'
                '${t.month.toString().padLeft(2, '0')}/${t.year}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _dark(context)
              ? const Color(0xFF182229)
              : const Color(0xFFFFF3C4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: _dark(context) ? Colors.white70 : Colors.black87)),
      ),
    );
  }

  Future<void> _msgMenu(Msg m) async {
    final isLast = c.messages.isNotEmpty && identical(c.messages.last, m);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copier'),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: m.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Message copié'),
                  duration: Duration(seconds: 1)));
            },
          ),
          if (!m.fromMe && m.audio == null)
            ListTile(
              leading: const Icon(Icons.volume_up),
              title: const Text('Écouter'),
              onTap: () {
                Navigator.pop(ctx);
                Voice.stop();
                Voice.speak(m.text, brain.byId(m.from) ?? c);
              },
            ),
          if (m.fromMe)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Modifier et renvoyer'),
              onTap: () {
                Navigator.pop(ctx);
                _editDialog(m);
              },
            ),
          if (isLast && !m.fromMe)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Régénérer la réponse'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(brain.regenerate(c));
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Supprimer ce message'),
            onTap: () {
              Navigator.pop(ctx);
              brain.deleteMessage(c, m);
            },
          ),
        ]),
      ),
    );
  }

  void _memoryDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: brain,
        builder: (ctx, _) => AlertDialog(
          title: Text('Mémoire de ${c.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: c.memory.isEmpty
                ? Text(c.memoryOn
                    ? 'Rien pour l\'instant. Raconte-lui des choses sur toi, '
                        'il/elle notera ce qui est important.'
                    : 'La mémoire est désactivée pour ce contact.')
                : ListView(shrinkWrap: true, children: [
                    for (final m in c.memory)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.psychology, size: 20),
                        title: Text(m),
                      ),
                  ]),
          ),
          actions: [
            if (c.memory.isNotEmpty)
              TextButton(
                  onPressed: () => brain.clearMemory(c),
                  child: const Text('Tout oublier')),
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ContactEditPage(brain: brain, contact: c)));
                },
                child: const Text('Modifier')),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  Future<void> _editDialog(Msg m) async {
    if (!brain.canReply(c)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Charge d\'abord un modèle (icône puce).')));
      return;
    }
    final ctrl = TextEditingController(text: m.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 5, minLines: 1),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Renvoyer')),
        ],
      ),
    );
    ctrl.dispose();
    if (text != null && text.isNotEmpty) {
      unawaited(brain.editAndResend(c, m, text));
    }
  }

  Widget _typingBubble() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: _dark(context) ? const Color(0xFF202C33) : Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: brain.recording.contains(c.id)
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic, color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Text('enregistre un audio…',
                      style: TextStyle(
                          fontSize: 13, fontStyle: FontStyle.italic)),
                ])
              : const SizedBox(
                  width: 24,
                  height: 14,
                  child: LinearProgressIndicator(minHeight: 3)),
        ),
      );

  Widget _bubble(Msg m) {
    final author = (c.isGroup && !m.fromMe) ? brain.byId(m.from) : null;
    return Align(
      key: _keys.putIfAbsent(m, GlobalKey.new),
      alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _msgMenu(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          foregroundDecoration: identical(_highlight, m)
              ? BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12))
              : null,
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: m.fromMe
                ? (_dark(context) ? const Color(0xFF005C4B) : _bubbleMe)
                : (_dark(context) ? const Color(0xFF202C33) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(m.fromMe ? 12 : 2),
              bottomRight: Radius.circular(m.fromMe ? 2 : 12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.isGroup && !m.fromMe)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(author?.name ?? 'Ancien membre',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(author?.color ?? 0xFF888888))),
                  ),
                ),
              if (m.audio != null)
                VoiceBubble(
                    msg: m, who: author ?? c, dark: _dark(context))
              else
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(m.text,
                      style: TextStyle(
                          fontSize: 15.5,
                          color: _dark(context)
                              ? Colors.white
                              : Colors.black87))),
              const SizedBox(height: 2),
              Text(
                m.seconds != null
                    ? '${_hhmm(m.time)} · ⏱ ${m.seconds!.toStringAsFixed(1)} s'
                    : _hhmm(m.time),
                style: TextStyle(
                    fontSize: 10.5,
                    color: _dark(context) ? Colors.white54 : Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
//  Bulle de message vocal
// ---------------------------------------------------------------
String _mmss(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class VoiceBubble extends StatefulWidget {
  const VoiceBubble(
      {super.key, required this.msg, required this.who, required this.dark});
  final Msg msg;
  final Contact who;
  final bool dark;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  bool _showText = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    final path = '$_appDirPath/${m.audio}';
    final exists = File(path).existsSync();
    final total = m.dur ?? 0;
    final fg = widget.dark ? Colors.white : Colors.black87;
    final dim = widget.dark ? Colors.white38 : Colors.black26;
    final accent = widget.dark ? const Color(0xFF53BDEB) : const Color(0xFF34B7F1);
    return ListenableBuilder(
      listenable: AudioHub.i,
      builder: (context, _) {
        final hub = AudioHub.i;
        final active = hub.path == path;
        final playing = active && hub.playing;
        final ms = active ? hub.pos.inMilliseconds : 0;
        final progress = total > 0 ? (ms / total).clamp(0.0, 1.0) : 0.0;
        final wave = m.wave ?? List.filled(48, 0.3);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Avatar(widget.who, radius: 20),
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Icon(Icons.mic,
                      size: 18, color: active ? accent : _waLight),
                ),
              ]),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 34,
                color: fg,
                icon: Icon(exists
                    ? (playing ? Icons.pause : Icons.play_arrow)
                    : Icons.error_outline),
                onPressed: exists ? () => hub.toggle(path) : null,
              ),
              SizedBox(
                width: 150,
                height: 34,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: !exists
                      ? null
                      : (d) => hub.seek(
                          path, (d.localPosition.dx / 150).clamp(0.0, 1.0), total),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var k = 0; k < wave.length; k++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.6),
                            height: 4 + 28 * wave[k],
                            decoration: BoxDecoration(
                              color: (k + 0.5) / wave.length <= progress && active
                                  ? accent
                                  : dim,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 92),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(exists ? _mmss(active ? ms : total) : 'audio indisponible',
                    style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.6))),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _showText = !_showText),
                  child: Text(_showText ? 'masquer le texte' : 'transcription',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: accent,
                          decoration: TextDecoration.underline)),
                ),
              ]),
            ),
            if (_showText || !exists)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.text,
                    style: TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic, color: fg)),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------
//  Création d'une voix ElevenLabs (on choisit à l'oreille)
// ---------------------------------------------------------------
class VoiceDesignPage extends StatefulWidget {
  const VoiceDesignPage({super.key, required this.brain});
  final Brain brain;

  @override
  State<VoiceDesignPage> createState() => _VoiceDesignPageState();
}

class _VoiceDesignPageState extends State<VoiceDesignPage> {
  final _desc = TextEditingController(text: elevenDefaultDescription);
  final _name = TextEditingController(text: 'Ado 15 ans');
  List<(String, String)> _previews = [];
  int? _chosen;
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    AudioHub.i.stop();
    _desc.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _status = 'Création des voix (≈ 20 s)…';
      _previews = [];
      _chosen = null;
    });
    try {
      final res = await Eleven.design(_desc.text.trim(), Eleven.key);
      setState(() {
        _previews = res;
        _status = 'Écoute les essais et choisis ta préférée.';
      });
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final i = _chosen;
    if (i == null) return;
    setState(() {
      _busy = true;
      _status = 'Enregistrement de la voix…';
    });
    try {
      final name = _name.text.trim().isEmpty ? 'Ado 15 ans' : _name.text.trim();
      final id = await Eleven.save(
          _previews[i].$1, name, _desc.text.trim(), Eleven.key);
      await widget.brain.setEleven(voiceId: id, name: name);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      setState(() => _status = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer une voix')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Décris la voix (en anglais, c\'est plus précis) :'),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_previews.isEmpty
                ? 'Générer des essais'
                : 'Générer d\'autres essais'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status),
          ],
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: AudioHub.i,
            builder: (context, _) => RadioGroup<int>(
              groupValue: _chosen,
              onChanged: (v) => setState(() => _chosen = v),
              child: Column(children: [
                for (var i = 0; i < _previews.length; i++)
                  RadioListTile<int>(
                    value: i,
                    title: Text('Essai ${i + 1}'),
                    secondary: IconButton(
                      iconSize: 34,
                      icon: Icon(AudioHub.i.path == _previews[i].$2 &&
                              AudioHub.i.playing
                          ? Icons.pause_circle
                          : Icons.play_circle),
                      onPressed: () => AudioHub.i.toggle(_previews[i].$2),
                    ),
                  ),
              ]),
            ),
          ),
          if (_previews.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Nom de la voix', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_chosen == null || _busy) ? null : _save,
              child: const Text('Utiliser cette voix'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
//  Gestion des modèles
// ---------------------------------------------------------------
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.brain});
  final Brain brain;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  late final TextEditingController _repo;
  late final TextEditingController _elKey;
  late final TextEditingController _elVoice;
  bool _showKey = false;

  Brain get b => widget.brain;

  @override
  void initState() {
    super.initState();
    _repo = TextEditingController(text: b.customRepo);
    _elKey = TextEditingController(text: Eleven.key);
    _elVoice = TextEditingController(text: Eleven.voiceId);
  }

  @override
  void dispose() {
    _repo.dispose();
    _elKey.dispose();
    _elVoice.dispose();
    super.dispose();
  }

  Widget _elevenSection() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voix ElevenLabs (ultra réaliste)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Utilisée en priorité pour les vocaux, avec les émotions '
                  '(rires, soupirs, chuchotements…). Nécessite Internet : le '
                  'texte des vocaux est envoyé à ElevenLabs et consomme ton '
                  'quota de caractères.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: _elKey,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Clé API ElevenLabs',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
                onChanged: (v) => b.setEleven(key: v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _elVoice,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'ID de la voix',
                  helperText: Eleven.voiceName.isEmpty
                      ? 'Crée une voix ci-dessous, ou colle l\'ID d\'une voix'
                      : 'Voix : ${Eleven.voiceName}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => b.setEleven(voiceId: v, name: ''),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: Eleven.key.isEmpty
                      ? null
                      : () async {
                          final id = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => VoiceDesignPage(brain: b)));
                          if (id != null) _elVoice.text = id;
                        },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Créer une voix'),
                ),
                OutlinedButton.icon(
                  onPressed: Eleven.ready
                      ? () {
                          Voice.stop();
                          Voice.speak(elevenPreviewText,
                              Contact(
                                  id: '_test',
                                  name: '',
                                  age: 15,
                                  description: '',
                                  color: 0));
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Tester'),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                  Eleven.ready
                      ? '✅ Les vocaux utilisent ElevenLabs.'
                      : 'Non configuré : les vocaux utilisent la voix locale '
                          '(si installée).',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final busy = b.progress != null || b.loading;
        final m = b.model;
        final isDown = b.downloaded.contains(m.id);
        final options = [
          ...baseModels,
          const ModelOption(
              id: _customId,
              name: 'Modèle perso (Hugging Face)',
              note: 'dépôt LiteRT-LM ou URL directe .litertlm'),
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Modèles IA')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Modèle',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              RadioGroup<String>(
                groupValue: b.modelId,
                onChanged: (v) {
                  if (!busy && v != null) b.selectModel(v);
                },
                child: Column(children: [
                  for (final o in options)
                    RadioListTile<String>(
                      value: o.id,
                      title: Text(o.name),
                      subtitle: Text(
                          '${o.note}${b.downloaded.contains(o.id) ? '\n✅ téléchargé' : ''}'),
                      isThreeLine: b.downloaded.contains(o.id),
                    ),
                ]),
              ),
              if (b.modelId == _customId)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: _repo,
                    onChanged: b.setCustomRepo,
                    decoration: const InputDecoration(
                      labelText: 'Dépôt (auteur/nom) ou URL .litertlm',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              if (b.progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: b.progress),
                const SizedBox(height: 4),
                Text('${((b.progress ?? 0) * 100).toStringAsFixed(0)} %  '
                    '(garde l\'écran allumé, en Wi-Fi)'),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (isDown || busy) ? null : b.download,
                    icon: const Icon(Icons.download),
                    label: const Text('Télécharger'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Supprimer le fichier',
                  onPressed: (!isDown || busy) ? null : b.deleteModel,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              const SizedBox(height: 24),
              const Text('Processeur',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<LiteLmBackend>(
                segments: const [
                  ButtonSegment(
                      value: LiteLmBackend.cpu, label: Text('CPU (sûr)')),
                  ButtonSegment(
                      value: LiteLmBackend.gpu, label: Text('GPU (rapide ?)')),
                ],
                selected: {b.backend},
                onSelectionChanged:
                    busy ? null : (s) => b.setBackend(s.first),
              ),
              const SizedBox(height: 24),
              const Text('Temps d\'écriture simulé',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Plus un message est long, plus « en train d\'écrire… » '
                  'dure, comme une vraie personne.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  for (final e in _typingSpeeds.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {
                  _typingSpeeds.containsKey(b.typingCps) ? b.typingCps : 20
                },
                onSelectionChanged: (v) => b.setTypingCps(v.first),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (isDown && !busy)
                    ? () async {
                        final ok = await b.load();
                        if (ok && context.mounted) Navigator.pop(context);
                      }
                    : null,
                icon: const Icon(Icons.memory),
                label: Text(b.loading ? 'Chargement…' : 'Charger le modèle'),
              ),
              if (b.ready) ...[
                const SizedBox(height: 8),
                Text('Actuellement chargé : ${b.loadedId}',
                    style: const TextStyle(color: Colors.green)),
              ],
              if (b.status.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(b.status),
              ],
              const SizedBox(height: 24),
              _elevenSection(),
              const SizedBox(height: 16),
              const Text('Voix locale (hors ligne)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  Voice.neuralReady
                      ? '✅ Voix réaliste installée (féminine, ado par défaut). '
                          'Les contacts peuvent t\'envoyer des vocaux.'
                      : 'Voix neuronale réaliste, 100 % hors ligne '
                          '(≈ 67 Mo). Nécessaire pour que les contacts '
                          'envoient des vocaux.',
                  style: const TextStyle(fontSize: 12)),
              if (b.voiceProgress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: b.voiceProgress),
              ],
              if (b.voiceStatus.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(b.voiceStatus, style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: (Voice.neuralReady || b.voiceProgress != null)
                        ? null
                        : b.downloadVoice,
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text('Installer la voix'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Écouter un exemple',
                  onPressed: Voice.neuralReady
                      ? () {
                          Voice.stop();
                          Voice.speak(
                              'Coucou ! Ça va toi ? Moi j\'ai trop rigolé '
                              'aujourd\'hui. Par contre j\'ai raté mon '
                              'contrôle de maths…',
                              Contact(
                                  id: '_test',
                                  name: '',
                                  age: 15,
                                  description: '',
                                  color: 0));
                        }
                      : null,
                  icon: const Icon(Icons.play_circle_outline),
                ),
                IconButton(
                  tooltip: 'Supprimer la voix',
                  onPressed: (Voice.neuralReady && b.voiceProgress == null)
                      ? b.deleteVoice
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              const SizedBox(height: 24),
              const Text(
                'Les modèles tournent 100 % sur ton téléphone. '
                'Un modèle non censuré n\'applique aucun filtre de lui-même : '
                'les personnages de moins de 18 ans reçoivent des règles '
                'strictes (aucun contenu sexuel ou romantique).',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
