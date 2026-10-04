import 'package:flutter/material.dart';

import 'models.dart';
import 'sim.dart';

// ============================================================
//  Feuilles modales : engagement des moyens, fiche d'intervention
// ============================================================

Future<void> showDispatch(BuildContext context, Sim sim, Incident c) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF111A24),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => DispatchSheet(sim: sim, c: c, scroll: ctrl),
    ),
  );
}

class DispatchSheet extends StatefulWidget {
  const DispatchSheet({super.key, required this.sim, required this.c, required this.scroll});
  final Sim sim;
  final Incident c;
  final ScrollController scroll;

  @override
  State<DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<DispatchSheet> {
  Nature? nature;
  final selected = <Vehicle>{};

  Sim get sim => widget.sim;
  Incident get c => widget.c;

  @override
  void initState() {
    super.initState();
    nature = c.nature;
    if (c.missing.isNotEmpty) {
      c.missing.forEach((type, n) {
        final cands = sim.vehicles.where((v) => v.type == type && v.available).toList()
          ..sort((a, b) => sim.eta(a, c.loc).compareTo(sim.eta(b, c.loc)));
        selected.addAll(cands.take(n));
      });
    } else if (c.awaiting && c.nature == null) {
      // rien de présélectionné : l'opérateur choisit la nature
    }
  }

  void _choose(Nature n) {
    setState(() {
      nature = n;
      selected
        ..clear()
        ..addAll(sim.proposal(c, n));
    });
  }

  String _eta(Vehicle v) => '≈ ${(sim.eta(v, c.loc) / 60).ceil()} min';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sim,
      builder: (context, _) {
        final avail = sim.vehicles.where((v) => v.available).toList()
          ..sort((a, b) {
            final s = (selected.contains(b) ? 1 : 0) - (selected.contains(a) ? 1 : 0);
            if (s != 0) return s;
            final t = a.type.index - b.type.index;
            if (t != 0) return t;
            return sim.eta(a, c.loc).compareTo(sim.eta(b, c.loc));
          });
        final none = VType.values.where((t) => !avail.any((v) => v.type == t)).toList();
        final count = selected.where((v) => v.available).length;
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: ListView(
                controller: widget.scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Text(
                    c.dispatched ? 'Envoyer des renforts' : 'Engagement des moyens',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text('📍 ${c.address}', style: const TextStyle(color: Colors.white70)),
                  if (c.missing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _Alert(
                      'Demandé sur place : ${c.missing.entries.map((e) => '${e.value} ${e.key.code}').join(', ')}',
                    ),
                  ],
                  if (!c.dispatched || c.awaiting) ...[
                    const SizedBox(height: 16),
                    const _Title('1 · Nature de l\'intervention'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in Nature.values)
                          ChoiceChip(
                            avatar: Icon(n.icon, size: 16),
                            label: Text(n.label, style: const TextStyle(fontSize: 12)),
                            selected: nature == n,
                            onSelected: (_) => _choose(n),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _Title(c.dispatched ? 'Moyens disponibles' : '2 · Moyens proposés (modifiables)'),
                  for (final v in avail)
                    _VehicleTile(
                      v: v,
                      eta: _eta(v),
                      selected: selected.contains(v),
                      onTap: () => setState(() => selected.contains(v) ? selected.remove(v) : selected.add(v)),
                    ),
                  if (none.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const _Title('Plus rien de disponible'),
                    for (final t in none)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: _Badge(t),
                        title: Text('Aucun ${t.code} libre'),
                        subtitle: const Text('Demander au centre voisin (plus loin)'),
                        trailing: OutlinedButton(
                          onPressed: () => setState(() => selected.add(sim.borrow(t))),
                          child: const Text('Emprunter'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                    onPressed: count == 0
                        ? null
                        : () {
                            sim.engage(c, selected.toList(), nature: nature);
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.local_shipping),
                    label: Text(
                      count == 0 ? 'Choisis des moyens' : 'ENGAGER ($count)',
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.v, required this.eta, required this.selected, required this.onTap});
  final Vehicle v;
  final String eta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: selected ? const Color(0xFF3A1F22) : const Color(0xFF17222E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? const Color(0xFFE53935) : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              _Badge(v.type),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      v.type.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Text(eta, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Checkbox(value: selected, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.t);
  final VType t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: t.color, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: Text(
        t.code,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: t.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12, letterSpacing: 1.2, color: Color(0xFFFF8A80), fontWeight: FontWeight.w700),
    ),
  );
}

class _Alert extends StatelessWidget {
  const _Alert(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0x33FF1744),
      border: Border.all(color: const Color(0xFFFF1744)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.campaign, color: Color(0xFFFF5252)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------
//  Fiche d'intervention
// ------------------------------------------------------------

Future<void> showIncident(BuildContext context, Sim sim, Incident c) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF111A24),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => AnimatedBuilder(
        animation: sim,
        builder: (context, _) {
          final vs = c.vehicles.where((v) => v.inc == c).toList();
          return ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon((c.nature ?? c.sc.nature).icon, color: const Color(0xFFFF7043)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.dispatched ? c.shortLabel : 'Intervention à engager',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('📍 ${c.address}', style: const TextStyle(color: Colors.white70)),
              Text('Appel reçu à ${fmtClock(c.ringAt)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 12),
              if (c.done) _Alert('Terminée : ${c.verdict}'),
              if (c.missing.isNotEmpty)
                _Alert('Renfort demandé : ${c.missing.entries.map((e) => '${e.value} ${e.key.code}').join(', ')}'),
              if (c.awaiting) const _Alert('Communication coupée : aucun moyen engagé !'),
              if (!c.done && (c.missing.isNotEmpty || c.awaiting || c.dispatched)) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.missing.isNotEmpty || c.awaiting
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF37474F),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    showDispatch(context, sim, c);
                  },
                  icon: const Icon(Icons.add_road),
                  label: Text(c.awaiting ? 'Engager des moyens' : 'Envoyer des renforts'),
                ),
              ],
              const SizedBox(height: 16),
              const _Title('Moyens sur l\'intervention'),
              if (vs.isEmpty) const Text('Aucun', style: TextStyle(color: Colors.white38)),
              for (final v in vs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      _Badge(v.type),
                      const SizedBox(width: 10),
                      Expanded(child: Text(v.name)),
                      Text(
                        v.state == VState.route || v.state == VState.depart
                            ? '${v.state.label} · ${_mins(sim.eta(v, c.loc))}'
                            : v.state.label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const _Title('Radio'),
              if (c.radio.isEmpty) const Text('Rien pour l\'instant.', style: TextStyle(color: Colors.white38)),
              for (final m in c.radio.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(m, style: const TextStyle(fontSize: 13)),
                ),
            ],
          );
        },
      ),
    ),
  );
}

String _mins(double s) => '${(s / 60).ceil()} min';
