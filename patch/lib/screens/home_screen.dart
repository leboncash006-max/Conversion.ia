import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/history.dart';
import '../services/leboncoin_reader.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'analysis_screen.dart';
import 'deals_screen.dart';
import 'export_pdf.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Settings settings;
  const HomeScreen({super.key, required this.settings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _url = TextEditingController();
  List<HistoryEntry> _history = [];
  bool _historyLoaded = false;
  String? _error;

  /// Lien Leboncoin trouvé dans le presse-papiers (bannière).
  Uri? _clipUrl;

  /// Liens déjà proposés / analysés pendant cette session (pas de re-proposition).
  final _handled = <String>{};

  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  Settings get s => widget.settings;

  static String _norm(Uri u) => '${u.host.replaceFirst('www.', '')}${u.path}'
      .replaceAll(RegExp(r'/+$'), '');

  // --------------------------------------------------------------- cycle de vie

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHistory().then((_) => _checkClipboard());
    _initShare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _url.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // petit délai : Android n'autorise la lecture du presse-papiers qu'une
      // fois la fenêtre au premier plan
      Future.delayed(const Duration(milliseconds: 350), _checkClipboard);
    }
  }

  Future<void> _loadHistory() async {
    final h = await HistoryStore.load();
    if (!mounted) return;
    setState(() {
      _history = h;
      _historyLoaded = true;
    });
  }

  // ------------------------------------------------------------- partage Android

  void _initShare() {
    try {
      // appli déjà ouverte
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared,
          onError: (_) {});
      // appli lancée par « Partager > MPB Check »
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _onShared(files);
        ReceiveSharingIntent.instance.reset();
      }).catchError((_) {});
    } catch (_) {
      // plateforme sans partage (tests, desktop)
    }
  }

  void _onShared(List<SharedMediaFile> files) {
    for (final f in files) {
      final uri = extractLeboncoinUrl('${f.path}\n${f.message ?? ''}');
      if (uri != null) {
        _url.text = uri.toString();
        _startLink(uri, fromShare: true);
        return;
      }
    }
    if (files.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun lien Leboncoin dans le partage.')));
    }
  }

  // --------------------------------------------------------- presse-papiers

  Future<void> _checkClipboard() async {
    if (!mounted) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final uri = extractLeboncoinUrl(data?.text ?? '');
      if (uri == null) {
        if (_clipUrl != null && mounted) setState(() => _clipUrl = null);
        return;
      }
      final key = _norm(uri);
      final known = _handled.contains(key) ||
          _history.any((h) => h.url.isNotEmpty && _norm(Uri.parse(h.url)) == key);
      if (known || _url.text.contains(uri.path)) return;
      if (mounted) setState(() => _clipUrl = uri);
    } catch (_) {}
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    final uri = extractLeboncoinUrl(text);
    _url.text = uri?.toString() ?? text;
    if (uri != null) _startLink(uri);
  }

  // --------------------------------------------------------------- actions

  void _analyzeField() {
    FocusScope.of(context).unfocus();
    final uri = extractLeboncoinUrl(_url.text);
    if (uri == null) {
      setState(() => _error = "Colle un lien d'annonce leboncoin.fr.");
      return;
    }
    _startLink(uri);
  }

  Future<void> _startLink(Uri uri, {bool fromShare = false}) async {
    _handled.add(_norm(uri));
    setState(() {
      _error = null;
      _clipUrl = null;
    });
    final nav = Navigator.of(context);
    if (fromShare) nav.popUntil((r) => r.isFirst);
    await nav.push(MaterialPageRoute(
        builder: (_) => AnalysisScreen(settings: s, url: uri)));
    _loadHistory();
  }

  Future<void> _startManual() async {
    final m = await showModalBottomSheet<ManualAd>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ManualSheet(),
    );
    if (m == null || !mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AnalysisScreen(settings: s, manual: m)));
    _loadHistory();
  }

  Future<void> _openEntry(HistoryEntry e) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ResultScreen(entry: e, settings: s)));
    _loadHistory();
  }

  Future<void> _delete(HistoryEntry e) async {
    final idx = _history.indexOf(e);
    setState(() => _history.remove(e));
    await HistoryStore.remove(e.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('Analyse supprimée'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            setState(() => _history.insert(idx.clamp(0, _history.length), e));
            await HistoryStore.upsert(e);
            _loadHistory();
          },
        ),
      ));
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset('assets/icon/icon.png', width: 30, height: 30),
          ),
          const SizedBox(width: 10),
          const Text('MPB Check'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Mes affaires',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => DealsScreen(settings: s))),
          ),
          IconButton(
            tooltip: 'Paramètres',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => SettingsScreen(settings: s)));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.list(children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: _clipUrl == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ClipBanner(
                          url: _clipUrl!,
                          onAnalyze: () => _startLink(_clipUrl!),
                          onDismiss: () => setState(() {
                            _handled.add(_norm(_clipUrl!));
                            _clipUrl = null;
                          }),
                        ),
                      ),
              ),
              FadeSlideIn(child: _linkCard(t, cs)),
              const SizedBox(height: 26),
              Row(children: [
                Text('HISTORIQUE',
                    style: TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                if (_history.isNotEmpty)
                  Text('${_history.length}',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary)),
                const Spacer(),
                if (_history.isNotEmpty) ...[
                  Text('Glisse pour supprimer',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  IconButton(
                    tooltip: 'Exporter en PDF',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    onPressed: () => showExportSheet(context, s),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
            ]),
          ),
          if (_historyLoaded && _history.isEmpty)
            SliverToBoxAdapter(child: _EmptyHistory())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.builder(
                itemCount: _history.length,
                itemBuilder: (_, i) {
                  final e = _history[i];
                  return Padding(
                    key: ValueKey(e.id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                      child: Dismissible(
                        key: ValueKey('d${e.id}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _delete(e),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: AppColors.bad.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(kRadius),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        child: _HistoryTile(
                            entry: e, minMargin: s.minMargin, onTap: () => _openEntry(e)),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  Widget _linkCard(TextTheme t, ColorScheme cs) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.accent.withValues(alpha: 0.22), cs.surface],
          ),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Colle le lien', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text("Ou partage l'annonce depuis l'appli Leboncoin vers MPB Check.",
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: 'https://www.leboncoin.fr/ad/…',
              prefixIcon: const Icon(Icons.link),
              errorText: _error,
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Coller'),
                ),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _analyzeField(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _analyzeField,
            icon: const Icon(Icons.bolt),
            label: const Text('Analyser'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _startManual,
            icon: const Icon(Icons.edit_note, size: 20),
            label: const Text('Saisir le texte à la main'),
          ),
        ]),
      );
}

class _ClipBanner extends StatelessWidget {
  final Uri url;
  final VoidCallback onAnalyze;
  final VoidCallback onDismiss;
  const _ClipBanner({required this.url, required this.onAnalyze, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.content_paste_go, color: cs.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text("Analyser l'annonce copiée ?",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 34, top: 2, right: 8),
          child: Text('${url.host}${url.path}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: onDismiss, child: const Text('Ignorer')),
          const SizedBox(width: 4),
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: onAnalyze,
            child: const Text('Analyser'),
          ),
        ]),
      ]),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final double minMargin;
  final VoidCallback onTap;
  const _HistoryTile({required this.entry, required this.minMargin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = entry.analysis;
    final v = verdictFor(a.margin, minMargin);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 6,
          height: 44,
          decoration:
              BoxDecoration(color: v.color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title.isEmpty ? 'Annonce' : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 3),
            Row(children: [
              Text(euros(entry.adPrice ?? a.price),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontFeatures: tabular)),
              Text('  ·  ${shortDate(entry.date)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              if (entry.chat.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(Icons.forum_outlined, size: 14, color: cs.onSurfaceVariant),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(euros(a.margin, signed: true),
              style: TextStyle(
                  color: v.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  fontFeatures: tabular)),
          Text('marge', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      child: Column(children: [
        Icon(Icons.history_toggle_off, size: 40, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Text('Aucune analyse pour le moment',
            style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('Les 50 dernières analyses apparaîtront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Saisie manuelle (titre, description, prix), comme le mode « Texte » de la v1.
class _ManualSheet extends StatefulWidget {
  const _ManualSheet();

  @override
  State<_ManualSheet> createState() => _ManualSheetState();
}

class _ManualSheetState extends State<_ManualSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty && _desc.text.trim().isEmpty) {
      setState(() => _error = "Colle au moins le titre de l'annonce.");
      return;
    }
    final price =
        double.tryParse(_price.text.replaceAll(',', '.').replaceAll('€', '').trim());
    Navigator.pop(context, ManualAd(_title.text.trim(), _desc.text.trim(), price));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Saisie manuelle', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: 'Titre', errorText: _error),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Prix', suffixText: '€'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: _submit, icon: const Icon(Icons.bolt), label: const Text('Analyser')),
        ]),
      ),
    );
  }
}
