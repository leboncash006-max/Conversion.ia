import 'dart:math';

import 'package:flutter/material.dart';

// ============================================================
//  Modèles : véhicules, natures d'intervention, appels, profil
// ============================================================

enum VType { vsav, fpt, epa, vsr, ccf, vtu, bls, smur, police }

extension VTypeInfo on VType {
  String get code => switch (this) {
    VType.vsav => 'VSAV',
    VType.fpt => 'FPT',
    VType.epa => 'EPA',
    VType.vsr => 'VSR',
    VType.ccf => 'CCF',
    VType.vtu => 'VTU',
    VType.bls => 'BLS',
    VType.smur => 'SMUR',
    VType.police => 'POLICE',
  };

  String get desc => switch (this) {
    VType.vsav => 'Ambulance pompier · secours à personne',
    VType.fpt => 'Fourgon pompe-tonne · incendie',
    VType.epa => 'Grande échelle · hauteurs, sauvetages',
    VType.vsr => 'Secours routier · désincarcération',
    VType.ccf => 'Camion feux de forêt',
    VType.vtu => 'Tous usages · eau, animaux, guêpes',
    VType.bls => 'Bateau · sauvetage aquatique',
    VType.smur => 'Médecin urgentiste (via le 15)',
    VType.police => 'Police nationale (via le 17)',
  };

  Color get color => switch (this) {
    VType.vsav => const Color(0xFFFFB300),
    VType.fpt => const Color(0xFFE53935),
    VType.epa => const Color(0xFFFF7043),
    VType.vsr => const Color(0xFF8E24AA),
    VType.ccf => const Color(0xFF43A047),
    VType.vtu => const Color(0xFF29B6F6),
    VType.bls => const Color(0xFF26C6DA),
    VType.smur => const Color(0xFFF5F5F5),
    VType.police => const Color(0xFF3F51B5),
  };

  bool get partner => this == VType.smur || this == VType.police;
}

enum Nature {
  feuCuisine,
  feuHabitation,
  feuForet,
  feuIndustriel,
  malaise,
  acr,
  blesse,
  avp,
  noyade,
  intoxication,
  fuiteGaz,
  inondation,
  animal,
  personneBloquee,
}

extension NatureInfo on Nature {
  String get label => switch (this) {
    Nature.feuCuisine => 'Petit feu (cuisine, poubelle)',
    Nature.feuHabitation => 'Feu d\'habitation',
    Nature.feuForet => 'Feu de forêt / végétation',
    Nature.feuIndustriel => 'Feu industriel',
    Nature.malaise => 'Malaise',
    Nature.acr => 'Arrêt cardio-respiratoire',
    Nature.blesse => 'Personne blessée / chute',
    Nature.avp => 'Accident de la route',
    Nature.noyade => 'Noyade',
    Nature.intoxication => 'Intoxication (CO, fumées)',
    Nature.fuiteGaz => 'Fuite de gaz',
    Nature.inondation => 'Inondation / fuite d\'eau',
    Nature.animal => 'Animal / insectes',
    Nature.personneBloquee => 'Personne bloquée',
  };

  IconData get icon => switch (this) {
    Nature.feuCuisine => Icons.outdoor_grill,
    Nature.feuHabitation => Icons.local_fire_department,
    Nature.feuForet => Icons.forest,
    Nature.feuIndustriel => Icons.factory,
    Nature.malaise => Icons.airline_seat_flat,
    Nature.acr => Icons.monitor_heart,
    Nature.blesse => Icons.personal_injury,
    Nature.avp => Icons.car_crash,
    Nature.noyade => Icons.pool,
    Nature.intoxication => Icons.masks,
    Nature.fuiteGaz => Icons.warning_amber,
    Nature.inondation => Icons.water_damage,
    Nature.animal => Icons.pets,
    Nature.personneBloquee => Icons.elevator,
  };

  /// Départ type proposé par le logiciel du central.
  Map<VType, int> get proposal => switch (this) {
    Nature.feuCuisine => {VType.fpt: 1},
    Nature.feuHabitation => {VType.fpt: 1, VType.epa: 1, VType.vsav: 1},
    Nature.feuForet => {VType.ccf: 1, VType.fpt: 1},
    Nature.feuIndustriel => {VType.fpt: 2, VType.epa: 1, VType.vsav: 1},
    Nature.malaise => {VType.vsav: 1},
    Nature.acr => {VType.vsav: 1, VType.smur: 1},
    Nature.blesse => {VType.vsav: 1},
    Nature.avp => {VType.vsr: 1, VType.vsav: 1, VType.fpt: 1},
    Nature.noyade => {VType.bls: 1, VType.vsav: 1, VType.smur: 1},
    Nature.intoxication => {VType.fpt: 1, VType.vsav: 1},
    Nature.fuiteGaz => {VType.fpt: 1},
    Nature.inondation => {VType.vtu: 1},
    Nature.animal => {VType.vtu: 1},
    Nature.personneBloquee => {VType.vtu: 1},
  };
}

/// Ce qu'il fallait faire de l'appel.
enum Kind { urgence, canular, police, medecin }

enum Zone { ville, centre, foret, autoroute, riviere, zi }

class Base {
  const Base(this.name, this.short, this.pos);
  final String name;
  final String short;
  final Offset pos; // coordonnées normalisées 0..1
}

const casCentre = Base('CIS Centre', 'Centre', Offset(0.47, 0.47));
const casNord = Base('CIS Nord', 'Nord', Offset(0.36, 0.17));
const casSud = Base('CIS Sud', 'Sud', Offset(0.7, 0.8));
const hopital = Base('Centre hospitalier', 'CH', Offset(0.64, 0.36));
const commissariat = Base('Commissariat', 'Comico', Offset(0.3, 0.5));
const casVoisin = Base('Centre voisin', 'Ext.', Offset(0.97, 0.03));

enum VState { dispo, depart, route, surPlace, transport, hopital, retour }

extension VStateInfo on VState {
  String get label => switch (this) {
    VState.dispo => 'Disponible',
    VState.depart => 'Départ',
    VState.route => 'En route',
    VState.surPlace => 'Sur les lieux',
    VState.transport => 'Transport CH',
    VState.hopital => 'Au CH',
    VState.retour => 'Retour',
  };
}

class Vehicle {
  Vehicle(this.type, this.home, this.num) : pos = home.pos;
  final VType type;
  final Base home;
  final int num;
  Offset pos;
  VState state = VState.dispo;
  Incident? inc;
  List<Offset> path = [];
  double timer = 0;

  String get name => '${type.code} ${home.short}${num > 1 ? ' $num' : ''}';

  bool get available => state == VState.dispo || state == VState.retour;
}

/// Une ligne du dialogue téléphonique.
class Line {
  Line(this.who, this.text);
  final Who who;
  final String text;
}

enum Who { op, caller, info }

/// Une question que l'opérateur peut poser.
class Q {
  Q(this.key, this.ask, this.answer, {this.after, this.when});
  final String key;
  final String ask;
  final String Function(Incident c) answer;
  final String? after;
  final bool Function(Incident c)? when;
}

/// Un conseil donné à l'appelant. effect : +1 bon, -1 mauvais, -2 grave.
class Advice {
  Advice(this.key, this.say, this.reply, this.effect, {this.after, this.when, this.apply});
  final String key;
  final String say;
  final String Function(Incident c) reply;
  final int effect;
  final String? after;
  final bool Function(Incident c)? when;
  final void Function(Incident c)? apply;
}

class Scenario {
  Scenario({
    required this.id,
    required this.nature,
    required this.zone,
    required this.setup,
    required this.caller,
    required this.opening,
    required this.questions,
    this.advice = const [],
    required this.needs,
    this.kind,
    this.minLevel = 0,
    this.weight = 1,
    this.target = 10,
    this.critical = false,
    this.work = 20,
    this.transport = false,
    required this.ambiance,
    required this.report,
    this.whatHappens,
    this.title,
  });

  final String id;
  final Nature nature;
  final Zone zone;
  final void Function(Incident c, Random r) setup;
  final String Function(Incident c) caller;
  final List<String> Function(Incident c) opening;
  final List<Q> questions;
  final List<Advice> advice;
  final Map<VType, int> Function(Incident c) needs;
  final Kind Function(Incident c)? kind;
  final int minLevel;
  final double weight;

  /// Délai cible d'arrivée des secours, en minutes depuis la sonnerie.
  final double target;

  /// Une vie est en jeu.
  final bool critical;

  /// Durée du travail sur place, en minutes.
  final double work;

  /// Une victime est transportée au CH.
  final bool transport;
  final String Function(Incident c) ambiance;
  final String Function(Incident c, bool good) report;

  /// Réponse à « Que se passe-t-il exactement ? » si différente de l'ouverture.
  final String Function(Incident c)? whatHappens;

  /// Ce qu'était vraiment l'appel (affiché au débrief).
  final String Function(Incident c)? title;
}

class Incident {
  Incident(this.id, this.sc, this.ringAt);
  final int id;
  final Scenario sc;
  final double ringAt;
  final v = <String, dynamic>{};
  late Offset loc;
  late String address;
  late String callerName;

  double? pickupAt;
  double? closedAt;
  final lines = <Line>[];
  final asked = <String>{};
  final advised = <String>{};
  int adviceScore = 0;
  bool addressKnown = false;
  bool dispatched = false;
  bool callOpen = false;
  bool isCallback = false;
  Nature? nature;
  String? endAction;
  final vehicles = <Vehicle>[];
  final radio = <String>[];

  double? firstArrival;
  double? needsMetAt;
  double? workEnd;
  double? waitingSince;
  bool renfortAsked = false;
  bool done = false;
  bool extraSent = false;
  int extras = 0;

  double? dispatchAt;
  bool awaiting = false;
  double awaitSince = 0;
  bool degraded = false;
  String? transfer;
  Map<VType, int> missing = {};

  int score = 0;
  String verdict = '';
  final notes = <String>[];
  bool? survived;
  bool get closed => closedAt != null;

  Kind get kind => sc.kind?.call(this) ?? Kind.urgence;
  bool get vf => v['vf'] == true; // victime de sexe féminin
  String g(String m, String f) => vf ? f : m;
  String get prenom => v['prenom'] as String? ?? '';
  int get victims => v['victimes'] as int? ?? 1;

  Map<VType, int> get needs => sc.needs(this);

  String get shortLabel => (nature ?? sc.nature).label;
  String get title => sc.title?.call(this) ?? sc.nature.label;

  bool get active => dispatched && !done;
}

// ------------------------------------------------------------
//  Profil et grades
// ------------------------------------------------------------

class Grade {
  const Grade(this.name, this.xp);
  final String name;
  final int xp;
}

const grades = [
  Grade('Opérateur stagiaire', 0),
  Grade('Opérateur', 400),
  Grade('Opérateur confirmé', 1200),
  Grade('Chef de salle adjoint', 2600),
  Grade('Chef de salle', 4500),
  Grade('Officier CODIS', 7500),
];

class Profile {
  String name = '';
  int xp = 0;
  int gardes = 0;
  int appels = 0;
  int vies = 0;
  int deces = 0;
  int best = 0;

  int get level {
    var l = 0;
    for (var i = 0; i < grades.length; i++) {
      if (xp >= grades[i].xp) l = i;
    }
    return l;
  }

  Grade get grade => grades[level];
  Grade? get next => level + 1 < grades.length ? grades[level + 1] : null;

  double get progress {
    final n = next;
    if (n == null) return 1;
    return ((xp - grade.xp) / (n.xp - grade.xp)).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'xp': xp,
    'gardes': gardes,
    'appels': appels,
    'vies': vies,
    'deces': deces,
    'best': best,
  };

  void load(Map<String, dynamic> j) {
    name = j['name'] as String? ?? '';
    xp = (j['xp'] as num?)?.toInt() ?? 0;
    gardes = (j['gardes'] as num?)?.toInt() ?? 0;
    appels = (j['appels'] as num?)?.toInt() ?? 0;
    vies = (j['vies'] as num?)?.toInt() ?? 0;
    deces = (j['deces'] as num?)?.toInt() ?? 0;
    best = (j['best'] as num?)?.toInt() ?? 0;
  }
}

// ------------------------------------------------------------
//  Petits utilitaires
// ------------------------------------------------------------

T pick<T>(Random r, List<T> l) => l[r.nextInt(l.length)];

const prenomsH = [
  'Karim',
  'Julien',
  'Marc',
  'Thomas',
  'Mehdi',
  'Lucas',
  'Patrick',
  'Antoine',
  'Yanis',
  'Bernard',
  'Hugo',
  'Sofiane',
  'Gérard',
  'Kevin',
];
const prenomsF = [
  'Sarah',
  'Julie',
  'Nadia',
  'Camille',
  'Monique',
  'Inès',
  'Claire',
  'Fatou',
  'Léa',
  'Martine',
  'Emma',
  'Sandrine',
  'Chloé',
  'Yasmine',
];
const noms = [
  'Martin',
  'Bernard',
  'Lefèvre',
  'Moreau',
  'Garcia',
  'Benali',
  'Roux',
  'Fournier',
  'Girard',
  'Mercier',
  'Diallo',
  'Lambert',
  'Bonnet',
  'Perrin',
];
const rues = [
  'rue Victor Hugo',
  'avenue Jean Jaurès',
  'rue de la République',
  'boulevard Gambetta',
  'rue Pasteur',
  'impasse des Lilas',
  'rue des Écoles',
  'allée des Peupliers',
  'rue du Moulin',
  'rue Émile Zola',
  'chemin des Vignes',
  'rue de la Paix',
  'avenue de Verdun',
  'rue des Tanneurs',
  'place du Marché',
];

String fmtClock(double s) {
  final m = (s / 60).floor();
  final h = (m ~/ 60) % 24;
  return '${h.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}
