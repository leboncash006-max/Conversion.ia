import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------
//  Questionnaire d'orientation (modifiable : ajoute/retire des lignes)
// ---------------------------------------------------------------

class Question {
  final String text;
  final bool eco; // true = axe économique, false = axe sociétal
  final int sign; // +1 : être d'accord pousse vers droite / autoritaire
  const Question(this.text, this.eco, this.sign);
}

const questions = <Question>[
  // Économie : gauche (-) <-> droite (+)
  Question('L\'État devrait augmenter les impôts des plus riches pour financer les services publics.', true, -1),
  Question('Le marché libre régule mieux l\'économie que l\'intervention de l\'État.', true, 1),
  Question('Les grands secteurs stratégiques (énergie, transports) devraient être publics.', true, -1),
  Question('Le salaire minimum devrait être fortement augmenté.', true, -1),
  Question('Il faut réduire le nombre de fonctionnaires et les dépenses publiques.', true, 1),
  Question('Les syndicats sont indispensables pour protéger les travailleurs.', true, -1),
  Question('L\'héritage ne devrait pas être taxé.', true, 1),
  Question('La santé et l\'éducation devraient pouvoir être en partie privées.', true, 1),
  Question('Réduire le temps de travail est une bonne chose pour la société.', true, -1),
  Question('Les aides sociales encouragent trop souvent l\'assistanat.', true, 1),
  // Société : libertaire (-) <-> autoritaire (+)
  Question('Les peines de prison devraient être beaucoup plus sévères.', false, 1),
  Question('L\'immigration devrait être strictement limitée.', false, 1),
  Question('Chacun doit être libre de ses choix de vie, même s\'ils choquent la majorité.', false, -1),
  Question('L\'État doit pouvoir surveiller les communications pour lutter contre le terrorisme.', false, 1),
  Question('La tradition et l\'identité nationale doivent être protégées avant tout.', false, 1),
  Question('Les drogues douces devraient être légalisées.', false, -1),
  Question('L\'armée et l\'ordre devraient avoir plus de place dans la société.', false, 1),
  Question('Le mariage et l\'adoption pour tous les couples sont de bonnes choses.', false, -1),
  Question('La liberté d\'expression doit être quasi absolue, même pour les propos choquants.', false, -1),
  Question('La désobéissance civile est parfois légitime.', false, -1),
];

const answerLabels = [
  'Pas du tout d\'accord',
  'Plutôt pas d\'accord',
  'Neutre',
  'Plutôt d\'accord',
  'Tout à fait d\'accord',
];

// ---------------------------------------------------------------
//  Orientations (e = économie, s = société, entre -1 et 1)
// ---------------------------------------------------------------

class Leaning {
  final String name;
  final double e, s;
  const Leaning(this.name, this.e, this.s);
}

const leanings = <Leaning>[
  Leaning('Centriste', 0, 0),
  Leaning('Gauche libertaire', -0.7, -0.7),
  Leaning('Gauche sociale-étatiste', -0.7, 0.5),
  Leaning('Écologiste', -0.5, -0.3),
  Leaning('Libéral', 0.7, -0.6),
  Leaning('Conservateur', 0.7, 0.7),
  Leaning('Souverainiste', 0.1, 0.8),
  Leaning('Libertarien', 1, -1),
];

Leaning nearestLeaning(double e, double s) {
  Leaning best = leanings.first;
  double bd = double.infinity;
  for (final l in leanings) {
    final d = pow(l.e - e, 2) + pow(l.s - s, 2);
    if (d < bd) {
      bd = d.toDouble();
      best = l;
    }
  }
  return best;
}

String describe(double e, double s) {
  final d = sqrt(e * e + s * s);
  final name = nearestLeaning(e, s).name;
  if (d < 0.15) return name;
  if (d < 0.45) return '$name (modéré)';
  if (d < 0.8) return name;
  return '$name (radical)';
}

// ---------------------------------------------------------------
//  Modèles
// ---------------------------------------------------------------

class Profile {
  String party;
  List<int> answers; // -2 .. 2, même ordre que `questions`
  Profile(this.party, this.answers);

  double _axis(bool eco) {
    double sum = 0, max = 0;
    for (var i = 0; i < questions.length && i < answers.length; i++) {
      if (questions[i].eco == eco) {
        sum += questions[i].sign * answers[i];
        max += 2;
      }
    }
    return max == 0 ? 0 : sum / max;
  }

  double get e => _axis(true);
  double get s => _axis(false);
  String get label => describe(e, s);

  Map<String, dynamic> toJson() => {'party': party, 'answers': answers};
  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(j['party'] ?? 'Mon parti', List<int>.from(j['answers'] ?? []));
}

class Settings {
  String apiKey;
  String model;
  String strict; // consignes strictes de l'adversaire
  String extra; // instructions supplémentaires
  String audience; // consignes du public
  Settings({
    this.apiKey = '',
    this.model = 'gemini-flash-lite-latest',
    this.strict = '',
    this.extra = '',
    this.audience = '',
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'model': model,
        'strict': strict,
        'extra': extra,
        'audience': audience,
      };
  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        apiKey: j['apiKey'] ?? '',
        model: j['model'] ?? 'gemini-flash-lite-latest',
        strict: j['strict'] ?? '',
        extra: j['extra'] ?? '',
        audience: j['audience'] ?? '',
      );
}

class Msg {
  final String role; // 'me' ou 'ai'
  final String text;
  int? shift; // réaction du public à l'échange (sur le message de l'IA)
  String? comment;
  Msg(this.role, this.text, {this.shift, this.comment});

  Map<String, dynamic> toJson() =>
      {'role': role, 'text': text, 'shift': shift, 'comment': comment};
  factory Msg.fromJson(Map<String, dynamic> j) =>
      Msg(j['role'], j['text'], shift: j['shift'], comment: j['comment']);
}

class Debate {
  final String id;
  final String topic;
  final String opponentName;
  final String opponentLeaning;
  final DateTime date;
  int audience; // 0..100, 100 = tout le public est avec moi
  bool finished;
  final List<Msg> messages;

  Debate({
    required this.id,
    required this.topic,
    required this.opponentName,
    required this.opponentLeaning,
    DateTime? date,
    this.audience = 50,
    this.finished = false,
    List<Msg>? messages,
  })  : date = date ?? DateTime.now(),
        messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'opponentName': opponentName,
        'opponentLeaning': opponentLeaning,
        'date': date.toIso8601String(),
        'audience': audience,
        'finished': finished,
        'messages': messages.map((m) => m.toJson()).toList(),
      };
  factory Debate.fromJson(Map<String, dynamic> j) => Debate(
        id: j['id'],
        topic: j['topic'],
        opponentName: j['opponentName'],
        opponentLeaning: j['opponentLeaning'],
        date: DateTime.tryParse(j['date'] ?? ''),
        audience: j['audience'] ?? 50,
        finished: j['finished'] ?? false,
        messages: (j['messages'] as List? ?? [])
            .map((m) => Msg.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

// ---------------------------------------------------------------
//  Sauvegarde locale
// ---------------------------------------------------------------

class Store {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static Profile? get profile {
    final s = _p.getString('profile');
    return s == null ? null : Profile.fromJson(jsonDecode(s));
  }

  static Future<void> saveProfile(Profile p) =>
      _p.setString('profile', jsonEncode(p.toJson()));

  static Settings get settings {
    final s = _p.getString('settings');
    return s == null ? Settings() : Settings.fromJson(jsonDecode(s));
  }

  static Future<void> saveSettings(Settings s) =>
      _p.setString('settings', jsonEncode(s.toJson()));

  static List<Debate> get debates {
    final s = _p.getString('debates');
    if (s == null) return [];
    return (jsonDecode(s) as List)
        .map((d) => Debate.fromJson(Map<String, dynamic>.from(d)))
        .toList();
  }

  static Future<void> saveDebate(Debate d) {
    final all = debates;
    final i = all.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      all[i] = d;
    } else {
      all.insert(0, d);
    }
    return _p.setString('debates', jsonEncode(all.map((x) => x.toJson()).toList()));
  }

  static Future<void> deleteDebate(String id) {
    final all = debates..removeWhere((d) => d.id == id);
    return _p.setString('debates', jsonEncode(all.map((x) => x.toJson()).toList()));
  }
}
