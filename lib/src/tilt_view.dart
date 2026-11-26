import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';
import 'package:studio_core/app/studio_ui.dart';

import 'tilt_engine.dart';
import 'tilt_rules.dart';

final Map<StudioLook, ThemeData> _studioThemes = {};

/// Oyun ekranı: düğmeler, çipler, üst bilgi ve pencereler onaylı koyu
/// tasarımda (merkezin paleti, studio-core StudioLook); tahta çizimi kendi
/// renklerini korur.
class TiltView extends StatelessWidget {
  final PlayContext ctx;
  const TiltView({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Theme(data: _studioThemes[look] ??= buildStudioTheme(look), child: TiltViewBody(ctx: ctx));
  }
}

class TiltViewBody extends StatefulWidget {
  final PlayContext ctx;
  const TiltViewBody({super.key, required this.ctx});

  @override
  State<TiltViewBody> createState() => _TiltViewState();
}

class _TiltViewState extends State<TiltViewBody> {
  late TiltLevel level;
  late TiltGame game;
  int? _hint;
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false;
  double _cell = 40;
  Offset _lean = Offset.zero;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = TiltRules().finalize(ctx.generated as GeneratedLevel<TiltLevel>);
    final snap = ctx.resume['snap'];
    game = snap is String ? TiltGame.restore(level, snap) : TiltGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  void _tilt(int d) {
    if (_ended) return;
    final m = game.tilt(d);
    if (m < 0) {
      ctx.sfx(Sfx.error);
      return;
    }
    ctx.sfx(m > 0 ? (game.won ? Sfx.win : Sfx.clear) : Sfx.tap);
    setState(() {
      _hint = null;
      _lean = Offset(kTiltDirs[d][0] * 0.03, kTiltDirs[d][1] * 0.03);
    });
    Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _lean = Offset.zero);
    });
    _persist();
    if (game.won || game.stuck || (level.moveLimit > 0 && game.moves >= level.moveLimit)) _end();
  }

  void _swipe(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (v.distance < 120) return;
    if (v.dx.abs() > v.dy.abs()) {
      _tilt(v.dx > 0 ? 1 : 3);
    } else {
      _tilt(v.dy > 0 ? 2 : 0);
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    if (!game.won) ctx.sfx(Sfx.lose);
    ctx.finish(RoundResult(
      won: game.won,
      score: (game.melted * 15 + (game.won ? (level.moveLimit - game.moves).clamp(0, 99) * 10 : 0)).clamp(0, 1 << 20),
      stars: TiltRules.stars(game),
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'blocks_melted': game.melted, 'perfect_tilts': game.won && game.moves <= level.optimal ? 1 : 0},
    ));
  }

  Future<void> _useHint() async {
    if (!await ctx.requestHint()) return;
    _hints++;
    setState(() => _hint = game.hint());
    _persist();
  }

  Widget _arrow(int d, IconData icon) => IconButton.filledTonal(
        onPressed: _ended ? null : () => _tilt(d),
        icon: Icon(icon),
        style: _hint == d ? IconButton.styleFrom(backgroundColor: Colors.amber) : null,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _cell = math.max(20.0, math.min((cons.maxWidth - 32) / level.w, cons.maxHeight * 0.6 / level.h));
      final left = level.moveLimit > 0 ? level.moveLimit - game.moves : null;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(Strings.tx(ctx.lang, 'Kalan blok: {0}', 'Blocks left: {0}', [game.colorLeft]),
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (left != null) ...[const Icon(Icons.swipe, size: 18), Text(' $left  ')],
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onPanEnd: _swipe,
              child: AnimatedSlide(
                offset: _lean,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Semantics(
                  label: 'board',
                  child: SizedBox(
                    width: _cell * level.w,
                    height: _cell * level.h,
                    child: CustomPaint(painter: _Painter(this)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _arrow(3, Icons.west),
            Column(mainAxisSize: MainAxisSize.min, children: [
              _arrow(0, Icons.north),
              _arrow(2, Icons.south),
            ]),
            _arrow(1, Icons.east),
            const SizedBox(width: 24),
            IconButton.filledTonal(onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
            IconButton.filledTonal(
                onPressed: game.canUndo && !_ended
                    ? () {
                        setState(() {
                          game.undo();
                          _undos++;
                        });
                        _persist();
                      }
                    : null,
                icon: const Icon(Icons.undo),
                tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
    });
  }
}

class _Painter extends CustomPainter {
  final _TiltViewState v;
  _Painter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = v._cell;
    final g = v.game;
    final tray = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.3));
    canvas.drawRRect(tray, Paint()..color = Colors.black.withValues(alpha: 0.14));
    canvas.drawRRect(
        tray.deflate(1.5),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    for (final p in g.level.walls) {
      final r = Rect.fromLTWH((p % g.w) * c, (p ~/ g.w) * c, c, c).deflate(c * 0.04);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(c * 0.12)), Paint()..color = const Color(0xFF3B4252));
      canvas.drawLine(r.topLeft + Offset(c * 0.2, c * 0.2), r.bottomRight - Offset(c * 0.2, c * 0.2),
          Paint()..color = Colors.white.withValues(alpha: 0.12)..strokeWidth = 3);
    }
    g.blocks.forEach((p, col) {
      final r = Rect.fromLTWH((p % g.w) * c, (p ~/ g.w) * c, c, c).deflate(c * 0.08);
      if (col == kStone) {
        canvas.drawOval(r, Paint()..color = const Color(0xFF8C9199));
        canvas.drawOval(r.deflate(c * 0.18), Paint()..color = Colors.white.withValues(alpha: 0.15));
        return;
      }
      final color = v.ctx.pieceColors[col % v.ctx.pieceColors.length];
      final rr = RRect.fromRectAndRadius(r, Radius.circular(c * 0.26));
      canvas.drawRRect(rr, Paint()..color = color);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(r.left + c * 0.1, r.top + c * 0.08, r.width - c * 0.2, r.height * 0.3),
              Radius.circular(c * 0.12)),
          Paint()..color = Colors.white.withValues(alpha: 0.22));
      if (v.ctx.colorBlind) {
        final tp = TextPainter(
            text: TextSpan(text: v.ctx.symbol(col), style: TextStyle(fontSize: c * 0.4, color: Colors.white)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
