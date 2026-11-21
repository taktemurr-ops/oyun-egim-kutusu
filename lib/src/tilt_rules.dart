import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'tilt_engine.dart';

const egimKutusuId = 'oyun-egim-kutusu';

class TiltRules extends GameRules<TiltLevel> {
  /// Üretim + çözücü türü: 100.000 bölüm.
  @override
  int get levelCount => 100000;

  @override
  String get gameId => egimKutusuId;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('blocks_melted', 'Eriyen blok', 'Blocks melted', scale: 60),
        GameStat('perfect_tilts', 'En kısa çözüm', 'Perfect solves', scale: 3),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('melted', 'blocks_melted', [20, 60, 150]),
        MissionTemplate('perfect', 'perfect_tilts', [1, 3, 6]),
      ];

  @override
  TiltLevel generate(LevelSpec spec) => generateTiltLevel(spec);

  @override
  Validation validate(TiltLevel level, LevelSpec spec) {
    if (level.blocks.values.where((c) => c != kStone).length < 2) return const Validation.fail('too few blocks');
    final (_, n) = tiltSolve(level.w, level.h, level.walls, level.blocks);
    if (n <= 0) return const Validation.fail('not solvable');
    return Validation.ok(n);
  }

  /// Hamle sınırı: en kısa çözüm + pay; zorlaştıkça pay azalır.
  TiltLevel finalize(GeneratedLevel<TiltLevel> g) {
    final l = g.puzzle;
    final n = g.validation.metric;
    final limit = n + (12 - l.difficulty).clamp(3, 10);
    return TiltLevel(
        w: l.w, h: l.h, walls: l.walls, blocks: l.blocks, seed: l.seed, difficulty: l.difficulty, optimal: n, moveLimit: limit);
  }

  static int stars(TiltGame g) =>
      !g.won ? 0 : (g.moves <= g.level.optimal ? 3 : (g.moves <= g.level.optimal + 2 ? 2 : 1));
}
