import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_egim_kutusu/oyun_egim_kutusu.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = TiltRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('bölümler çözülebilir ve ipucuyla en kısa yoldan çözülür', () {
    for (final lv in [1, 12, 50, 99, 230, 777, 2500, 9999, 33333, 49999, 99999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      final l = rules.finalize(gl);
      final g = TiltGame(l);
      var guard = 0;
      while (!g.won && guard++ < 40) {
        final d = g.hint();
        expect(d, isNotNull, reason: 'bölüm $lv');
        g.tilt(d!);
      }
      expect(g.won, isTrue);
      expect(g.moves, l.optimal, reason: 'bölüm $lv');
      expect(TiltRules.stars(g), 3);
    }
  });

  test('kaydırma blokları duvara kadar götürür, aynı renkler erir', () {
    // 3x1: [A . A] sağa eğ -> A'lar yan yana gelir ve erir.
    final (nb, m) = tiltStep(3, 1, const {}, {0: 1, 2: 1}, 1);
    expect(m, 2);
    expect(nb, isEmpty);
    // Taş erimez.
    final (nb2, m2) = tiltStep(3, 1, const {}, {0: kStone, 2: kStone}, 3);
    expect(m2, 0);
    expect(nb2.keys.toSet(), {0, 1});
  });

  test('geri al ve kayıt', () {
    final l = rules.finalize(rules.build(planner.spec(300)));
    final g = TiltGame(l);
    final before = g.serialize();
    for (var d = 0; d < 4; d++) {
      if (g.tilt(d) >= 0) break;
    }
    final r = TiltGame.restore(l, g.serialize());
    expect(r.serialize(), g.serialize());
    g.undo();
    expect(g.serialize(), before);
  });
}
