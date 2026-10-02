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

import 'package:flutter/material.dart';
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
    List<Msg>? messages,
  }) : messages = messages ?? [];

  final String id;
  String name;
  int age;
  String description;
  int color;
  final List<Msg> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'description': description,
        'color': color,
        'messages': [for (final m in messages) m.toJson()],
      };

  static Contact fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] as String,
        name: j['name'] as String,
        age: (j['age'] as num?)?.toInt() ?? 18,
        description: j['description'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF128C7E,
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
        age: 18,
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
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : m.sizeBytes;
      sink = part.openWrite();
      var received = 0;
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
        if (await part.exists()) await part.delete();
      } catch (_) {}
      status = 'Erreur de téléchargement : $e';
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
  String systemPrompt(Contact c) {
    final desc = c.description.trim();
    final buf = StringBuffer()
      ..writeln('Tu es ${c.name}, ${c.age} ans. Tu discutes par messagerie '
          '(style WhatsApp) avec ton ami(e).')
      ..writeln('Ton personnage : ${desc.isEmpty ? 'sympa et naturel' : desc}.')
      ..writeln('Tu écris en français, de façon naturelle et spontanée. '
          'Messages courts (1 à 3 phrases), parfois un emoji. '
          'Pas de narration, pas d\'astérisques, pas de didascalies.')
      ..writeln('Tu restes toujours dans ton personnage et tu relances '
          'de temps en temps la conversation avec une question.');
    // Mémoire : on rejoue les derniers messages dans le contexte.
    final hist = c.messages.length > 14
        ? c.messages.sublist(c.messages.length - 14)
        : c.messages;
    if (hist.isNotEmpty) {
      buf.writeln('\nDébut de votre conversation (pour mémoire) :');
      for (final m in hist) {
        buf.writeln('${m.fromMe ? 'Ami(e)' : c.name} : ${m.text}');
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

  Future<void> send(Contact c, String text) async {
    if (!ready || generating.contains(c.id)) return;
    c.messages.add(Msg(text, fromMe: true));
    generating.add(c.id);
    notifyListeners();
    _scheduleSave();

    final sw = Stopwatch()..start();
    try {
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

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, required this.brain});
  final Brain brain;

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
        return Scaffold(
          appBar: AppBar(
            title: const Text('IA Messenger',
                style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
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
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final last = c.messages.isEmpty ? null : c.messages.last;
                    final typing = brain.generating.contains(c.id);
                    return ListTile(
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
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ChatPage(brain: brain, contact: c))),
                      onLongPress: () => _contactMenu(context, c),
                    );
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
  late double _age;
  late int _color;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _name = TextEditingController(text: c?.name ?? '');
    _desc = TextEditingController(text: c?.description ?? '');
    _age = (c?.age ?? 12).clamp(10, 60).toDouble();
    _color = c?.color ?? _palette[widget.brain.contacts.length % _palette.length];
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
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
      ..color = _color;
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
          Text('Âge : ${_age.round()} ans (personnages adultes uniquement)'),
          Slider(
            min: 18,
            max: 60,
            divisions: 42,
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
    if (!brain.ready) {
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
                  PopupMenuItem(value: 'clear', child: Text('Vider la discussion')),
                ],
              ),
            ],
          ),
          body: Container(
            color: _chatBg,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: count,
                    itemBuilder: (context, i) {
                      if (i == c.messages.length) return _typingBubble();
                      return _bubble(c.messages[i]);
                    },
                  ),
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
                              fillColor: Colors.white,
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

  Widget _typingBubble() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.text));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Message copié'),
              duration: Duration(seconds: 1)));
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: m.fromMe ? _bubbleMe : Colors.white,
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
                  child: Text(m.text, style: const TextStyle(fontSize: 15.5))),
              const SizedBox(height: 2),
              Text(
                m.seconds != null
                    ? '${_hhmm(m.time)} · ⏱ ${m.seconds!.toStringAsFixed(1)} s'
                    : _hhmm(m.time),
                style: const TextStyle(fontSize: 10.5, color: Colors.black45),
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

  Brain get b => widget.brain;

  @override
  void initState() {
    super.initState();
    _repo = TextEditingController(text: b.customRepo);
  }

  @override
  void dispose() {
    _repo.dispose();
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
