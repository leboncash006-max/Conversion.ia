import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';
import 'gemini.dart';

const meColor = Color(0xFF1E88E5);
const aiColor = Color(0xFFE53935);

void snack(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

// ===============================================================
//  Questionnaire de départ
// ===============================================================

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _answers = <int>[];
  bool _started = false;

  void _answer(int v) {
    setState(() => _answers.add(v));
    if (_answers.length == questions.length) _finish();
  }

  Future<void> _finish() async {
    final p = Profile(_name.text.trim(), List.of(_answers));
    await Store.saveProfile(p);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.how_to_vote, size: 72),
                const SizedBox(height: 16),
                Text('Crée ton parti',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                    '${questions.length} questions pour déterminer ton orientation politique.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nom de ton parti',
                      border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => setState(() => _started = true),
                  child: const Padding(
                      padding: EdgeInsets.all(12), child: Text('Commencer')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final i = _answers.length;
    final q = questions[i];
    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${i + 1} / ${questions.length}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            if (_answers.isEmpty) {
              _started = false;
            } else {
              _answers.removeLast();
            }
          }),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: i / questions.length),
              const Spacer(),
              Text(q.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              for (var v = 0; v < 5; v++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => _answer(v - 2),
                    child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(answerLabels[v])),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
//  Accueil
// ===============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Profile get p => Store.profile!;

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  Future<void> _retake() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Refaire le test ?'),
        content: const Text('Ton orientation actuelle sera remplacée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Refaire')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debates = Store.debates;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.party),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refaire le test',
              onPressed: _retake),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Paramètres',
              onPressed: () => _open(const SettingsScreen())),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const NewDebateScreen()),
        icon: const Icon(Icons.forum),
        label: const Text('Nouveau débat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Center(
            child: Chip(
              avatar: const Icon(Icons.explore, size: 18),
              label: Text(p.label, style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: CustomPaint(painter: CompassPainter(p.e, p.s, Theme.of(context))),
            ),
          ),
          const SizedBox(height: 8),
          _axisBar('Économie', 'Gauche', 'Droite', p.e),
          _axisBar('Société', 'Libertaire', 'Autoritaire', p.s),
          const SizedBox(height: 24),
          if (debates.isNotEmpty) ...[
            Text('Débats précédents', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final d in debates)
              Dismissible(
                key: ValueKey(d.id),
                background: Container(color: Colors.red),
                onDismissed: (_) => Store.deleteDebate(d.id),
                child: Card(
                  child: ListTile(
                    title: Text(d.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('contre ${d.opponentName} · ${d.opponentLeaning}'),
                    trailing: Text('${d.audience}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: d.audience >= 50 ? meColor : aiColor)),
                    onTap: () => _open(DebateScreen(d)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _axisBar(String title, String neg, String pos, double v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Row(children: [
            Text(neg, style: const TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(value: v.clamp(-1.0, 1.0), min: -1, max: 1, onChanged: null),
            ),
            Text(pos, style: const TextStyle(fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  final double e, s;
  final ThemeData theme;
  CompassPainter(this.e, this.s, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = theme.colorScheme.outline
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, line);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), line);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), line);

    void label(String t, Offset o) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o);
    }

    label('Autoritaire', Offset(size.width / 2 - 28, 3));
    label('Libertaire', Offset(size.width / 2 - 25, size.height - 15));
    label('Gauche', Offset(3, size.height / 2 + 3));
    label('Droite', Offset(size.width - 38, size.height / 2 + 3));

    final dot = Offset(
      size.width / 2 + e * size.width / 2 * 0.9,
      size.height / 2 - s * size.height / 2 * 0.9,
    );
    canvas.drawCircle(dot, 9, Paint()..color = meColor);
    canvas.drawCircle(dot, 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(CompassPainter old) => old.e != e || old.s != s;
}

// ===============================================================
//  Nouveau débat
// ===============================================================

class NewDebateScreen extends StatefulWidget {
  const NewDebateScreen({super.key});
  @override
  State<NewDebateScreen> createState() => _NewDebateScreenState();
}

class _NewDebateScreenState extends State<NewDebateScreen> {
  static const _partyNames = [
    'Union Nouvelle', 'Front Citoyen', 'Alliance Républicaine', 'Mouvement Horizon',
    'Parti du Renouveau', 'Les Indépendants', 'Génération Avenir', 'Rassemblement National Unifié',
    'Voix du Peuple', 'Coalition Sociale',
  ];
  final _topic = TextEditingController();
  final _name = TextEditingController();
  String _choice = 'Opposé à moi'; // 'Opposé à moi', 'Aléatoire' ou nom d'orientation

  Leaning _pick(Profile p) {
    if (_choice == 'Opposé à moi') return nearestLeaning(-p.e, -p.s);
    if (_choice == 'Aléatoire') return leanings[Random().nextInt(leanings.length)];
    return leanings.firstWhere((l) => l.name == _choice);
  }

  void _start() {
    final p = Store.profile!;
    final l = _pick(p);
    final name = _name.text.trim().isEmpty
        ? _partyNames[Random().nextInt(_partyNames.length)]
        : _name.text.trim();
    final d = Debate(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      topic: _topic.text.trim(),
      opponentName: name,
      opponentLeaning: l.name,
    );
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DebateScreen(d)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau débat')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _topic,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Sujet du débat',
                hintText: 'Ex : Faut-il instaurer un revenu universel ?',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _choice,
            decoration: const InputDecoration(
                labelText: 'Orientation de l\'adversaire', border: OutlineInputBorder()),
            items: [
              for (final o in ['Opposé à moi', 'Aléatoire', ...leanings.map((l) => l.name)])
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => setState(() => _choice = v!),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Nom du parti adverse (facultatif)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _topic.text.trim().isEmpty ? null : _start,
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Lancer le débat')),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
//  Débat
// ===============================================================

class DebateScreen extends StatefulWidget {
  final Debate debate;
  const DebateScreen(this.debate, {super.key});
  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

class _DebateScreenState extends State<DebateScreen> {
  late final Debate d = widget.debate;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  Profile get p => Store.profile!;

  /// Contexte factuel (pas de consigne) ajouté aux instructions de l'utilisateur.
  String get _context =>
      'Contexte — Sujet du débat : ${d.topic}. '
      'Ton parti : ${d.opponentName} (orientation : ${d.opponentLeaning}). '
      'Parti de ton interlocuteur : ${p.party} (orientation : ${p.label}).';

  String get _opponentSystem {
    final s = Store.settings;
    return [s.strict, s.extra, _context].where((t) => t.trim().isNotEmpty).join('\n\n');
  }

  String get _audienceSystem {
    final s = Store.settings;
    final ctx = 'Contexte — Sujet du débat : ${d.topic}. '
        'Le joueur humain représente le parti ${p.party} (orientation : ${p.label}). '
        'L\'adversaire représente le parti ${d.opponentName} (orientation : ${d.opponentLeaning}).';
    return [s.audience, ctx].where((t) => t.trim().isNotEmpty).join('\n\n');
  }

  String get _transcript => d.messages
      .skip(max(0, d.messages.length - 8))
      .map((m) => '${m.role == 'me' ? p.party : d.opponentName} : ${m.text}')
      .join('\n\n');

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || d.finished) return;
    final settings = Store.settings;
    setState(() {
      d.messages.add(Msg('me', text));
      _input.clear();
      _busy = true;
    });
    _scrollDown();

    final String reply;
    try {
      reply = await Gemini.opponent(settings, _opponentSystem, d.messages);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        d.messages.removeLast();
        _input.text = text;
        _busy = false;
      });
      snack(context, '$e');
      return;
    }

    final ai = Msg('ai', reply);
    setState(() => d.messages.add(ai));
    _scrollDown();

    try {
      final a = await Gemini.audience(settings, _audienceSystem, _transcript);
      ai.shift = a.shift;
      ai.comment = a.comment;
      d.audience = (d.audience + a.shift).clamp(0, 100);
    } catch (e) {
      if (mounted) snack(context, 'Public indisponible : $e');
    }
    await Store.saveDebate(d);
    if (!mounted) return;
    setState(() => _busy = false);
    _scrollDown();
  }

  Future<void> _finish() async {
    setState(() => d.finished = true);
    await Store.saveDebate(d);
    if (!mounted) return;
    final win = d.audience > 50;
    final tie = d.audience == 50;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tie ? 'Égalité' : win ? 'Tu as convaincu le public !' : 'Le public a penché pour ${d.opponentName}'),
        content: Text('${p.party} ${d.audience}% — ${100 - d.audience}% ${d.opponentName}'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(d.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!d.finished && d.messages.isNotEmpty)
            TextButton(onPressed: _busy ? null : _finish, child: const Text('Terminer')),
        ],
      ),
      body: Column(
        children: [
          _AudienceBar(
              mine: p.party, theirs: d.opponentName, percent: d.audience),
          Expanded(
            child: d.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Face à ${d.opponentName} (${d.opponentLeaning}).\nÀ toi d\'ouvrir le débat !',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: d.messages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == d.messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      return _bubble(d.messages[i]);
                    },
                  ),
          ),
          if (!d.finished)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                            hintText: 'Ton argument…', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(Msg m) {
    final me = m.role == 'me';
    final color = me ? meColor : aiColor;
    return Column(
      crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(m.text),
        ),
        if (m.comment != null && m.comment!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: Text(
              '👥 « ${m.comment} »  ${(m.shift ?? 0) > 0 ? '+' : ''}${m.shift ?? 0}',
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.outline),
            ),
          ),
      ],
    );
  }
}

class _AudienceBar extends StatelessWidget {
  final String mine, theirs;
  final int percent;
  const _AudienceBar({required this.mine, required this.theirs, required this.percent});

  @override
  Widget build(BuildContext context) {
    const n = 20;
    final mineCount = (percent / 100 * n).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$mine $percent%',
                  style: const TextStyle(color: meColor, fontWeight: FontWeight.bold)),
              Text('${100 - percent}% $theirs',
                  style: const TextStyle(color: aiColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < n; i++)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Icon(Icons.person,
                      key: ValueKey('$i-${i < mineCount}'),
                      size: 16,
                      color: i < mineCount ? meColor : aiColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===============================================================
//  Paramètres
// ===============================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = Store.settings;
  late final _key = TextEditingController(text: s.apiKey);
  late final _model = TextEditingController(text: s.model);
  late final _strict = TextEditingController(text: s.strict);
  late final _extra = TextEditingController(text: s.extra);
  late final _audience = TextEditingController(text: s.audience);
  bool _hide = true;

  // Suggestions : jamais envoyées à l'IA tant que tu ne les insères pas.
  static const _sugStrict =
      'Tu es un politicien qui débat. Défends fermement les positions de ton parti selon son orientation. '
      'Reste respectueux, argumente avec des faits et des exemples, réponds directement aux arguments de '
      'l\'adversaire et attaque ses points faibles. Ne sors jamais de ton rôle. Réponds en français.';
  static const _sugExtra =
      'Réponds en 4 phrases maximum. Utilise un ton oral de débat télévisé. '
      'Termine parfois par une question piège à l\'adversaire.';
  static const _sugAudience =
      'Tu simules un public de spectateurs qui écoutent un débat. Après le dernier échange, évalue '
      'qui a été le plus convaincant (qualité des arguments, cohérence, éloquence, réponse aux attaques). '
      'Donne un "shift" de -15 à 15 : positif si le public penche vers le joueur humain, négatif vers '
      'l\'adversaire, 0 si égalité. Les spectateurs ont des sensibilités variées. Ajoute une courte '
      'réaction d\'un spectateur dans "comment".';

  Future<void> _save() async {
    s
      ..apiKey = _key.text.trim()
      ..model = _model.text.trim().isEmpty ? 'gemini-flash-lite-latest' : _model.text.trim()
      ..strict = _strict.text
      ..extra = _extra.text
      ..audience = _audience.text;
    await Store.saveSettings(s);
    if (mounted) {
      snack(context, 'Paramètres enregistrés');
      Navigator.pop(context);
    }
  }

  Widget _prompt(String title, String help, TextEditingController c, String suggestion) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(help, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'Vide = rien n\'est envoyé'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Insérer la suggestion'),
              onPressed: () => setState(() => c.text = suggestion),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        actions: [TextButton(onPressed: _save, child: const Text('Enregistrer'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _key,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'Clé API Gemini',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
                labelText: 'Modèle', border: OutlineInputBorder()),
          ),
          _prompt(
            'Consignes strictes de l\'adversaire',
            'Le rôle et les règles que l\'IA doit suivre. Rien n\'est écrit en dur : c\'est toi qui décides.',
            _strict,
            _sugStrict,
          ),
          _prompt(
            'Instructions supplémentaires',
            'Style, longueur, ton, petites manies… ajoutées après les consignes strictes.',
            _extra,
            _sugExtra,
          ),
          _prompt(
            'Consignes du public',
            'Comment les spectateurs jugent le débat et font pencher la jauge.',
            _audience,
            _sugAudience,
          ),
          const SizedBox(height: 12),
          Text(
            'Seul un bloc de contexte (sujet, noms et orientations des partis) est ajouté '
            'automatiquement à tes consignes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
