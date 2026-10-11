import 'package:flutter/material.dart';

import '../messages/message_store.dart';
import '../radar/radar_db.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'export_pdf.dart';
import 'result_screen.dart';

/// TOUTES les annonces vues par le radar : analysées (avec marge) et ignorées
/// (avec la raison), recherche texte, filtres.
class RadarAllScreen extends StatefulWidget {
  final Settings settings;
  const RadarAllScreen({super.key, required this.settings});

  @override
  State<RadarAllScreen> createState() => _RadarAllScreenState();
}

class _RadarAllScreenState extends State<RadarAllScreen> {
  bool _analyzed = true;
  bool _onlyProfitable = false;
  String _sort = 'recent';
  String _query = '';
  int? _search;
  List<RadarSearch> _searches = [];
  List<RadarAnalysis> _analyses = [];
  Set<String> _contacted = {};
  List<SeenAd> _seen = [];
  final Set<String> _selected = {}; // analyses cochées (appui long pour commencer)

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final searches = await RadarDb.searches();
    _sort = await RadarDb.feedSort();
    final analyses = await RadarDb.analyses(searchId: _search, sort: _sort);
    final seen = await RadarDb.seenAds(searchId: _search);
    final contacted = await MessageStore.contacted(analyses.map((a) => a.listId).toList());
    if (!mounted) return;
    setState(() {
      _searches = searches;
      _analyses = analyses;
      _contacted = contacted;
      _seen = seen;
      _selected.removeWhere((id) => !analyses.any((a) => a.listId == id));
    });
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  /// Demande confirmation. Rend null si annulé, sinon « oublier aussi les annonces vues ? ».
  Future<bool?> _confirmDelete(String title, String body) async {
    var forget = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(body),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: forget,
              onChanged: (v) => setD(() => forget = v ?? false),
              title: const Text('Aussi oublier ces annonces', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Le radar pourra les ré-analyser si elles reviennent', style: TextStyle(fontSize: 12)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
          ],
        ),
      ),
    );
    return ok == true ? forget : null;
  }

  void _done(int n) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(n == 1 ? '1 analyse supprimée.' : '$n analyses supprimées.')));
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final forget = await _confirmDelete(
        n == 1 ? 'Supprimer cette analyse ?' : 'Supprimer $n analyses ?', 'Cette action est définitive.');
    if (forget == null) return;
    final removed = await RadarDb.deleteAnalyses(_selected.toList(), forgetSeen: forget);
    _selected.clear();
    await _load();
    _done(removed);
  }

  Future<void> _deleteAll() async {
    if (_analyses.isEmpty) return;
    final scope = _search == null ? 'du radar' : 'de « ${_searchName(_search!)} »';
    final forget = await _confirmDelete(
        'Tout supprimer ?', 'Les ${_analyses.length} analyses $scope seront supprimées définitivement.');
    if (forget == null) return;
    final removed = await RadarDb.deleteAllAnalyses(searchId: _search, forgetSeen: forget);
    _selected.clear();
    await _load();
    _done(removed);
  }

  bool _match(String title) => _query.isEmpty || title.toLowerCase().contains(_query.toLowerCase());

  List<RadarAnalysis> get _shownAnalyses =>
      _analyses.where((a) => _match(a.title) && (!_onlyProfitable || a.profitable)).toList();

  List<SeenAd> get _shownSeen => _seen.where((a) => _match(a.title)).toList();

  Future<void> _openAnalysis(RadarAnalysis a) async {
    if (_selecting) return _toggle(a.listId);
    final entry = a.entry;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ResultScreen(entry: entry, settings: widget.settings)));
    await RadarDb.updateEntry(a.listId, entry);
  }

  Future<void> _openSeen(SeenAd s) async {
    final a = await RadarDb.analysis(s.listId);
    if (a != null) return _openAnalysis(a);
    if (s.url.isNotEmpty) openExternal(s.url);
  }

  String _searchName(int id) => _searches.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final analyses = _shownAnalyses;
    final seen = _shownSeen;
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              title: Text('${_selected.length} sélectionnée(s)'),
              actions: [
                IconButton(
                  tooltip: 'Tout sélectionner',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(() => _selected.addAll(analyses.map((a) => a.listId))),
                ),
                IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: _deleteSelected),
              ],
            )
          : AppBar(
              title: const Text('Toutes les annonces'),
              actions: [
                IconButton(
                  tooltip: 'Exporter en PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => showExportSheet(context, widget.settings),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'all') _deleteAll();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'all',
                        enabled: _analyses.isNotEmpty,
                        child: const Text('Tout supprimer…')),
                  ],
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text('Analysées (${_analyses.length})')),
                ButtonSegment(value: false, label: Text('Toutes vues (${_seen.length})')),
              ],
              selected: {_analyzed},
              onSelectionChanged: (v) => setState(() => _analyzed = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(hintText: 'Rechercher un titre…', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                if (_analyzed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: const Text('Rentables'),
                      selected: _onlyProfitable,
                      onSelected: (v) => setState(() => _onlyProfitable = v),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Toutes recherches'),
                    selected: _search == null,
                    onSelected: (_) {
                      _search = null;
                      _load();
                    },
                  ),
                ),
                for (final s in _searches)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: _search == s.id,
                      onSelected: (_) {
                        _search = s.id;
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (_analyzed) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'recent', icon: Icon(Icons.schedule, size: 18), label: Text('Récent')),
                  ButtonSegment(value: 'best', icon: Icon(Icons.trending_up, size: 18), label: Text('Bonne affaire')),
                ],
                selected: {_sort},
                showSelectedIcon: false,
                onSelectionChanged: (v) async {
                  await RadarDb.setFeedSort(v.first);
                  _load();
                },
              ),
              const SizedBox(height: 10),
              if (analyses.isEmpty) _empty(cs),
              for (final a in analyses) ...[
                _AnalysisTile(
                    a: a,
                    minMargin: widget.settings.minMargin,
                    contacted: _contacted.contains(a.listId),
                    selected: _selected.contains(a.listId),
                    selecting: _selecting,
                    onLongPress: () => _toggle(a.listId),
                    onTap: () => _openAnalysis(a)),
                const SizedBox(height: 8),
              ],
            ] else ...[
              if (seen.isEmpty) _empty(cs),
              for (final s in seen) ...[
                AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  onTap: () => _openSeen(s),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.title.isEmpty ? 'Annonce ${s.listId}' : s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${euros(s.price)} · ${_searchName(s.searchId)} · ${shortDate(s.seenAt)}',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(s.reason.isEmpty ? 'vue' : s.reason,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: s.reason == 'analysée' ? cs.primary : cs.onSurfaceVariant)),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('Rien à afficher.', style: TextStyle(color: cs.onSurfaceVariant))),
      );
}

class _AnalysisTile extends StatelessWidget {
  final RadarAnalysis a;
  final double minMargin;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool contacted;
  final bool selected;
  final bool selecting;
  const _AnalysisTile(
      {required this.a,
      required this.minMargin,
      required this.onTap,
      this.onLongPress,
      this.contacted = false,
      this.selected = false,
      this.selecting = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = verdictFor(a.margin, minMargin);
    final stage = switch (a.stage) { 'full' => 'complète', 'limit' => 'provisoire', _ => 'pré-analyse' };
    return GestureDetector(
      onLongPress: onLongPress,
      child: Opacity(
      opacity: a.profitable || selected ? 1 : 0.6,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: onTap,
        child: Row(children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.onSurfaceVariant),
            ),
          Container(width: 6, height: 44, decoration: BoxDecoration(color: v.color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 3),
              Text('${contacted ? '✉️ Contacté · ' : ''}${euros(a.price)} · ${a.searchName} · ${shortDate(a.createdAt)} · $stage',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(euros(a.margin, signed: true),
              style: TextStyle(color: v.color, fontWeight: FontWeight.w800, fontSize: 18, fontFeatures: tabular)),
        ]),
      ),
    ));
  }
}
