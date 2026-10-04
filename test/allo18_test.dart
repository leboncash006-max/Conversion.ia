import 'package:allo18/game_screen.dart';
import 'package:allo18/main.dart';
import 'package:allo18/models.dart';
import 'package:allo18/sim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un opérateur « parfait » qui joue directement via le moteur.
void bot(Sim s) {
  final c = s.call;
  if (c == null) {
    if (s.queue.isNotEmpty) s.pickup();
  } else {
    for (final q in s.questionsFor(c)) {
      s.ask(q);
    }
    for (final a in s.adviceFor(c).where((a) => a.effect > 0)) {
      s.advise(a);
      if (s.call == null) break;
    }
    if (s.call != null) {
      switch (c.kind) {
        case Kind.canular:
          s.endCall('raccroche');
        case Kind.police:
          s.endCall('r17');
        case Kind.medecin:
          s.endCall('r15');
        case Kind.urgence:
          s.engage(c, s.proposal(c, c.sc.nature), nature: c.sc.nature);
          s.endCall('raccroche');
      }
    }
  }
  for (final c in s.activeIncidents) {
    if (c.awaiting) s.engage(c, s.proposal(c, c.sc.nature), nature: c.sc.nature);
    if (c.missing.isNotEmpty) {
      final add = <Vehicle>[];
      c.missing.forEach((t, n) {
        final free = s.vehicles.where((v) => v.type == t && v.available && !add.contains(v)).take(n).toList();
        add.addAll(free.isEmpty ? [s.borrow(t)] : free);
      });
      s.engage(c, add);
    }
  }
}

/// Le ticker de la garde tourne en continu : on avance image par image.
Future<void> settle(WidgetTester tester) async {
  for (var k = 0; k < 10; k++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('les gardes se terminent, à tous les niveaux', () {
    for (var level = 0; level < grades.length; level++) {
      for (var seed = 0; seed < 10; seed++) {
        final s = Sim(level: level, operator: 'Test', seed: seed, tutorial: seed == 0);
        var steps = 0;
        while (!s.over && steps < 30000) {
          s.tick(0.1);
          if (steps % 15 == 0) bot(s);
          steps++;
        }
        expect(s.over, isTrue, reason: 'niveau $level, graine $seed');
        expect(s.closedCalls, isNotEmpty);
        final avg = s.totalScore / s.closedCalls.length;
        expect(avg, greaterThan(70), reason: 'un bon opérateur doit bien scorer');
      }
    }
  });

  test('raccrocher à tout est sanctionné', () {
    final s = Sim(level: 1, operator: 'Test', seed: 3);
    var steps = 0;
    while (!s.over && steps < 30000) {
      s.tick(0.1);
      if (s.call == null && s.queue.isNotEmpty) s.pickup();
      if (s.call != null) s.endCall('raccroche');
      steps++;
    }
    expect(s.over, isTrue);
    expect(s.totalScore / s.closedCalls.length, lessThan(40));
  });

  testWidgets('une garde complète à l\'écran, puis le débrief', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final sim = Sim(level: 1, operator: 'Test', seed: 4, tutorial: true);
    Sim? ended;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: GameScreen(sim: sim, onEnd: (s) => ended = s),
      ),
    );

    // Premier appel joué « au doigt », à travers l'interface.
    while (sim.queue.isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('DÉCROCHER'));
    await tester.pump();
    await tester.tap(find.text("Quelle est l'adresse exacte ?"));
    await tester.pump();
    await tester.tap(find.text('ENGAGER'));
    await settle(tester);
    await tester.tap(find.text(sim.call!.sc.nature.label));
    await tester.pump();
    await tester.tap(find.textContaining('ENGAGER ('));
    await settle(tester);
    expect(sim.call!.dispatched, isTrue);
    await tester.tap(find.text("Fin d'appel"));
    await settle(tester);
    await tester.tap(find.textContaining('Raccrocher'));
    await tester.pump();
    expect(sim.call, isNull);

    // La fiche d'intervention s'ouvre depuis la barre des interventions.
    await tester.tap(find.text('En route'));
    await settle(tester);
    expect(find.text('Moyens sur l\'intervention'.toUpperCase()), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);

    // Le reste de la garde est joué par le robot.
    var i = 0;
    while (ended == null && i < 8000) {
      await tester.pump(const Duration(milliseconds: 100));
      if (i % 15 == 0) bot(sim);
      i++;
    }
    expect(ended, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: DebriefScreen(sim: sim, profile: Profile()..name = 'Test', promoted: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FIN DE GARDE'), findsOneWidget);
  });
}
