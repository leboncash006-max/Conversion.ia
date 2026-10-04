// ============================================================
//  ALLÔ 18 — Simulateur d'opérateur au centre de traitement
//  de l'alerte des pompiers.
//
//  Tu décroches, tu poses les bonnes questions, tu conseilles
//  l'appelant, tu engages les bons camions… et tu montes en grade.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'game_screen.dart';
import 'models.dart';
import 'sim.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const Allo18App());
}

class Allo18App extends StatelessWidget {
  const Allo18App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Allô 18',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.dark,
          surface: const Color(0xFF111A24),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B121B),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white38),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ------------------------------------------------------------
//  Sauvegarde du profil
// ------------------------------------------------------------

class Store {
  static Future<File?> _file() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/allo18_profil.json');
  }

  static Future<Profile> load() async {
    final p = Profile();
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        p.load(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return p;
  }

  static Future<void> save(Profile p) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(p.toJson()));
    } catch (_) {}
  }
}

// ------------------------------------------------------------
//  Accueil
// ------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Profile? profile;

  @override
  void initState() {
    super.initState();
    Store.load().then((p) {
      setState(() => profile = p);
      if (p.name.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _askName());
    });
  }

  Future<void> _askName() async {
    final ctrl = TextEditingController(text: profile?.name);
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Bienvenue au CTA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tu rejoins le centre de traitement de l\'alerte de Valmont. Ton nom d\'opérateur ?'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Ex. : Dupont', border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('C\'est parti'))],
      ),
    );
    final p = profile!;
    p.name = (name ?? '').trim().isEmpty ? 'Opérateur' : name!.trim();
    await Store.save(p);
    if (mounted) setState(() {});
  }

  void _start() {
    final p = profile!;
    final sim = Sim(level: p.level, operator: p.name, tutorial: p.gardes == 0);
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              sim: sim,
              onEnd: (s) async {
                final before = p.level;
                p.xp += s.totalScore;
                p.gardes++;
                p.appels += s.closedCalls.length;
                p.vies += s.saved;
                p.deces += s.lost;
                if (s.totalScore > p.best) p.best = s.totalScore;
                await Store.save(p);
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => DebriefScreen(sim: s, profile: p, promoted: p.level > before),
                  ),
                );
              },
            ),
          ),
        )
        .then((_) => setState(() {}));
  }

  void _rules() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comment ça marche'),
        content: const SingleChildScrollView(
          child: Text(
            '📞  Le 18 sonne : décroche avant que l\'appelant ne raccroche.\n\n'
            '❓  Pose les bonnes questions. Commence toujours par l\'adresse : sans elle, '
            'tu ne peux envoyer personne.\n\n'
            '🚒  Engage les moyens : choisis la nature, le logiciel te propose un départ type. '
            'Adapte-le à ce que l\'appelant t\'a dit (étage, victimes, personne coincée…).\n\n'
            '💬  Reste en ligne et donne des conseils. Un bon conseil sauve des vies, '
            'un mauvais peut tout faire basculer.\n\n'
            '📻  Sur place, les équipes peuvent demander des renforts : touche l\'intervention '
            'qui clignote pour en envoyer.\n\n'
            '🎭  Méfie-toi : canulars, appels pour la police (17) ou pour un médecin (15)… '
            'et des appels qui ressemblent à des blagues mais n\'en sont pas.\n\n'
            '⭐  Chaque intervention est notée. Ton score te fait monter en grade.\n\n'
            'Lexique : VSAV = ambulance pompier · FPT = fourgon incendie · EPA = grande échelle · '
            'VSR = désincarcération · CCF = feux de forêt · VTU = tous usages · BLS = bateau · '
            'SMUR = médecin du SAMU.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Scaffold(
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  const _Logo(),
                  const SizedBox(height: 28),
                  _ProfileCard(p: p, onRename: _askName),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Tile('Gardes', '${p.gardes}', Icons.nights_stay),
                      _Tile('Appels', '${p.appels}', Icons.phone),
                      _Tile('Vies sauvées', '${p.vies}', Icons.favorite),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Tile('Meilleure garde', '${p.best}', Icons.emoji_events),
                      _Tile('Décès', '${p.deces}', Icons.heart_broken),
                      _Tile('XP', '${p.xp}', Icons.star),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 62,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: red),
                      onPressed: _start,
                      icon: const Icon(Icons.headset_mic, size: 26),
                      label: Text(
                        p.gardes == 0 ? 'PREMIÈRE GARDE' : 'PRENDRE LA GARDE',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _rules,
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Comment jouer'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p.gardes == 0
                        ? 'Ta première garde est accompagnée par le lieutenant Garnier.'
                        : 'Garde de nuit · 19h → 23h · environ 8 minutes de jeu',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFF5252), Color(0xFF8B0000)]),
          boxShadow: [BoxShadow(color: red.withValues(alpha: 0.5), blurRadius: 30)],
        ),
        child: const Icon(Icons.local_fire_department, size: 54, color: Colors.white),
      ),
      const SizedBox(height: 14),
      const Text('ALLÔ 18', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6)),
      const Text(
        'Centre de traitement de l\'alerte · Valmont',
        style: TextStyle(color: Colors.white54, letterSpacing: 0.5),
      ),
    ],
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.p, required this.onRename});
  final Profile p;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final next = p.next;
    return Card(
      color: const Color(0xFF15202B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: red,
                  child: Text(
                    p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isEmpty ? '…' : p.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(p.grade.name, style: const TextStyle(color: Color(0xFFFF8A80))),
                    ],
                  ),
                ),
                IconButton(onPressed: onRename, icon: const Icon(Icons.edit, size: 18)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p.progress,
                minHeight: 8,
                color: const Color(0xFFFFB300),
                backgroundColor: Colors.white10,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              next == null ? 'Grade maximum atteint. Respect.' : '${p.xp} / ${next.xp} XP → ${next.name}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      color: const Color(0xFF15202B),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white54),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------
//  Débrief de fin de garde
// ------------------------------------------------------------

class DebriefScreen extends StatelessWidget {
  const DebriefScreen({super.key, required this.sim, required this.profile, required this.promoted});
  final Sim sim;
  final Profile profile;
  final bool promoted;

  String get _garnier {
    final calls = sim.closedCalls;
    if (calls.isEmpty) return 'Une garde sans appel ? Profite, ça n\'arrive jamais.';
    final avg = sim.totalScore / calls.length;
    if (sim.lost > 0 && avg < 60) {
      return 'Dure soirée. On a perdu du monde. Repose-toi, et demain on reprend les bases : adresse, moyens, conseils.';
    }
    if (avg >= 85) {
      return 'Franchement ? Du très beau travail. Les équipes sur le terrain ont adoré bosser avec toi ce soir.';
    }
    if (avg >= 70) return 'Bonne garde. Quelques hésitations, mais tu as les bons réflexes. Continue comme ça.';
    if (avg >= 50) return 'Correct, sans plus. Pose plus de questions avant d\'engager, et pense aux conseils.';
    return 'On va devoir retravailler ensemble. Relis tes interventions, chaque erreur est une leçon.';
  }

  Color _col(int s) => s >= 85
      ? const Color(0xFF66BB6A)
      : s >= 65
      ? const Color(0xFF9CCC65)
      : s >= 45
      ? const Color(0xFFFFCA28)
      : const Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    final calls = sim.closedCalls;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('FIN DE GARDE', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3)),
            Text('${calls.length} appels traités · ${fmtClock(sim.t)}', style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 18),
            Row(
              children: [
                _Tile('Score', '${sim.totalScore}', Icons.star),
                _Tile('Vies sauvées', '${sim.saved}', Icons.favorite),
                _Tile('Décès', '${sim.lost}', Icons.heart_broken),
              ],
            ),
            if (promoted) ...[
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFF4A3B00),
                child: ListTile(
                  leading: const Icon(Icons.military_tech, color: Color(0xFFFFD54F), size: 36),
                  title: const Text('PROMOTION !', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('Tu es maintenant ${profile.grade.name}. Les appels vont se corser…'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1A2B3D),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(backgroundColor: Color(0xFF0277BD), child: Text('LG')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lieutenant Garnier, chef de salle',
                            style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF81D4FA)),
                          ),
                          const SizedBox(height: 4),
                          Text('« $_garnier »'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'INTERVENTIONS',
              style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: Color(0xFFFF8A80), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final c in calls)
              Card(
                color: const Color(0xFF15202B),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _col(c.score).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${c.score}',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _col(c.score)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${fmtClock(c.ringAt)} · ${c.sc.nature.label}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(c.verdict, style: TextStyle(color: _col(c.score))),
                            if (c.survived != null)
                              Text(
                                c.survived! ? '❤️ Victime sauvée' : '🖤 Victime décédée',
                                style: const TextStyle(fontSize: 12),
                              ),
                            for (final n in c.notes)
                              Text('· $n', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: red, minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'RETOUR À LA CASERNE',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
