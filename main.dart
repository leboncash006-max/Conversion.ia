// ============================================================
//  TEST IA LOCALE  —  interface volontairement moche
//  Objectif : vérifier que le modèle se télécharge, se charge
//  et répond sur le téléphone, avec un perso défini par l'utilisateur.
//
//  Installation :
//    flutter create ia_test --platforms=android
//    cd ia_test
//    flutter pub add flutter_litert_lm path_provider
//    (remplacer lib/main.dart par ce fichier)
//    android/app/build.gradle(.kts) : minSdk = 24
//    AndroidManifest.xml : ajouter avant <application ...> :
//      <uses-permission android:name="android.permission.INTERNET"/>
//    flutter run --release
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const TestApp());

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Test IA locale',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
        home: const HomePage(),
      );
}

// ---------------------------------------------------------------
//  Modèles disponibles (publics, sans token Hugging Face)
// ---------------------------------------------------------------
class ModelOption {
  const ModelOption(this.id, this.name, this.url, this.sizeBytes);
  final String id;
  final String name;
  final String url;
  final int sizeBytes;
}

const modelOptions = <ModelOption>[
  ModelOption(
    'qwen25-1.5b',
    'Qwen 2.5 1.5B (1,6 Go) - recommandé',
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    1604270080,
  ),
  ModelOption(
    'qwen3-0.6b',
    'Qwen 3 0.6B (0,6 Go) - léger',
    'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    614235648,
  ),
];

class ChatMessage {
  ChatMessage(this.text, {required this.fromMe, this.seconds});
  final String text;
  final bool fromMe;
  final double? seconds;
}

enum AppStep { setup, persona, chat }

// ---------------------------------------------------------------
//  Page unique (3 écrans gérés par _step)
// ---------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppStep _step = AppStep.setup;

  // Écran 1 : modèle
  ModelOption _model = modelOptions.first;
  LiteLmBackend _backend = LiteLmBackend.cpu;
  bool _downloaded = false;
  double? _progress; // null = pas de téléchargement en cours
  bool _loading = false;
  String _status = '';

  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;

  // Écran 2 : personnage
  final _nameCtrl = TextEditingController(text: 'Léo');
  final _descCtrl = TextEditingController(
    text: 'pote de classe, un peu sarcastique mais sympa, '
        'passionné de jeux vidéo et de voitures',
  );
  double _age = 15;

  // Écran 3 : chat
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  @override
  void dispose() {
    _conversation?.dispose();
    _engine?.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------- Modèle -------------------------
  Future<File> _fileFor(ModelOption m) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${m.id}.litertlm');
  }

  Future<void> _checkDownloaded() async {
    final f = await _fileFor(_model);
    final ok = await f.exists();
    if (mounted) setState(() => _downloaded = ok);
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _status = '';
    });
    final file = await _fileFor(_model);
    final part = File('${file.path}.part');
    final client = HttpClient();
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(_model.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : _model.sizeBytes;
      sink = part.openWrite();
      var received = 0;
      var lastPct = -1;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        final pct = received * 100 ~/ total;
        if (pct != lastPct) {
          lastPct = pct;
          if (mounted) setState(() => _progress = received / total);
        }
      }
      await sink.close();
      sink = null;
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      if (mounted) {
        setState(() {
          _progress = null;
          _downloaded = true;
          _status = 'Téléchargement terminé';
        });
      }
    } catch (e) {
      try {
        await sink?.close();
        if (await part.exists()) await part.delete();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _progress = null;
          _status = 'Erreur de téléchargement : $e';
        });
      }
    } finally {
      client.close();
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _loading = true;
      _status = 'Chargement du modèle…';
    });
    try {
      await _conversation?.dispose();
      _conversation = null;
      await _engine?.dispose();
      _engine = null;

      final f = await _fileFor(_model);
      final sw = Stopwatch()..start();
      _engine = await LiteLmEngine.create(
        LiteLmEngineConfig(modelPath: f.path, backend: _backend),
      );
      sw.stop();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status =
            'Modèle chargé en ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
        _step = AppStep.persona;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Erreur de chargement : $e';
      });
    }
  }

  // ------------------------- Personnage -------------------------
  String _buildSystemPrompt() {
    final name = _nameCtrl.text.trim().isEmpty ? 'Léo' : _nameCtrl.text.trim();
    final age = _age.round();
    final desc = _descCtrl.text.trim();
    final buf = StringBuffer()
      ..writeln('Tu es $name, $age ans. Tu discutes par messagerie '
          '(style WhatsApp) avec ton ami(e).')
      ..writeln('Ton personnage : $desc.')
      ..writeln('Style : tu écris en français, comme un(e) jeune de $age ans '
          '(vocabulaire, expressions, centres d\'intérêt de cet âge). '
          'Messages courts (1 à 3 phrases), naturels, parfois un emoji. '
          'Pas de narration, pas d\'astérisques, pas de didascalies.')
      ..writeln('Tu es chaleureux(se), drôle et bienveillant(e), '
          'avec une vraie amitié mais sans en faire trop.')
      ..writeln('Tu restes toujours dans ton personnage et tu relances '
          'de temps en temps la conversation avec une question.');
    if (age < 18) {
      buf.writeln('Vous parlez de la vie de tous les jours : l\'école, '
          'les jeux vidéo, les passions, les blagues.');
    }
    return buf.toString();
  }

  Future<void> _startChat() async {
    setState(() => _loading = true);
    try {
      await _conversation?.dispose();
      _conversation = await _engine!.createConversation(
        LiteLmConversationConfig(
          systemInstruction: _buildSystemPrompt(),
          samplerConfig: const LiteLmSamplerConfig(
            temperature: 0.8,
            topK: 40,
            topP: 0.95,
          ),
        ),
      );
      _messages.clear();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = AppStep.chat;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Erreur : $e';
      });
    }
  }

  // ------------------------- Chat -------------------------
  String _clean(String s) {
    // Qwen 3 peut renvoyer un bloc <think>…</think> : on le retire.
    var out = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final i = out.indexOf('<think>');
    if (i >= 0) out = out.substring(0, i);
    return out.trim();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _generating || _conversation == null) return;
    _msgCtrl.clear();
    setState(() {
      _messages.add(ChatMessage(text, fromMe: true));
      _generating = true;
    });
    _scrollToEnd();

    final sw = Stopwatch()..start();
    try {
      final reply = await _conversation!.sendMessage(text);
      final String? raw = reply.text;
      final clean = _clean(raw ?? '');
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          clean.isEmpty ? '…' : clean,
          fromMe: false,
          seconds: sw.elapsedMilliseconds / 1000,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('Erreur : $e', fromMe: false)));
    } finally {
      if (mounted) setState(() => _generating = false);
      _scrollToEnd();
    }
  }

  // ------------------------- UI -------------------------
  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      AppStep.setup => 'Test IA locale',
      AppStep.persona => 'Définir le personnage',
      AppStep.chat =>
        '${_nameCtrl.text.trim().isEmpty ? 'Léo' : _nameCtrl.text.trim()} (${_age.round()} ans)',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _step == AppStep.setup
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _step = _step == AppStep.chat
                        ? AppStep.persona
                        : AppStep.setup;
                  });
                },
              ),
      ),
      body: SafeArea(
        child: switch (_step) {
          AppStep.setup => _buildSetup(),
          AppStep.persona => _buildPersona(),
          AppStep.chat => _buildChat(),
        },
      ),
    );
  }

  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('1. Modèle IA',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        DropdownButton<ModelOption>(
          isExpanded: true,
          value: _model,
          items: [
            for (final m in modelOptions)
              DropdownMenuItem(value: m, child: Text(m.name)),
          ],
          onChanged: (_progress != null || _loading)
              ? null
              : (m) {
                  if (m == null) return;
                  setState(() => _model = m);
                  _checkDownloaded();
                },
        ),
        Text(_downloaded ? '✅ Modèle téléchargé' : '⬇️ Pas encore téléchargé'),
        if (_progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
          Text('${((_progress ?? 0) * 100).toStringAsFixed(0)} %  '
              '(garde l\'écran allumé, en Wi-Fi)'),
        ],
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: (_downloaded || _progress != null) ? null : _download,
          child: const Text('Télécharger'),
        ),
        const SizedBox(height: 24),
        const Text('2. Processeur',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<LiteLmBackend>(
          segments: const [
            ButtonSegment(value: LiteLmBackend.cpu, label: Text('CPU (sûr)')),
            ButtonSegment(
                value: LiteLmBackend.gpu, label: Text('GPU (rapide ?)')),
          ],
          selected: {_backend},
          onSelectionChanged: (s) => setState(() => _backend = s.first),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: (_downloaded && !_loading && _progress == null)
              ? _loadModel
              : null,
          child: Text(_loading ? 'Chargement…' : '3. Charger le modèle'),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_status),
        ],
      ],
    );
  }

  Widget _buildPersona() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Prénom du perso'),
        ),
        const SizedBox(height: 16),
        Text('Âge : ${_age.round()} ans'),
        Slider(
          min: 10,
          max: 25,
          divisions: 15,
          value: _age,
          label: '${_age.round()} ans',
          onChanged: (v) => setState(() => _age = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Type de personnage (écris ce que tu veux)',
            hintText: 'ex : grand frère protecteur, calme, fan de foot…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _startChat,
          child: Text(_loading ? 'Création…' : 'Lancer la discussion'),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_status),
        ],
      ],
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + (_generating ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _messages.length) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('en train d\'écrire…',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                );
              }
              return _bubble(_messages[i]);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  enabled: !_generating,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _generating ? null : _send,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(ChatMessage m) {
    return Align(
      alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: m.fromMe ? Colors.green.shade100 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text),
            if (m.seconds != null)
              Text(
                '⏱ ${m.seconds!.toStringAsFixed(1)} s',
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }
}
