import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'map_view.dart';
import 'models.dart';
import 'sheets.dart';
import 'sim.dart';

// ============================================================
//  Écran de garde : carte + appel en cours + radio
// ============================================================

const red = Color(0xFFD32F2F);
const panel = Color(0xFF111A24);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.sim, required this.onEnd});
  final Sim sim;
  final void Function(Sim sim) onEnd;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Incident? _selected;
  bool _ended = false;

  Sim get sim => widget.sim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !sim.paused) sim.togglePause();
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    sim.tick(dt);
    for (var e = sim.takeEvent(); e != null; e = sim.takeEvent()) {
      if (e == 'ring') HapticFeedback.mediumImpact();
      if (e == 'alert') HapticFeedback.heavyImpact();
    }
    if (sim.over && !_ended) {
      _ended = true;
      widget.onEnd(sim);
    }
  }

  void _openIncident(Incident c) {
    setState(() => _selected = c);
    if (c.callOpen && c == sim.call) return;
    showIncident(context, sim, c).then((_) {
      if (mounted) setState(() => _selected = null);
    });
  }

  Future<void> _pauseMenu() async {
    if (!sim.paused) sim.togglePause();
    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pause'),
        content: const Text('La garde est en pause. Les appelants patientent…'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abandonner la garde')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Reprendre')),
        ],
      ),
    );
    if (!mounted) return;
    if (quit == true) {
      Navigator.pop(context);
    } else if (sim.paused) {
      sim.togglePause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pauseMenu();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B121B),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: sim,
            builder: (context, _) => Column(
              children: [
                _TopBar(sim: sim, onPause: _pauseMenu),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  height: screenH * (sim.call != null ? 0.24 : 0.34),
                  child: MapView(sim: sim, selected: _selected, onTapIncident: _openIncident),
                ),
                _IncidentStrip(sim: sim, onTap: _openIncident),
                if (sim.coach != null) _Coach(text: sim.coach!, onClose: () => setState(() => sim.coach = null)),
                Expanded(
                  child: sim.call != null
                      ? CallPanel(sim: sim, c: sim.call!)
                      : sim.queue.isNotEmpty
                      ? _Ringing(sim: sim)
                      : _RadioLog(sim: sim, onTap: _openIncident),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
class _TopBar extends StatelessWidget {
  const _TopBar({required this.sim, required this.onPause});
  final Sim sim;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final ending = sim.t >= Sim.end;
    return Container(
      color: panel,
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtClock(sim.t),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ending ? 'Fin de garde : on termine' : 'Garde de nuit · fin 23:00',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: ending ? const Color(0xFFFFAB40) : Colors.white54),
                ),
              ],
            ),
          ),
          _Stat(icon: Icons.star, value: '${sim.totalScore}', color: const Color(0xFFFFD54F)),
          const SizedBox(width: 12),
          _Stat(icon: Icons.favorite, value: '${sim.saved}', color: const Color(0xFFFF5252)),
          const SizedBox(width: 12),
          Badge(
            isLabelVisible: sim.queue.isNotEmpty,
            label: Text('${sim.queue.length}'),
            child: Icon(Icons.phone_in_talk, color: sim.queue.isNotEmpty ? const Color(0xFF69F0AE) : Colors.white30),
          ),
          IconButton(onPressed: onPause, icon: const Icon(Icons.pause_circle_outline)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.color});
  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

// ------------------------------------------------------------
class _IncidentStrip extends StatelessWidget {
  const _IncidentStrip({required this.sim, required this.onTap});
  final Sim sim;
  final void Function(Incident) onTap;

  @override
  Widget build(BuildContext context) {
    final list = sim.activeIncidents;
    if (list.isEmpty) return const SizedBox(height: 4);
    final blink = DateTime.now().millisecondsSinceEpoch % 800 < 400;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = list[i];
          final alert = c.awaiting || c.missing.isNotEmpty;
          final status = c.awaiting
              ? 'À ENGAGER'
              : c.missing.isNotEmpty
              ? 'RENFORT !'
              : c.firstArrival == null
              ? 'En route'
              : 'Sur place';
          return InkWell(
            onTap: () => onTap(c),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: alert && blink ? const Color(0xFF8B1A1A) : const Color(0xFF1B2735),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: alert ? const Color(0xFFFF1744) : Colors.white12),
              ),
              child: Row(
                children: [
                  Icon((c.nature ?? c.sc.nature).icon, size: 16, color: const Color(0xFFFF8A65)),
                  const SizedBox(width: 6),
                  Text(status, style: TextStyle(fontSize: 12, fontWeight: alert ? FontWeight.w800 : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Coach extends StatelessWidget {
  const _Coach({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 2, 8, 4),
    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
    decoration: BoxDecoration(
      color: const Color(0xFF1A2B3D),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF4FC3F7).withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 15,
          backgroundColor: Color(0xFF0277BD),
          child: Text('LG', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Lt Garnier : ',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF81D4FA)),
                ),
                TextSpan(text: text),
              ],
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18), visualDensity: VisualDensity.compact),
      ],
    ),
  );
}

// ------------------------------------------------------------
class _Ringing extends StatelessWidget {
  const _Ringing({required this.sim});
  final Sim sim;

  @override
  Widget build(BuildContext context) {
    final c = sim.queue.first;
    final wait = (sim.t - c.ringAt) / Sim.patience;
    final shake = DateTime.now().millisecondsSinceEpoch % 500 < 250;
    return Container(
      color: panel,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (box.maxHeight - 40).clamp(0.0, double.infinity)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.rotate(
                  angle: shake ? -0.15 : 0.15,
                  child: const Icon(Icons.phone_in_talk, size: 64, color: Color(0xFF69F0AE)),
                ),
                const SizedBox(height: 12),
                Text(
                  sim.queue.length > 1 ? '${sim.queue.length} APPELS EN ATTENTE' : 'APPEL ENTRANT — 18',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  c.isCallback
                      ? 'Le numéro rappelle…'
                      : 'Ligne 1 · ça sonne depuis ${((sim.t - c.ringAt) / 60).floor()} min',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 1 - wait.clamp(0.0, 1.0),
                    minHeight: 6,
                    color: wait > 0.6 ? const Color(0xFFFF5252) : const Color(0xFF69F0AE),
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                    onPressed: sim.pickup,
                    icon: const Icon(Icons.call),
                    label: const Text(
                      'DÉCROCHER',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioLog extends StatelessWidget {
  const _RadioLog({required this.sim, required this.onTap});
  final Sim sim;
  final void Function(Incident) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Icon(Icons.settings_input_antenna, size: 16, color: Color(0xFFFF8A80)),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'RADIO · CANAL OPÉRATIONNEL',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sim.radio.isEmpty
                ? const Center(
                    child: Text('Calme plat… pour l\'instant.', style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    itemCount: sim.radio.length,
                    itemBuilder: (_, i) {
                      final m = sim.radio[i];
                      return InkWell(
                        onTap: m.inc != null ? () => onTap(m.inc!) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${fmtClock(m.t)}  ',
                                  style: const TextStyle(color: Colors.white38),
                                ),
                                TextSpan(
                                  text: '${m.from} : ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: m.alert ? const Color(0xFFFF5252) : const Color(0xFFFFB74D),
                                  ),
                                ),
                                TextSpan(
                                  text: m.text,
                                  style: TextStyle(color: m.alert ? const Color(0xFFFF8A80) : null),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 13.5, height: 1.3),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  Appel en cours
// ------------------------------------------------------------

class CallPanel extends StatefulWidget {
  const CallPanel({super.key, required this.sim, required this.c});
  final Sim sim;
  final Incident c;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> {
  final _scroll = ScrollController();
  int _lines = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (widget.c.lines.length == _lines) return;
    _lines = widget.c.lines.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sim = widget.sim;
    final c = widget.c;
    _autoScroll();
    final qs = sim.questionsFor(c);
    final adv = sim.adviceFor(c);
    final dur = sim.t - (c.pickupAt ?? sim.t);
    return Container(
      color: panel,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            // En-tête de l'appel
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              color: const Color(0xFF16351F),
              child: Row(
                children: [
                  const Icon(Icons.call, color: Color(0xFF69F0AE), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.callerName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(dur / 60).floor()}:${(dur % 60).floor().toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Color(0xFF69F0AE), fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            // Transcription
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                itemCount: c.lines.length,
                itemBuilder: (_, i) => _Bubble(line: c.lines[i]),
              ),
            ),
            // Actions : prioritaires sur la transcription, sans jamais déborder.
            Container(
              constraints: BoxConstraints(
                maxHeight: min(MediaQuery.sizeOf(context).height * 0.26, max(56.0, box.maxHeight - 190)),
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0E161F),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                children: [
                  for (final q in qs)
                    _Action(
                      text: q.ask,
                      icon: Icons.help_outline,
                      color: const Color(0xFF90CAF9),
                      onTap: () => sim.ask(q),
                    ),
                  for (final a in adv)
                    _Action(
                      text: a.say,
                      icon: Icons.record_voice_over,
                      color: const Color(0xFFA5D6A7),
                      onTap: () => sim.advise(a),
                    ),
                  if (qs.isEmpty && adv.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Plus rien à demander. À toi de décider.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                ],
              ),
            ),
            // Décision
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: red),
                        onPressed: c.addressKnown ? () => showDispatch(context, sim, c) : null,
                        icon: const Icon(Icons.local_fire_department),
                        label: Text(
                          !c.addressKnown ? 'Adresse ?' : (c.dispatched ? 'Renforts' : 'ENGAGER'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: PopupMenuButton<String>(
                        onSelected: sim.endCall,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'raccroche', child: Text('📴  Raccrocher')),
                          PopupMenuItem(value: 'r17', child: Text('👮  Transférer au 17 (Police)')),
                          PopupMenuItem(value: 'r15', child: Text('🩺  Transférer au 15 (SAMU)')),
                        ],
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call_end, color: Color(0xFFFF5252)),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Fin d\'appel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.text, required this.icon, required this.color, required this.onTap});
  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(fontSize: 13.5, color: color)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});
  final Line line;

  @override
  Widget build(BuildContext context) {
    if (line.who == Who.info) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
            child: Text(line.text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ),
      );
    }
    final op = line.who == Who.op;
    return Align(
      alignment: op ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: op ? const Color(0xFF1E3A5F) : const Color(0xFF2A2F36),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(op ? 14 : 3),
            bottomRight: Radius.circular(op ? 3 : 14),
          ),
        ),
        child: Text(line.text, style: const TextStyle(fontSize: 14.5, height: 1.3)),
      ),
    );
  }
}
