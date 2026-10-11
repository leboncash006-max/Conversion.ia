import 'package:flutter/material.dart';

import '../main.dart';
import '../services/deepseek_web.dart';
import '../services/mpb_catalog.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'catalog_screen.dart';
import 'deepseek_login_screen.dart';
import 'lbc_login_screen.dart';
import 'message_settings_screen.dart';
import 'net_settings_screen.dart';
import 'radar_all_screen.dart';
import 'radar_log_screen.dart';
import 'radar_searches_screen.dart';
import 'radar_setup_screen.dart';
import 'radar_test_screen.dart';

/// Menu « Paramètres » : tous les réglages de l'appli, regroupés par thème.
class SettingsScreen extends StatefulWidget {
  final Settings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _margin = TextEditingController(text: widget.settings.minMargin.toStringAsFixed(0));
  late final _coefBody = TextEditingController(text: widget.settings.coefBody.toString());
  late final _coefLens = TextEditingController(text: widget.settings.coefLens.toString());

  MpbCatalog? _catalog;
  bool _catalogLoaded = false;

  bool _dsOn = false;
  bool _dsChat = false;
  bool _dsPhotos = false;
  bool _dsVision = false;
  bool _dsTesting = false;
  bool _dsVisionTesting = false;
  String? _dsResult;

  @override
  void initState() {
    super.initState();
    _loadDs();
    MpbCatalog.load().then((c) {
      if (mounted) {
        setState(() {
          _catalog = c;
          _catalogLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _margin.dispose();
    _coefBody.dispose();
    _coefLens.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- DeepSeek

  Future<void> _loadDs() async {
    final on = await DeepSeekWeb.enabled();
    final chat = await DeepSeekWeb.chatEnabled();
    final photos = await DeepSeekWeb.photosEnabled();
    final vision = await DeepSeekWeb.visionVerified();
    if (mounted) {
      setState(() {
        _dsOn = on;
        _dsChat = chat;
        _dsPhotos = photos;
        _dsVision = vision;
      });
    }
  }

  Future<void> _setDs(bool v) async {
    await DeepSeekWeb.setEnabled(v);
    setState(() => _dsOn = v);
  }

  Future<void> _setDsChat(bool v) async {
    await DeepSeekWeb.setChatEnabled(v);
    setState(() => _dsChat = v);
  }

  Future<void> _setDsPhotos(bool v) async {
    await DeepSeekWeb.setPhotosEnabled(v);
    setState(() => _dsPhotos = v);
  }

  Future<void> _testDs() async {
    setState(() {
      _dsTesting = true;
      _dsResult = null;
    });
    DeepSeekWeb.resume();
    final r = await DeepSeekWeb.test();
    if (mounted) {
      setState(() {
        _dsTesting = false;
        _dsResult = r;
      });
    }
  }

  Future<void> _testDsVision() async {
    setState(() {
      _dsVisionTesting = true;
      _dsResult = null;
    });
    DeepSeekWeb.resume();
    final r = await DeepSeekWeb.testVision();
    if (mounted) {
      setState(() {
        _dsVisionTesting = false;
        _dsVision = r.ok;
        _dsResult = r.message;
        if (!r.ok) _dsPhotos = false;
      });
      if (!r.ok) await DeepSeekWeb.setPhotosEnabled(false);
    }
  }

  // --------------------------------------------------------- réglages chiffrés

  double? _parse(String s) => double.tryParse(s.replaceAll(',', '.').replaceAll('€', '').trim());

  /// Enregistrement immédiat à chaque modification (valeurs invalides ignorées).
  Future<void> _saveNumbers() async {
    final s = widget.settings;
    final m = _parse(_margin.text);
    final cb = _parse(_coefBody.text);
    final cl = _parse(_coefLens.text);
    if (m != null) s.minMargin = m;
    if (cb != null) s.coefBody = cb;
    if (cl != null) s.coefLens = cl;
    await s.save();
  }

  Future<void> _setDark(bool v) async {
    setState(() => widget.settings.darkTheme = v);
    darkThemeNotifier.value = v;
    await widget.settings.save();
  }

  Future<void> _refreshCatalog() async {
    await MpbCatalog.invalidate();
    if (!mounted) return;
    setState(() => _catalog = null);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le catalogue sera retéléchargé à la prochaine analyse.')));
  }

  // ---------------------------------------------------------------- éléments

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = widget.settings;
    const gap = SizedBox(height: 10);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // ------------------------------------------------ bonne affaire
          _section('Bonne affaire'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Seuil minimal', style: t.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                  'Marge mini pour qu\'une annonce compte comme « bonne affaire » '
                  '(notifications du radar, envoi automatique, vert/orange/rouge).',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: _margin,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _saveNumbers(),
                decoration: const InputDecoration(labelText: 'Marge mini', suffixText: '€'),
              ),
            ]),
          ),
          gap,
          _tile(
              Icons.receipt_long_outlined,
              'Marge nette',
              s.net.home.isEmpty
                  ? 'Ville, trajet, frais Leboncoin, livraison'
                  : '${s.net.home} · ${s.net.kmCost} €/km · max ${s.net.maxKm.toStringAsFixed(0)} km',
              () => _push(NetSettingsScreen(settings: s))),

          // -------------------------------------------------------- IA
          _section('IA gratuite'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('DeepSeek', style: t.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                  'Le chat web chat.deepseek.com tourne en arrière-plan pour les textes '
                  '(identification, radar, messages, questions). Gemini reste le secours. '
                  'Plus lent (10 à 40 s par réponse) mais ça ménage le quota Gemini.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const DeepSeekLoginScreen()));
                },
                icon: const Icon(Icons.login),
                label: const Text('Se connecter à DeepSeek'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dsOn,
                onChanged: _setDs,
                title: const Text('Utiliser DeepSeek en premier', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dsChat,
                onChanged: _dsOn ? _setDsChat : null,
                title: const Text('Aussi pour le chat'),
                subtitle: const Text('Sans la recherche Google de Gemini'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dsPhotos,
                onChanged: _dsOn && _dsVision ? _setDsPhotos : null,
                title: const Text('Envoyer les photos à DeepSeek'),
                subtitle: Text(_dsVision
                    ? 'Test de vision réussi · Gemini en secours'
                    : 'À activer après un test de vision réussi (ci-dessous)'),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _dsTesting || _dsVisionTesting ? null : _testDs,
                icon: _dsTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt),
                label: Text(_dsTesting ? 'Test en cours…' : 'Tester DeepSeek (texte)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _dsTesting || _dsVisionTesting ? null : _testDsVision,
                icon: _dsVisionTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined),
                label: Text(_dsVisionTesting ? 'Test en cours…' : 'Tester la vision (photos)'),
              ),
              if (_dsResult != null) ...[
                const SizedBox(height: 8),
                Text(_dsResult!, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 4),
              Text('Dernier état : ${DeepSeekWeb.lastStatus}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          gap,
          _tile(Icons.vpn_key_outlined, 'Clés Gemini et diagnostic', 'Test des clés, état du radar',
              () => _push(const RadarTestScreen())),

          // ------------------------------------------------------ comptes
          _section('Comptes'),
          _tile(Icons.shopping_bag_outlined, 'Connexion Leboncoin', 'Session utilisée pour les messages',
              () => _push(const LbcLoginScreen())),

          // ------------------------------------------------------- radar
          _section('Radar'),
          _tile(Icons.manage_search, 'Recherches surveillées', 'Ajouter, modifier, activer',
              () => _push(const RadarSearchesScreen())),
          _tile(Icons.delete_sweep_outlined, 'Analyses du radar', 'Voir, supprimer certaines ou tout',
              () => _push(RadarAllScreen(settings: s))),
          _tile(Icons.settings_suggest_outlined, 'Autorisations et fonctionnement', 'Notifications, batterie, écoute',
              () => _push(const RadarSetupScreen())),
          _tile(Icons.receipt_long_outlined, 'Journal du radar', 'Ce que le radar a fait',
              () => _push(const RadarLogScreen())),

          // ---------------------------------------------------- messages
          _section('Messages aux vendeurs'),
          _tile(Icons.forum_outlined, 'Réglages des messages', 'Mode, ton, consignes, plafond',
              () => _push(const MessageSettingsScreen())),

          // ---------------------------------------------------- catalogue
          _section('Données'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Catalogue MPB', style: t.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                  !_catalogLoaded
                      ? '…'
                      : _catalog == null
                          ? 'Pas encore téléchargé : il le sera à la prochaine analyse.'
                          : '${_catalog!.size} noms exacts de modèles, mis à jour le '
                              '${shortDate(_catalog!.date)}. Rafraîchi automatiquement chaque semaine.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _catalog == null ? null : () => _push(const CatalogScreen()),
                icon: const Icon(Icons.list_alt),
                label: const Text('Voir le catalogue (modèles et identifiants)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _catalog == null ? null : _refreshCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Retélécharger le catalogue'),
              ),
            ]),
          ),
          gap,
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Calcul de secours', style: t.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                  'La reprise vient du prix réel de MPB pour l\'état de l\'annonce. '
                  'Les coefficients ne servent que si cette API ne répond pas : '
                  'revente MPB en état Bon × coefficient (estimation approximative).',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _coefBody,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _saveNumbers(),
                    decoration: const InputDecoration(labelText: 'Coef boîtiers'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _coefLens,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _saveNumbers(),
                    decoration: const InputDecoration(labelText: 'Coef objectifs'),
                  ),
                ),
              ]),
            ]),
          ),

          // -------------------------------------------------- apparence
          _section('Apparence'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: SwitchListTile(
              value: s.darkTheme,
              onChanged: _setDark,
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Thème sombre', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
