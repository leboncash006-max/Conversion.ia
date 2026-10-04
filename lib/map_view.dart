import 'dart:math';

import 'package:flutter/material.dart';

import 'models.dart';
import 'sim.dart';

// ============================================================
//  Carte de la ville : quartiers, Loire, casernes, véhicules
// ============================================================

class MapView extends StatelessWidget {
  const MapView({super.key, required this.sim, this.selected, required this.onTapIncident});

  final Sim sim;
  final Incident? selected;
  final void Function(Incident) onTapIncident;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          onTapUp: (d) {
            final p = Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height);
            Incident? best;
            var bestD = 0.07;
            for (final c in sim.history) {
              if (!(c.active || c.awaiting || (c.callOpen && c.addressKnown))) continue;
              final dd = (c.loc - p).distance;
              if (dd < bestD) {
                bestD = dd;
                best = c;
              }
            }
            if (best != null) onTapIncident(best);
          },
          child: CustomPaint(size: size, painter: _MapPainter(sim, selected)),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.sim, this.selected);

  final Sim sim;
  final Incident? selected;

  static const bg = Color(0xFF0B121B);
  static const block = Color(0xFF16202C);
  static const blockHi = Color(0xFF1B2735);
  static const water = Color(0xFF1C4E78);
  static const label = Color(0xFF5D6E80);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset P(double x, double y) => Offset(x * w, y * h);
    final pulse = (DateTime.now().millisecondsSinceEpoch % 1200) / 1200;
    final blink = pulse < 0.5;

    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    // Pâtés de maisons
    final bp = Paint();
    const n = 12;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final x0 = i / n, y0 = j / n;
        final cx = x0 + 0.5 / n, cy = y0 + 0.5 / n;
        if (cx < 0.28 && cy < 0.3) continue; // forêt
        if (cx > 0.9) continue; // autoroute
        if ((cy - riverY(cx)).abs() < 0.05) continue;
        final zi = cx < 0.33 && cy > 0.76;
        final centre = (cx - 0.5).abs() < 0.13 && (cy - 0.47).abs() < 0.12;
        bp.color = zi ? const Color(0xFF1E2228) : (centre ? blockHi : block);
        final r = Rect.fromLTWH(x0 * w + 3, y0 * h + 3, w / n - 6, h / n - 6);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), bp);
      }
    }

    // Forêt
    final forest = Path()
      ..moveTo(0, 0)
      ..lineTo(0.3 * w, 0)
      ..quadraticBezierTo(0.31 * w, 0.18 * h, 0.27 * w, 0.31 * h)
      ..quadraticBezierTo(0.12 * w, 0.36 * h, 0, 0.33 * h)
      ..close();
    canvas.drawPath(forest, Paint()..color = const Color(0xFF12291B));
    final tree = Paint()..color = const Color(0xFF1C3D28);
    final rnd = Random(7);
    for (var k = 0; k < 70; k++) {
      final p = P(rnd.nextDouble() * 0.27, rnd.nextDouble() * 0.29);
      canvas.drawCircle(p, 2.5 + rnd.nextDouble() * 2.5, tree);
    }

    // Loire
    final river = Path()..moveTo(0, riverY(0) * h);
    for (var x = 0.0; x <= 1.0; x += 0.02) {
      river.lineTo(x * w, riverY(x) * h);
    }
    canvas.drawPath(
      river,
      Paint()
        ..color = water
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(8, h * 0.045),
    );
    // Ponts
    final bridge = Paint()
      ..color = const Color(0xFF2B3A4A)
      ..strokeWidth = 5;
    for (final x in [0.25, 0.5, 0.75]) {
      canvas.drawLine(P(x, riverY(x) - 0.05), P(x, riverY(x) + 0.05), bridge);
    }

    // Autoroute
    canvas.drawLine(
      P(0.93, 0),
      P(0.93, 1),
      Paint()
        ..color = const Color(0xFF6B4A22)
        ..strokeWidth = 6,
    );
    canvas.drawLine(
      P(0.93, 0),
      P(0.93, 1),
      Paint()
        ..color = const Color(0xFF3A2A16)
        ..strokeWidth = 1,
    );

    // Noms des quartiers
    _text(canvas, 'BOIS DE VAUCLAIR', P(0.13, 0.03), 8, const Color(0xFF3F6B4C));
    _text(canvas, 'LES HAUTS', P(0.55, 0.06), 8, label);
    _text(canvas, 'GARE', P(0.8, 0.2), 8, label);
    _text(canvas, 'BELLEVUE', P(0.15, 0.48), 8, label);
    _text(canvas, 'CENTRE', P(0.5, 0.58), 8, label);
    _text(canvas, 'LA LOIRE', P(0.62, riverY(0.62) + 0.002), 7, const Color(0xFF7FB2DD));
    _text(canvas, 'LE PORT', P(0.82, 0.78), 8, label);
    _text(canvas, 'ZI DES GRAVIÈRES', P(0.17, 0.97), 8, label);
    _text(canvas, 'A71', P(0.965, 0.5), 8, const Color(0xFFB98A4A));

    // Bases
    for (final b in [casCentre, casNord, casSud]) {
      final dispo = sim.vehicles.where((v) => v.home == b && v.state == VState.dispo).length;
      _base(canvas, P(b.pos.dx, b.pos.dy), const Color(0xFFD32F2F), '$dispo', b.short);
    }
    _base(canvas, P(hopital.pos.dx, hopital.pos.dy), Colors.white, 'H', null, fg: const Color(0xFFD32F2F));
    _base(canvas, P(commissariat.pos.dx, commissariat.pos.dy), const Color(0xFF3949AB), 'P', null);

    // Trajets
    for (final v in sim.vehicles) {
      if (v.path.isEmpty || v.state == VState.retour) continue;
      final path = Path()..moveTo(v.pos.dx * w, v.pos.dy * h);
      for (final p in v.path) {
        path.lineTo(p.dx * w, p.dy * h);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = v.type.color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Interventions
    for (final c in sim.history) {
      final visible = c.active || c.awaiting || (c.callOpen && c.addressKnown);
      if (!visible) continue;
      final p = P(c.loc.dx, c.loc.dy);
      final alert = c.awaiting || c.missing.isNotEmpty;
      final col = alert
          ? const Color(0xFFFF1744)
          : c.firstArrival != null
          ? const Color(0xFFFFC107)
          : const Color(0xFFFF7043);
      final rad = 9 + 10 * pulse;
      canvas.drawCircle(p, rad, Paint()..color = col.withValues(alpha: (1 - pulse) * 0.45));
      if (c == selected) {
        canvas.drawCircle(
          p,
          15,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(p, 10, Paint()..color = col);
      final icon = (c.nature ?? (c.callOpen ? null : c.sc.nature))?.icon ?? Icons.phone_in_talk;
      _icon(canvas, icon, p, 13, Colors.black);
    }

    // Véhicules
    for (final v in sim.vehicles) {
      if (v.state == VState.dispo) continue;
      if (v.home == casVoisin && v.pos == casVoisin.pos && v.state != VState.route) continue;
      var p = P(v.pos.dx, v.pos.dy);
      if (v.state == VState.surPlace && v.inc != null) {
        // Les engins sur place se garent autour de l'intervention.
        final i = v.inc!.vehicles.where((x) => x.state == VState.surPlace && x.inc == v.inc).toList().indexOf(v);
        final a = -pi / 2 + i * 0.9;
        p += Offset(cos(a), sin(a)) * 18;
      }
      final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 14, height: 9), const Radius.circular(2.5));
      canvas.drawRRect(rr.inflate(1.2), Paint()..color = Colors.black);
      canvas.drawRRect(rr, Paint()..color = v.type.color);
      final urgent = v.state == VState.route || v.state == VState.transport;
      if (urgent && blink) {
        canvas.drawCircle(p.translate(0, -6), 2.2, Paint()..color = const Color(0xFF40C4FF));
      }
      if (selected != null && v.inc == selected) {
        _text(canvas, v.type.code, p.translate(0, 11), 7, Colors.white);
      }
    }
  }

  void _base(Canvas canvas, Offset p, Color col, String txt, String? name, {Color fg = Colors.white}) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: 18, height: 18), const Radius.circular(4));
    canvas.drawRRect(r.inflate(1.5), Paint()..color = Colors.black);
    canvas.drawRRect(r, Paint()..color = col);
    _text(canvas, txt, p, 10, fg, bold: true);
    if (name != null) _text(canvas, name, p.translate(0, 15), 7, const Color(0xFFEF9A9A));
  }

  void _text(Canvas canvas, String s, Offset c, double size, Color col, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: col,
          fontSize: size,
          letterSpacing: 0.8,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _icon(Canvas canvas, IconData icon, Offset c, double size, Color col) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: size, fontFamily: icon.fontFamily, package: icon.fontPackage, color: col),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
