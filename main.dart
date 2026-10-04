// ============================================================
//  Messagerie façon WhatsApp avec une IA 100 % locale
//  (flutter_litert_lm + path_provider uniquement)
//
//  - Plusieurs contacts IA (nom, âge >= 18, personnalité, couleur)
//  - Conversations sauvegardées sur le téléphone
//  - Gestionnaire de modèles : Qwen 2.5 1.5B, Qwen 3 0.6B,
//    un modèle non censuré (abliterated) et un dépôt Hugging Face libre
//  - Choix CPU / GPU, temps de réponse affiché
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';

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

// Fournisseurs d'IA en ligne : l'utilisateur colle sa propre clé API.
class Provider {
  const Provider(this.id, this.name, this.defaultModel, this.keyHint);
  final String id;
  final String name;
  final String defaultModel;
  final String keyHint;
}

const providers = <Provider>[
  Provider('deepseek', 'DeepSeek', 'deepseek-chat', 'sk-…'),
  Provider('claude', 'Claude (Anthropic)', 'claude-sonnet-5-5', 'sk-ant-…'),
  Provider('gemini', 'Gemini (Google)', 'gemini-2.5-flash', 'AIza…'),
  Provider('openai', 'OpenAI (ChatGPT)', 'gpt-4o-mini', 'sk-…'),
];

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
    this.scenario = '',
    this.physical = '',
    this.rp = true,
    List<Msg>? messages,
  }) : messages = messages ?? [];

  final String id;
  String name;
  int age;
  String description; // description morale (caractère)
  int color;
  String script; // réponses préenregistrées (texte du .txt importé)
  String physical; // description physique
  String scenario; // décor / situation de la partie de jeu de rôle
  bool rp; // true = mode jeu de rôle (narration), false = simple chat
  final List<Msg> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'description': description,
        'color': color,
        'script': script,
        'physical': physical,
        'scenario': scenario,
        'rp': rp,
        'messages': [for (final m in messages) m.toJson()],
      };

  static Contact fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] as String,
        name: j['name'] as String,
        age: ((j['age'] as num?)?.toInt() ?? 18).clamp(10, 50),
        description: j['description'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF128C7E,
        script: j['script'] as String? ?? '',
        physical: j['physical'] as String? ?? '',
        scenario: j['scenario'] as String? ?? '',
        rp: j['rp'] as bool? ?? true,
        messages: [
          for (final m in (j['messages'] as List? ?? const []))
            Msg.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
      );
}

class Msg {
  Msg(this.text, {required this.fromMe, DateTime? time, this.seconds})
      : time = time ?? DateTime.now();
  final String text;
  final bool fromMe;
  final DateTime time;
  final double? seconds;

  Map<String, dynamic> toJson() => {
        't': text,
        'me': fromMe,
        'ts': time.millisecondsSinceEpoch,
        if (seconds != null) 's': seconds,
      };

  static Msg fromJson(Map<String, dynamic> j) => Msg(
        j['t'] as String? ?? '',
        fromMe: j['me'] as bool? ?? false,
        time: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num?)?.toInt() ?? 0),
        seconds: (j['s'] as num?)?.toDouble(),
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
//  Cerveau : stockage + modèle + conversations
// ---------------------------------------------------------------
class Brain extends ChangeNotifier {
  final List<Contact> contacts = [];

  // Réglages
  String modelId = baseModels.first.id;
  LiteLmBackend backend = LiteLmBackend.cpu;
  String customRepo = '';
  // IA en ligne : 'local' ou l'id d'un fournisseur. Les clés restent sur le
  // téléphone (jamais dans le code).
  String provider = 'deepseek';
  final Map<String, String> apiKeys = {};
  final Map<String, String> apiModels = {}; // modèle choisi par fournisseur

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
  Provider? get activeProvider {
    for (final p in providers) {
      if (p.id == provider) return p;
    }
    return null;
  }

  String keyOf(String id) => (apiKeys[id] ?? '').trim();
  String modelOf(Provider p) {
    final m = (apiModels[p.id] ?? '').trim();
    return m.isEmpty ? p.defaultModel : m;
  }

  bool get onlineOk {
    final p = activeProvider;
    return p != null && keyOf(p.id).isNotEmpty;
  }

  // ----- Stockage -----
  File get _dataFile => File('${_dir.path}/app_data.json');
  File modelFile(String id) => File('${_dir.path}/$id.litertlm');

  Future<void> init() async {
    _dir = await getApplicationSupportDirectory();
    try {
      if (await _dataFile.exists()) {
        final j = jsonDecode(await _dataFile.readAsString()) as Map;
        modelId = j['modelId'] as String? ?? modelId;
        customRepo = j['customRepo'] as String? ?? '';
        provider = j['provider'] as String? ??
            ((j['online'] as bool? ?? true) ? 'deepseek' : 'local');
        final k = j['apiKeys'];
        if (k is Map) {
          k.forEach((a, b) => apiKeys['$a'] = '$b');
        }
        final m = j['apiModels'];
        if (m is Map) {
          m.forEach((a, b) => apiModels['$a'] = '$b');
        }
        final legacy = j['deepseekKey'] as String? ?? '';
        if (legacy.isNotEmpty) apiKeys.putIfAbsent('deepseek', () => legacy);
        backend = (j['gpu'] as bool? ?? false)
            ? LiteLmBackend.gpu
            : LiteLmBackend.cpu;
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
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    try {
      await _dataFile.writeAsString(jsonEncode({
        'modelId': modelId,
        'customRepo': customRepo,
        'provider': provider,
        'apiKeys': apiKeys,
        'apiModels': apiModels,
        'gpu': backend == LiteLmBackend.gpu,
        'contacts': [for (final c in contacts) c.toJson()],
      }));
    } catch (_) {}
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

  void deleteContact(Contact c) {
    contacts.remove(c);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  void clearChat(Contact c) {
    c.messages.clear();
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

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

  void setProvider(String id) {
    provider = id;
    _scheduleSave();
    notifyListeners();
  }

  void setApiKey(String id, String v) {
    apiKeys[id] = v.trim();
    _scheduleSave();
    notifyListeners();
  }

  void setApiModel(String id, String v) {
    apiModels[id] = v.trim();
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
  String systemPrompt(Contact c, {bool withHistory = true}) {
    final desc = c.description.trim();
  final buf = StringBuffer();
  if (c.rp) {
    buf
      ..writeln('Tu animes une partie de jeu de rôle en français avec le '
          'joueur. Tu incarnes ${c.name}, ${c.age} ans.')
      ..writeln('Description physique : '
          '${c.physical.trim().isEmpty ? 'non précisée' : c.physical.trim()}.')
      ..writeln('Caractère et morale : ${desc.isEmpty ? 'à imaginer' : desc}.')
      ..writeln('Décor / situation : '
          '${c.scenario.trim().isEmpty ? 'libre, à toi de poser le décor' : c.scenario.trim()}.')
      ..writeln('Règles : tu parles à la première personne pour ${c.name} '
          'et tu décris les actions entre *astérisques*. Tu fais avancer '
          'l\'histoire avec des rebondissements, tu ne joues jamais le '
          'joueur à sa place et tu termines par une question ou un choix '
          'qui lui laisse la main. 2 à 5 phrases par message. Tu restes '
          'dans l\'univers et tu gardes l\'histoire adaptée à tous.');
  } else {
    buf
    ..writeln('Tu es ${c.name}, ${c.age} ans. Tu discutes par messagerie '
        '(style WhatsApp) avec ton ami(e).')
    ..writeln('Ton physique : '
        '${c.physical.trim().isEmpty ? 'non précisé' : c.physical.trim()}.')
    ..writeln('Ton caractère : ${desc.isEmpty ? 'sympa et naturel' : desc}.')
    ..writeln('Tu écris en français, de façon naturelle et spontanée. '
        'Messages courts (1 à 3 phrases), parfois un emoji. '
        'Pas de narration, pas d\'astérisques, pas de didascalies.')
    ..writeln('Tu restes toujours dans ton personnage et tu relances '
        'de temps en temps la conversation avec une question.');
  }
  // Mémoire : on rejoue les derniers messages dans le contexte.
  final hist = c.messages.length > 14
      ? c.messages.sublist(c.messages.length - 14)
      : c.messages;
  if (withHistory && hist.isNotEmpty) {
    buf.writeln('\nDébut de votre conversation (pour mémoire) :');
    for (final m in hist) {
      buf.writeln('${m.fromMe ? (c.rp ? 'Joueur' : 'Ami(e)') : c.name} : ${m.text}');
    }
    buf.writeln('Continue naturellement à partir de là.');
  }
  return buf.toString();
  }
  
  Future<LiteLmConversation> _convFor(Contact c) async {
    final existing = _convs[c.id];
    if (existing != null) return existing;
    final conv = await _engine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: systemPrompt(c),
        samplerConfig: const LiteLmSamplerConfig(
          temperature: 0.8,
          topK: 40,
          topP: 0.95,
        ),
      ),
    );
    _convs[c.id] = conv;
    return conv;
  }

  String _clean(String s) {
    var out = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final i = out.indexOf('<think>');
    if (i >= 0) out = out.substring(0, i);
    return out.trim();
  }

  // ----- IA en ligne (DeepSeek, Claude, Gemini, OpenAI) -----
  // Historique au format user/assistant : il doit commencer par « user » et
  // alterner (exigé par Claude et Gemini), donc on fusionne les messages
  // consécutifs du même rôle.
  List<Map<String, String>> _history(Contact c) {
    final src = c.messages.length > 30
        ? c.messages.sublist(c.messages.length - 30)
        : c.messages;
    final out = <Map<String, String>>[];
    for (final m in src) {
      final role = m.fromMe ? 'user' : 'assistant';
      if (out.isNotEmpty && out.last['role'] == role) {
        out.last['content'] = '${out.last['content']}\n${m.text}';
      } else {
        out.add({'role': role, 'content': m.text});
      }
    }
    if (out.isEmpty || out.first['role'] != 'user') {
      out.insert(0, {'role': 'user', 'content': '(début de la partie)'});
    }
    return out;
  }

  Future<String> _askOnline(Contact c) async {
    final p = activeProvider!;
    final key = keyOf(p.id);
    final model = modelOf(p);
    final system = systemPrompt(c, withHistory: false);
    final hist = _history(c);
    final temp = c.rp ? 1.0 : 0.9;

    late final Uri url;
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };
    late final Map<String, dynamic> body;
    switch (p.id) {
      case 'claude':
        url = Uri.parse('https://api.anthropic.com/v1/messages');
        headers['x-api-key'] = key;
        headers['anthropic-version'] = '2023-06-01';
        body = {
          'model': model,
          'max_tokens': 1024,
          'temperature': temp.clamp(0, 1),
          'system': system,
          'messages': hist,
        };
      case 'gemini':
        url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/'
            'models/$model:generateContent');
        headers['x-goog-api-key'] = key;
        body = {
          'systemInstruction': {
            'parts': [
              {'text': system}
            ]
          },
          'contents': [
            for (final m in hist)
              {
                'role': m['role'] == 'user' ? 'user' : 'model',
                'parts': [
                  {'text': m['content']}
                ],
              },
          ],
          'generationConfig': {'temperature': temp},
        };
      default: // deepseek, openai : API compatible OpenAI
        url = Uri.parse(p.id == 'openai'
            ? 'https://api.openai.com/v1/chat/completions'
            : 'https://api.deepseek.com/chat/completions');
        headers[HttpHeaders.authorizationHeader] = 'Bearer $key';
        body = {
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            ...hist,
          ],
          'temperature': temp,
        };
    }

    final client = HttpClient();
    try {
      final req = await client.postUrl(url);
      headers.forEach(req.headers.set);
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final txt = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw Exception('${p.name} ${res.statusCode} : $txt');
      }
      final j = jsonDecode(txt) as Map;
      switch (p.id) {
        case 'claude':
          return [
            for (final part in j['content'] as List)
              if ((part as Map)['type'] == 'text') part['text'],
          ].join();
        case 'gemini':
          final parts = (((j['candidates'] as List).first as Map)['content']
              as Map)['parts'] as List;
          return [for (final part in parts) (part as Map)['text'] ?? ''].join();
        default:
          return (((j['choices'] as List).first as Map)['message']
              as Map)['content'] as String;
      }
    } finally {
      client.close();
    }
  }

  Future<void> send(Contact c, String text) async {
    final book = _bookFor(c);
    if (!canReply(c) || generating.contains(c.id)) return;
    c.messages.add(Msg(text, fromMe: true));
    generating.add(c.id);
    notifyListeners();
    _scheduleSave();

    final sw = Stopwatch()..start();
    try {
      if (book != null) {
        // Réponse préenregistrée : pas besoin du modèle IA.
        await Future<void>.delayed(
            Duration(milliseconds: 600 + Random().nextInt(900)));
        final r = book.reply(text);
        c.messages.add(Msg(
            r ?? 'Aucune réponse préenregistrée ne correspond à ce message.',
            fromMe: false));
        return;
      }
      if (onlineOk) {
        _addReply(c, await _askOnline(c), sw);
        return;
      }
      // La conversation est créée avant l'envoi : l'historique du prompt
      // ne doit pas contenir le message en cours.
      if (!_convs.containsKey(c.id)) {
        final last = c.messages.removeLast();
        final conv = await _convFor(c);
        c.messages.add(last);
        final reply = await conv.sendMessage(text);
        _addReply(c, reply.text, sw);
      } else {
        final reply = await _convs[c.id]!.sendMessage(text);
        _addReply(c, reply.text, sw);
      }
    } catch (e) {
      c.messages.add(Msg('⚠️ Erreur : $e', fromMe: false));
    } finally {
      generating.remove(c.id);
      notifyListeners();
      _scheduleSave();
    }
  }

  // ----- Réponses préenregistrées -----
  ScriptBook? _bookFor(Contact c) {
    if (c.script.trim().isEmpty) return null;
    final b = ScriptBook.parse(c.script);
    return b.isEmpty ? null : b;
  }

  bool canReply(Contact c) => onlineOk || ready || _bookFor(c) != null;

  // ----- Confort de chat -----
  Future<void> regenerate(Contact c) async {
    if (generating.contains(c.id) || !canReply(c)) return;
    while (c.messages.isNotEmpty && !c.messages.last.fromMe) {
      c.messages.removeLast();
    }
    if (c.messages.isEmpty) return;
    final last = c.messages.removeLast();
    _dropConv(c.id);
    await send(c, last.text);
  }

  void deleteMessage(Contact c, Msg m) {
    if (generating.contains(c.id)) return;
    c.messages.remove(m);
    _dropConv(c.id);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> editAndResend(Contact c, Msg m, String text) async {
    if (generating.contains(c.id) || !canReply(c)) return;
    final i = c.messages.indexOf(m);
    if (i < 0) return;
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
          '${m.fromMe ? 'Moi' : c.name} : ${m.text}');
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

  void _addReply(Contact c, String? raw, Stopwatch sw) {
    final clean = _clean(raw ?? '');
    c.messages.add(Msg(
      clean.isEmpty ? '…' : clean,
      fromMe: false,
      seconds: sw.elapsedMilliseconds / 1000,
    ));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unload();
    super.dispose();
  }
}

// ---------------------------------------------------------------
//  Démarrage
// ---------------------------------------------------------------
// ---------------------------------------------------------------
//  Central JDR : bibliothèque de scénarios
// ---------------------------------------------------------------
class Scenario {
  const Scenario({
    required this.title,
    required this.emoji,
    required this.pitch,
    required this.character,
    required this.age,
    required this.physical,
    required this.persona,
    required this.setting,
    required this.opening,
    required this.color,
  });
  final String title;
  final String emoji;
  final String pitch; // accroche affichée sur la carte
  final String character; // nom du personnage joué par l'IA
  final int age;
  final String physical;
  final String persona;
  final String setting;
  final String opening; // premier message de la partie
  final int color;
}

const scenarios = <Scenario>[
  Scenario(
    title: 'La taverne du Dragon Rouge',
    emoji: '🐉',
    pitch: 'Fantasy · une rumeur de trésor circule…',
    character: 'Maître Brann',
    physical: 'grand et large d'épaules, barbe grise, cicatrice à la joue, tablier de cuir',
    age: 45,
    persona: 'tavernier bourru au grand cœur, ancien aventurier, '
        'connaît tous les secrets de la région',
    setting: 'une taverne de village fantasy, un soir d\'orage ; '
        'un étranger blessé vient de s\'écrouler près de la cheminée',
    opening: '*Brann essuie une chope et te fait signe d\'approcher.* '
        'Tu tombes bien, voyageur. Un blessé vient d\'arriver avec une carte '
        'dans la main… Tu t\'en mêles ?',
    color: 0xFFD81B60,
  ),
  Scenario(
    title: 'Station Orion-7',
    emoji: '🚀',
    pitch: 'Science-fiction · le vaisseau répond bizarrement',
    character: 'ARIA',
    physical: 'voix féminine ; apparaît en silhouette lumineuse bleutée',
    age: 30,
    persona: 'IA de bord calme, curieuse, qui cache quelque chose',
    setting: 'une station spatiale en orbite ; l\'équipage a disparu, '
        'seul le joueur est réveillé',
    opening: '*Les lumières clignotent. Une voix douce s\'élève.* '
        'Bonjour… Je suis ARIA. Je dois vous prévenir : vous êtes le seul '
        'à bord. Que voulez-vous faire en premier ?',
    color: 0xFF1E88E5,
  ),
  Scenario(
    title: 'Enquête au manoir',
    emoji: '🕵️',
    pitch: 'Policier · qui a volé le collier ?',
    character: 'Inspecteur Vidal',
    physical: 'mince, cheveux argentés, long manteau beige, monocle',
    age: 50,
    persona: 'enquêteur fin et ironique, adore les indices tordus',
    setting: 'un manoir isolé pendant une soirée de gala ; un collier de '
        'famille a disparu, six suspects sont encore dans le salon',
    opening: '*Vidal range son carnet.* Vous tombez à pic, je cherche un '
        'assistant. Six suspects, un collier volé, aucune porte forcée. '
        'Par qui commence-t-on ?',
    color: 0xFF5E35B1,
  ),
  Scenario(
    title: 'Après la fin du monde',
    emoji: '🏚️',
    pitch: 'Post-apo · survivre, trouver de l\'eau',
    character: 'Mira',
    physical: 'cheveux courts sombres, veste rapiécée, regard perçant',
    age: 28,
    persona: 'survivante débrouillarde, méfiante mais loyale',
    setting: 'un monde en ruines, ville abandonnée ; les réserves d\'eau '
        'sont presque vides et un convoi inconnu approche',
    opening: '*Mira te tire dans l\'ombre d\'un mur effondré.* Chut. '
        'Un convoi arrive du nord. On les suit ou on se cache ?',
    color: 0xFFEF6C00,
  ),
  Scenario(
    title: 'Académie des Mages',
    emoji: '🧙',
    pitch: 'Magie · premier jour d\'école',
    character: 'Professeure Elwen',
    physical: 'petite, cheveux lilas en désordre, robe étoilée, lunettes rondes',
    age: 40,
    persona: 'enseignante excentrique et bienveillante, un peu distraite',
    setting: 'une académie de magie flottante ; le joueur est nouvel élève '
        'et son premier sortilège tourne mal',
    opening: '*Un nuage de paillettes se dissipe dans la salle.* Eh bien… '
        'ce n\'était pas censé être un dragon. Respire, nouveau ! '
        'Comment t\'appelles-tu ?',
    color: 0xFF43A047,
  ),
  Scenario(
    title: 'Pirates des Sept Mers',
    emoji: '🏴‍☠️',
    pitch: 'Aventure · une carte, un équipage, une tempête',
    character: 'Capitaine Rosalind',
    physical: 'peau hâlée, tresses ornées de perles, long manteau rouge, chapeau à plume',
    age: 35,
    persona: 'capitaine charismatique, rusée, aime les paris fous',
    setting: 'un galion pirate en pleine mer ; le joueur vient de rejoindre '
        'l\'équipage et une île inconnue apparaît à l\'horizon',
    opening: '*Rosalind pointe l\'horizon avec sa longue-vue.* '
        'Terre ! Et elle n\'est sur aucune carte. Matelot, '
        'tu prends la vigie ou tu descends la chaloupe ?',
    color: 0xFF546E7A,
  ),
];

class HubPage extends StatelessWidget {
  const HubPage({super.key, required this.brain, required this.onStarted});
  final Brain brain;
  final VoidCallback onStarted;

  Future<void> _start(BuildContext context, Scenario sc) async {
    final c = Contact(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: sc.character,
      age: sc.age,
      description: sc.persona,
      physical: sc.physical,
      color: sc.color,
      scenario: sc.setting,
      rp: true,
    )..messages.add(Msg(sc.opening, fromMe: false));
    brain.addOrUpdate(c);
    onStarted();
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ChatPage(brain: brain, contact: c)));
  }

  Future<void> _custom(BuildContext context) async {
    final c = Contact(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '',
      age: 25,
      description: '',
      color: _palette[brain.contacts.length % _palette.length],
      rp: true,
    );
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ContactEditPage(brain: brain, contact: c)));
    onStarted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Central JDR',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text('Choisis un scénario pour lancer une nouvelle partie. '
                'L\'IA incarne le personnage et mène l\'histoire.'),
          ),
          for (final sc in scenarios)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(sc.color),
                  child: Text(sc.emoji, style: const TextStyle(fontSize: 22)),
                ),
                title: Text(sc.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${sc.pitch}\nAvec ${sc.character}'),
                isThreeLine: true,
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _start(context, sc),
              ),
            ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.auto_awesome)),
              title: const Text('Créer mon propre scénario',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Personnage, décor et ambiance libres'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _custom(context),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.brain});
  final Brain brain;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        ChatsPage(brain: widget.brain),
        HubPage(brain: widget.brain, onStarted: () => setState(() => _tab = 0)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Parties'),
          NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined), label: 'Scénarios'),
        ],
      ),
    );
  }
}

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
    return HomeShell(brain: brain);
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
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: Color(c.color),
        child: Text(
          c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
          style: TextStyle(
              color: Colors.white,
              fontSize: radius * 0.9,
              fontWeight: FontWeight.bold),
        ),
      );
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
            ],
          ),
          body: Column(
            children: [
              if (!brain.ready && !brain.onlineOk)
                Material(
                  color: Colors.amber.shade100,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber),
                    title: const Text('Aucune IA configurée'),
                    subtitle: const Text('Touche pour ajouter ta clé API'),
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
                              content: const Text(
                                  'Le contact et sa discussion seront effacés.'),
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
                      title: Text(c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        typing
                            ? 'en train d\'écrire…'
                            : (last == null
                                ? 'Dis bonjour 👋'
                                : '${last.fromMe ? 'Toi : ' : ''}${last.text}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: typing ? _waLight : null,
                            fontStyle:
                                typing ? FontStyle.italic : FontStyle.normal),
                      ),
                      trailing: last == null
                          ? null
                          : Text(_dayLabel(last.time),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).hintColor)),
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

  void _contactMenu(BuildContext context, Contact c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Modifier le contact'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ContactEditPage(brain: brain, contact: c)));
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
            title: const Text('Supprimer le contact'),
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
  late final TextEditingController _physical;
  late final TextEditingController _scenario;
  late double _age;
  late int _color;
  late bool _rp;
  String _script = '';

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _script = c?.script ?? '';
    _rp = c?.rp ?? true;
    _scenario = TextEditingController(text: c?.scenario ?? '');
    _name = TextEditingController(text: c?.name ?? '');
    _desc = TextEditingController(text: c?.description ?? '');
    _physical = TextEditingController(text: c?.physical ?? '');
    _age = (c?.age ?? 18).clamp(10, 50).toDouble();
    _color = c?.color ?? _palette[widget.brain.contacts.length % _palette.length];
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _physical.dispose();
    _scenario.dispose();
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
      ..physical = _physical.text.trim()
      ..scenario = _scenario.text.trim()
      ..rp = _rp
      ..color = _color
      ..script = _script;
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
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Color(_color),
              child: Text(
                _name.text.trim().isEmpty
                    ? '?'
                    : _name.text.trim().characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 36, color: Colors.white),
              ),
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
            max: 50,
            divisions: 40,
            value: _age,
            label: '${_age.round()}',
            onChanged: (v) => setState(() => _age = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _physical,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Description physique',
              hintText: 'ex : cheveux roux bouclés, 1m75, yeux verts, '
                  'toujours en hoodie…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Description morale (caractère)',
              hintText: 'ex : protecteur, calme, drôle, rancunier, '
                  'fan de foot…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mode jeu de rôle'),
            subtitle: const Text('L\'IA narre, décrit les actions et mène '
                'l\'histoire'),
            value: _rp,
            onChanged: (v) => setState(() => _rp = v),
          ),
          if (_rp)
            TextField(
              controller: _scenario,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Décor / situation',
                hintText: 'ex : une station spatiale abandonnée, '
                    'le joueur vient de se réveiller…',
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

  Brain get brain => widget.brain;
  Contact get c => widget.contact;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
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
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(children: [
              Avatar(c, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 17)),
                    Text(typing ? 'en train d\'écrire…' : 'en ligne',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.normal)),
                  ],
                ),
              ),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                ContactEditPage(brain: brain, contact: c)));
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
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifier le contact')),
                  PopupMenuItem(value: 'models', child: Text('Modèles IA')),
                  PopupMenuItem(value: 'export', child: Text('Exporter (copier)')),
                  PopupMenuItem(value: 'clear', child: Text('Vider la discussion')),
                ],
              ),
            ],
          ),
          body: Container(
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
                        CircleAvatar(
                          backgroundColor: _waGreen,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: typing ? null : _send,
                          ),
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
          child: const SizedBox(
              width: 24,
              height: 14,
              child: LinearProgressIndicator(minHeight: 3)),
        ),
      );

  Widget _bubble(Msg m) {
    return Align(
      alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _msgMenu(m),
        child: Container(
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
  late final TextEditingController _key;
  late final TextEditingController _apiModel;

  Brain get b => widget.brain;

  @override
  void initState() {
    super.initState();
    _repo = TextEditingController(text: b.customRepo);
    _key = TextEditingController();
    _apiModel = TextEditingController();
    _syncFields();
  }

  void _syncFields() {
    _key.text = b.keyOf(b.provider);
    _apiModel.text = b.apiModels[b.provider] ?? '';
  }

  @override
  void dispose() {
    _repo.dispose();
    _key.dispose();
    _apiModel.dispose();
    super.dispose();
  }

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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('IA en ligne (ta clé API)',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: b.provider,
                        decoration: const InputDecoration(
                            labelText: 'Fournisseur',
                            border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(
                              value: 'local',
                              child: Text('Modèle local (hors ligne)')),
                          for (final p in providers)
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          b.setProvider(v);
                          _syncFields();
                        },
                      ),
                      if (b.activeProvider != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: ValueKey('key-${b.provider}'),
                          controller: _key,
                          obscureText: true,
                          onChanged: (v) => b.setApiKey(b.provider, v),
                          decoration: InputDecoration(
                            labelText: 'Clé API ${b.activeProvider!.name}',
                            hintText: b.activeProvider!.keyHint,
                            helperText: 'Stockée uniquement sur ce téléphone',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: ValueKey('model-${b.provider}'),
                          controller: _apiModel,
                          onChanged: (v) => b.setApiModel(b.provider, v),
                          decoration: InputDecoration(
                            labelText: 'Modèle',
                            hintText: b.activeProvider!.defaultModel,
                            helperText: 'Laisse vide pour le modèle par défaut',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Modèle local',
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
              const Text(
                'Les modèles tournent 100 % sur ton téléphone. '
                'Un modèle non censuré n\'applique aucun filtre : '
                'les personnages restent des adultes (18 ans et +).',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
