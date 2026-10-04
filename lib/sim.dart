import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'models.dart';
import 'scenarios_a.dart';
import 'scenarios_b.dart';

// ============================================================
//  Moteur de la garde : appels, véhicules, interventions
// ============================================================

final allScenarios = [...scenariosA(), ...scenariosB()];

/// Tracé de la Loire sur la carte (coordonnées normalisées).
double riverY(double x) => 0.64 + 0.045 * sin(x * 7 + 0.6);

double l1(Offset a, Offset b) => (a.dx - b.dx).abs() + (a.dy - b.dy).abs();

class RadioMsg {
  RadioMsg(this.t, this.from, this.text, {this.inc, this.alert = false});
  final double t;
  final String from;
  final String text;
  final Incident? inc;
  final bool alert;
}

class Sim extends ChangeNotifier {
  Sim({required this.level, required this.operator, this.tutorial = false, int? seed}) : r = Random(seed) {
    _initFleet();
    nextCallAt = start + 40;
  }

  final int level;
  final String operator;
  final bool tutorial;
  final Random r;

  /// Secondes de jeu écoulées par seconde réelle.
  static const timeScale = 30.0;
  static const start = 19 * 3600.0;
  static const end = 23 * 3600.0;
  static const patience = 12 * 60.0;

  double t = start;
  bool paused = false;
  bool over = false;
  late double nextCallAt;

  final vehicles = <Vehicle>[];
  final history = <Incident>[];
  final queue = <Incident>[];
  final radio = <RadioMsg>[];
  Incident? call;
  String? coach;
  final _events = <String>[];
  final _callbacks = <(double, Incident)>[];
  int _id = 0;
  String? _lastScenario;

  // ---------------------------------------------------------- Flotte
  void _initFleet() {
    void add(Base b, VType t, [int n = 1]) => vehicles.add(Vehicle(t, b, n));
    add(casCentre, VType.vsav);
    add(casCentre, VType.vsav, 2);
    add(casCentre, VType.fpt);
    add(casCentre, VType.epa);
    add(casCentre, VType.vtu);
    add(casNord, VType.vsav);
    add(casNord, VType.fpt);
    add(casNord, VType.ccf);
    add(casNord, VType.ccf, 2);
    add(casSud, VType.vsav);
    add(casSud, VType.fpt);
    add(casSud, VType.vsr);
    add(casSud, VType.bls);
    add(hopital, VType.smur);
    add(hopital, VType.smur, 2);
    add(commissariat, VType.police);
    add(commissariat, VType.police, 2);
  }

  double speedOf(Vehicle v) => v.type.partner ? 0.0021 : 0.0018;
  double turnout(Vehicle v) => v.type.partner ? 120 : 75;

  /// Temps estimé (secondes de jeu) pour rejoindre un point.
  double eta(Vehicle v, Offset to) => (v.state == VState.dispo ? turnout(v) : 0) + l1(v.pos, to) / speedOf(v);

  // ---------------------------------------------------------- Boucle
  void tick(double realDt) {
    if (paused || over) return;
    final dt = realDt * timeScale;
    t += dt;
    _spawn();
    _ring();
    _move(dt);
    _progress();
    _checkEnd();
    notifyListeners();
  }

  String? takeEvent() => _events.isEmpty ? null : _events.removeAt(0);

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  // ---------------------------------------------------------- Appels
  void _spawn() {
    for (final cb in List.of(_callbacks)) {
      if (t >= cb.$1) {
        _callbacks.remove(cb);
        _newCall(cb.$2.sc, from: cb.$2);
      }
    }
    if (t >= end || t < nextCallAt) return;
    _newCall(_pickScenario());
    final mean = (tutorial ? 18 : 16 - level * 1.6) * 60;
    nextCallAt = t + mean * (0.55 + r.nextDouble() * 0.9);
  }

  Scenario _pickScenario() {
    if (tutorial && history.isEmpty) {
      return allScenarios.firstWhere((s) => s.id == 'feu_cuisine');
    }
    if (tutorial && history.length == 1) {
      return allScenarios.firstWhere((s) => s.id == 'malaise');
    }
    final pool = allScenarios.where((s) => s.minLevel <= level && s.id != _lastScenario).toList();
    final total = pool.fold<double>(0, (a, s) => a + s.weight);
    var x = r.nextDouble() * total;
    for (final s in pool) {
      x -= s.weight;
      if (x <= 0) return s;
    }
    return pool.last;
  }

  void _newCall(Scenario sc, {Incident? from}) {
    final c = Incident(++_id, sc, t);
    if (from != null) {
      c.v.addAll(from.v);
      c.v.remove('coupe');
      c.loc = from.loc;
      c.address = from.address;
      c.isCallback = true;
      c.transfer = from.transfer;
    } else {
      _place(c);
      sc.setup(c, r);
    }
    c.callerName = sc.caller(c);
    _lastScenario = sc.id;
    queue.add(c);
    history.add(c);
    _events.add('ring');
    if (tutorial && history.length == 1) {
      coach = 'Le téléphone sonne ! Décroche vite : chaque seconde compte.';
    }
  }

  void _place(Incident c) {
    final (p, a) = switch (c.sc.zone) {
      Zone.foret => (Offset(0.05 + r.nextDouble() * 0.18, 0.06 + r.nextDouble() * 0.2), 'Bois de Vauclair'),
      Zone.autoroute => (Offset(0.93, 0.12 + r.nextDouble() * 0.76), 'A71, sortie 12'),
      Zone.riviere => () {
        final x = 0.15 + r.nextDouble() * 0.65;
        return (Offset(x, riverY(x)), 'Quai des Mariniers');
      }(),
      Zone.zi => (Offset(0.08 + r.nextDouble() * 0.2, 0.8 + r.nextDouble() * 0.12), 'ZI des Gravières'),
      Zone.centre => (Offset(0.38 + r.nextDouble() * 0.24, 0.36 + r.nextDouble() * 0.2), _addr()),
      Zone.ville => (_cityPoint(), _addr()),
    };
    c.loc = p;
    c.address = a;
  }

  String _addr() => '${1 + r.nextInt(120)} ${pick(r, rues)}';

  Offset _cityPoint() {
    while (true) {
      final p = Offset(0.1 + r.nextDouble() * 0.74, 0.1 + r.nextDouble() * 0.82);
      if (p.dx < 0.28 && p.dy < 0.3) continue; // forêt
      if (p.dx < 0.32 && p.dy > 0.76) continue; // zone industrielle
      if ((p.dy - riverY(p.dx)).abs() < 0.045) continue; // Loire
      return p;
    }
  }

  void _ring() {
    for (final c in List.of(queue)) {
      if (t - c.ringAt > patience) {
        queue.remove(c);
        c.closedAt = t;
        c.endAction = 'perdu';
        final urgent = c.kind == Kind.urgence;
        c.score = urgent ? 0 : 50;
        c.verdict = "Appel perdu : l'appelant a raccroché";
        c.notes.add('Personne n\'a décroché pendant 12 minutes.');
        if (urgent && (c.sc.critical || c.v['critique'] == true)) {
          c.survived = false;
        }
        _radio('CTA', 'Appel perdu après 12 minutes de sonnerie.', alert: true);
      }
    }
  }

  void pickup() {
    if (call != null || queue.isEmpty) return;
    final c = queue.removeAt(0);
    call = c;
    c.pickupAt = t;
    c.callOpen = true;
    if (c.transfer != null) c.lines.add(Line(Who.info, c.transfer!));
    c.lines.add(Line(Who.op, 'Pompiers, j\'écoute.'));
    for (final l in c.sc.opening(c)) {
      c.lines.add(Line(Who.caller, l));
    }
    if (tutorial && history.length <= 2) {
      coach = 'Pose tes questions. Commence par l\'adresse : sans elle, impossible d\'envoyer qui que ce soit.';
    }
    notifyListeners();
  }

  List<Q> questionsFor(Incident c) => c.sc.questions
      .where(
        (q) => !c.asked.contains(q.key) && (q.after == null || c.asked.contains(q.after)) && (q.when?.call(c) ?? true),
      )
      .toList();

  List<Advice> adviceFor(Incident c) => c.sc.advice
      .where(
        (a) =>
            !c.advised.contains(a.key) &&
            (a.after == null || c.asked.contains(a.after) || c.advised.contains(a.after)) &&
            (a.when?.call(c) ?? true),
      )
      .toList();

  void ask(Q q) {
    final c = call;
    if (c == null) return;
    c.asked.add(q.key);
    c.lines.add(Line(Who.op, q.ask));
    c.lines.add(Line(Who.caller, q.answer(c)));
    if (q.key == 'adresse') {
      c.addressKnown = true;
      c.lines.add(Line(Who.info, '📍 Localisé : ${c.address}'));
      if (tutorial && history.length <= 2) {
        coach =
            'Adresse trouvée ! Appuie sur « Engager » pour envoyer les secours. Tu pourras continuer à parler ensuite.';
      }
    }
    notifyListeners();
  }

  void advise(Advice a) {
    final c = call;
    if (c == null) return;
    c.advised.add(a.key);
    c.adviceScore += a.effect;
    a.apply?.call(c);
    c.lines.add(Line(Who.op, a.say));
    c.lines.add(Line(Who.caller, a.reply(c)));
    if (c.v['coupe'] == true) {
      c.lines.add(Line(Who.info, '📵 La communication a été coupée.'));
      _endCall('coupe');
    }
    notifyListeners();
  }

  /// action : raccroche, r17, r15
  void endCall(String action) {
    if (call == null) return;
    _endCall(action);
    notifyListeners();
  }

  void _endCall(String action) {
    final c = call!;
    call = null;
    c.callOpen = false;
    c.endAction = action;
    if (tutorial && c.dispatched) {
      coach = 'Suis tes véhicules sur la carte. Les équipes te parlent à la radio. Touche une intervention pour voir où elle en est.';
    }
    if (c.dispatched) return;
    if (action == 'coupe' && c.addressKnown && c.kind == Kind.urgence) {
      c.awaiting = true;
      c.awaitSince = t;
      _radio('CTA', 'Communication coupée — ${c.address}. Il faut engager des moyens !', inc: c, alert: true);
      return;
    }
    _closeWithoutDispatch(c);
  }

  void _closeWithoutDispatch(Incident c) {
    c.closedAt = t;
    final dur = (t - (c.pickupAt ?? t)) / 60;
    final a = c.endAction;
    switch (c.kind) {
      case Kind.canular:
        if (a == 'raccroche' || a == 'coupe') {
          c.score = (100 - max(0, dur - 4) * 6).round().clamp(60, 100);
          c.verdict = 'Canular démasqué';
        } else {
          c.score = 60;
          c.verdict = 'Canular transféré pour rien';
        }
      case Kind.police:
        if (a == 'r17') {
          c.score = 100;
          c.verdict = 'Bien réorienté vers la police (17)';
        } else if (c.v['vrai'] == true) {
          c.score = 0;
          c.verdict = 'Une femme en danger… et tu as raccroché';
          c.notes.add('« Une pizza » : un code connu des victimes de violences.');
        } else {
          c.score = 35;
          c.verdict = 'Il fallait réorienter vers le 17';
        }
      case Kind.medecin:
        c.score = a == 'r15' ? 100 : 35;
        c.verdict = a == 'r15' ? 'Bien réorienté vers le 15 (médecin de garde)' : 'Il fallait réorienter vers le 15';
      case Kind.urgence:
        if (a == 'r15' || a == 'r17') {
          c.score = 15;
          c.verdict = 'Mauvaise orientation, appel retransféré';
          c.transfer = '↪ Retransféré par le ${a == 'r15' ? '15' : '17'} : « C\'est pour vous, les pompiers ! »';
          _callbacks.add((t + 60, c));
        } else if (c.sc.id == 'enfant_maman' && !c.isCallback) {
          c.score = 0;
          c.verdict = 'Tu as raccroché sur un vrai appel !';
          c.notes.add('Un enfant qui appelle n\'est pas forcément un canular.');
          _callbacks.add((t + 90, c));
        } else {
          c.score = 0;
          c.verdict = 'Urgence non traitée !';
          if (c.sc.critical || c.v['critique'] == true) c.survived = false;
        }
    }
  }

  // ---------------------------------------------------------- Engagement
  List<Vehicle> proposal(Incident c, Nature n) {
    final res = <Vehicle>[];
    n.proposal.forEach((type, count) {
      final cands = vehicles.where((v) => v.type == type && v.available && !res.contains(v)).toList()
        ..sort((a, b) => eta(a, c.loc).compareTo(eta(b, c.loc)));
      res.addAll(cands.take(count));
    });
    return res;
  }

  /// Emprunte un véhicule à un centre voisin quand plus rien n'est dispo.
  Vehicle borrow(VType type) {
    final n = vehicles.where((v) => v.home == casVoisin && v.type == type).length;
    final v = Vehicle(type, casVoisin, n + 1);
    vehicles.add(v);
    return v;
  }

  void engage(Incident c, List<Vehicle> vs, {Nature? nature}) {
    final sent = <String>[];
    for (final v in vs) {
      if (!v.available) continue;
      v.inc = c;
      v.state = v.state == VState.dispo ? VState.depart : VState.route;
      v.timer = turnout(v);
      v.path = [Offset(c.loc.dx, v.pos.dy), c.loc];
      c.vehicles.add(v);
      sent.add(v.name);
    }
    if (sent.isEmpty) return;
    c.nature ??= nature;
    if (!c.dispatched) {
      c.dispatched = true;
      c.dispatchAt = t;
    }
    c.awaiting = false;
    if (c.firstArrival != null) c.extraSent = true;
    _radio('CTA', 'Départ ${sent.join(', ')} → ${c.address}', inc: c);
    if (c.callOpen) {
      c.lines.add(Line(Who.info, '🚒 Engagés : ${sent.join(', ')}'));
      c.lines.add(Line(Who.op, 'Les secours sont en route. Restez en ligne avec moi.'));
      if (tutorial && history.length <= 2) {
        coach = 'Les secours roulent ! Donne un bon conseil à l\'appelant, puis raccroche.';
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- Véhicules
  void _move(double dt) {
    for (final v in vehicles) {
      switch (v.state) {
        case VState.depart:
          v.timer -= dt;
          if (v.timer <= 0) v.state = VState.route;
        case VState.route || VState.transport || VState.retour:
          if (_advance(v, dt)) _arrived(v);
        case VState.hopital:
          v.timer -= dt;
          if (v.timer <= 0) _goHome(v);
        case VState.dispo || VState.surPlace:
          break;
      }
    }
  }

  bool _advance(Vehicle v, double dt) {
    var d = speedOf(v) * dt;
    while (d > 0 && v.path.isNotEmpty) {
      final target = v.path.first;
      final delta = target - v.pos;
      final len = delta.distance;
      if (len <= d) {
        v.pos = target;
        v.path.removeAt(0);
        d -= len;
      } else {
        v.pos += delta / len * d;
        d = 0;
      }
    }
    return v.path.isEmpty;
  }

  void _goHome(Vehicle v) {
    v.state = VState.retour;
    v.inc = null;
    v.path = [Offset(v.pos.dx, v.home.pos.dy), v.home.pos];
  }

  void _arrived(Vehicle v) {
    final c = v.inc;
    switch (v.state) {
      case VState.retour:
        v.state = VState.dispo;
        v.pos = v.home.pos;
      case VState.transport:
        v.state = VState.hopital;
        v.timer = 8 * 60;
        _radio(v.name, 'Arrivés au CH, victime confiée aux urgences.');
      case VState.route:
        if (c == null || c.done) {
          _goHome(v);
          return;
        }
        v.state = VState.surPlace;
        if (c.firstArrival == null) {
          c.firstArrival = t;
          _radio(v.name, 'Sur les lieux. ${c.sc.ambiance(c)}', inc: c);
        } else {
          _radio(v.name, 'Sur les lieux.', inc: c);
        }
        final need = c.needs[v.type] ?? 0;
        final here = c.vehicles.where((x) => x.type == v.type && x.state == VState.surPlace).length;
        if (here > need) {
          c.extras++;
          _goHome(v);
          _radio(v.name, 'Pas besoin de nous ici, on rentre.', inc: c);
        }
      default:
        break;
    }
  }

  // ---------------------------------------------------------- Interventions
  Map<VType, int> _missing(Incident c, bool Function(Vehicle) counted) {
    final res = <VType, int>{};
    c.needs.forEach((type, n) {
      final have = c.vehicles.where((v) => v.type == type && v.inc == c && counted(v)).length;
      if (have < n) res[type] = n - have;
    });
    return res;
  }

  void _progress() {
    for (final c in history) {
      if (c.awaiting && t - c.awaitSince > 6 * 60) {
        c.awaiting = false;
        c.endAction = 'coupe';
        c.closedAt = t;
        c.score = 0;
        c.verdict = 'Urgence non traitée !';
        if (c.sc.critical || c.v['critique'] == true) c.survived = false;
      }
      if (!c.active) continue;
      if (c.firstArrival != null && c.needsMetAt == null) {
        final onScene = _missing(c, (v) => v.state == VState.surPlace);
        if (onScene.isEmpty) {
          c.missing = {};
          c.needsMetAt = t;
          c.workEnd = t + c.sc.work * 60;
        } else {
          final engaged = _missing(
            c,
            (v) => v.state == VState.depart || v.state == VState.route || v.state == VState.surPlace,
          );
          c.missing = engaged;
          if (engaged.isNotEmpty && !c.renfortAsked) {
            c.renfortAsked = true;
            final txt = engaged.entries.map((e) => '${e.value} ${e.key.code}').join(', ');
            final from =
                c.vehicles.where((v) => v.inc == c && v.state == VState.surPlace).firstOrNull?.name ?? 'Chef de groupe';
            _radio(from, 'DEMANDE DE RENFORT : $txt !', inc: c, alert: true);
            _events.add('alert');
            if (tutorial || history.length < 6) {
              coach = 'Demande de renfort ! Touche l\'intervention clignotante pour envoyer ce qui manque.';
            }
          }
          if (t - c.firstArrival! > 25 * 60) {
            c.degraded = true;
            c.needsMetAt = t;
            c.workEnd = t + c.sc.work * 60;
          }
        }
      }
      if (c.workEnd != null && t >= c.workEnd!) _resolve(c);
    }
  }

  void _resolve(Incident c) {
    c.done = true;
    c.closedAt = t;
    c.missing = {};
    final k = c.kind;
    var good = true;
    if (k == Kind.canular || (k != Kind.urgence && c.needs.isEmpty)) {
      c.score = 15;
      c.verdict = switch (k) {
        Kind.canular => 'Moyens engagés pour un canular',
        Kind.police => 'Il fallait réorienter vers le 17',
        _ => 'Il fallait réorienter vers le 15',
      };
    } else {
      final target = (c.v['target'] as num?)?.toDouble() ?? c.sc.target;
      final tFull = ((c.needsMetAt ?? t) - c.ringAt) / 60;
      final tScore = tFull <= target ? 1.0 : (1 - (tFull - target) / (target * 1.5)).clamp(0.0, 1.0);
      final adequacy = c.degraded ? 0.0 : ((c.renfortAsked ? 0.5 : 1.0) - 0.15 * c.extras).clamp(0.0, 1.0);
      final adv = (0.5 + 0.25 * c.adviceScore).clamp(0.0, 1.0);
      var score = 35 + 30 * tScore + 20 * adequacy + 15 * adv;
      if (c.sc.critical || c.v['critique'] == true) {
        var q = 0.55 * tScore + 0.2 * adequacy + 0.25 * adv;
        for (final b in ['mce', 'bouee', 'stylo', 'sortis', 'porte']) {
          if (c.v[b] == true) q += 0.15;
        }
        if (c.v['daeOk'] == true) q += 0.25;
        if (c.v['aggrave'] == true) q -= 0.15;
        q += (r.nextDouble() - 0.5) * 0.12;
        good = q >= 0.5;
        c.survived = good;
        if (!good) score -= 25;
      } else {
        good = tScore > 0.3 && !c.degraded;
      }
      c.score = score.round().clamp(0, 100);
      c.verdict = c.score >= 85
          ? 'Excellent'
          : c.score >= 65
          ? 'Bien'
          : c.score >= 45
          ? 'Moyen'
          : 'Insuffisant';
      c.notes.add('Moyens complets en ${tFull.round()} min (objectif ${target.round()} min)');
      if (c.renfortAsked) c.notes.add('Renfort demandé sur place');
      if (c.extras > 0) {
        c.notes.add('${c.extras} moyen${c.extras > 1 ? 's' : ''} engagé${c.extras > 1 ? 's' : ''} pour rien');
      }
      if (c.adviceScore > 0) c.notes.add('Bons conseils à l\'appelant');
      if (c.adviceScore < 0) c.notes.add('Conseils dangereux donnés');
    }
    final onScene = c.vehicles.where((v) => v.inc == c && v.state == VState.surPlace).toList();
    final reporter = onScene.isNotEmpty ? onScene.first.name : 'Chef de groupe';
    _radio(reporter, c.sc.report(c, good), inc: c, alert: c.survived == false);
    var transported = false;
    for (final v in onScene) {
      if (!transported && v.type == VType.vsav && c.survived != false && k == Kind.urgence) {
        transported = true;
        v.state = VState.transport;
        v.path = [Offset(v.pos.dx, hopital.pos.dy), hopital.pos];
      } else {
        _goHome(v);
      }
    }
  }

  void _checkEnd() {
    if (t < end) return;
    final busy =
        queue.isNotEmpty || call != null || _callbacks.isNotEmpty || history.any((c) => c.active || c.awaiting);
    if (!busy || t > end + 3600) {
      for (final c in history.where((c) => c.active)) {
        _resolve(c);
      }
      over = true;
    }
  }

  void _radio(String from, String text, {Incident? inc, bool alert = false}) {
    radio.insert(0, RadioMsg(t, from, text, inc: inc, alert: alert));
    if (radio.length > 80) radio.removeLast();
    inc?.radio.add('${fmtClock(t)} · $from : $text');
  }

  // ---------------------------------------------------------- Bilan
  List<Incident> get closedCalls => history.where((c) => c.closed).toList();
  int get totalScore => closedCalls.fold(0, (a, c) => a + c.score);
  int get saved => history.where((c) => c.survived == true).length;
  int get lost => history.where((c) => c.survived == false).length;
  List<Incident> get activeIncidents => history.where((c) => c.active || c.awaiting).toList();
}
