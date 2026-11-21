import 'dart:collection';
import 'dart:convert';

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Eğim Kutusu: kutuyu dört yönden birine eğ; bütün bloklar o yöne
/// duvara ya da başka bloğa kadar kayar. Aynı renkten yan yana gelen iki
/// ya da daha çok blok erir. Gri taşlar kayar ama erimez. Renkli blok
/// kalmayınca bölüm biter.

const List<List<int>> kTiltDirs = [[0, -1], [1, 0], [0, 1], [-1, 0]]; // yukarı, sağ, aşağı, sol

/// Taş (kayar, erimez).
const int kStone = -1;

class TiltLevel {
  final int w, h;
  final Set<int> walls;
  final Map<int, int> blocks; // hücre -> renk (taş = -1)
  final int seed, difficulty;
  final int optimal; // en kısa çözüm
  final int moveLimit;
  const TiltLevel({
    required this.w,
    required this.h,
    required this.walls,
    required this.blocks,
    required this.seed,
    required this.difficulty,
    this.optimal = 0,
    this.moveLimit = 0,
  });
}

/// Bir eğme sonucu: yeni yerleşim ve kaç blok eridi.
(Map<int, int>, int) tiltStep(int w, int h, Set<int> walls, Map<int, int> blocks, int d) {
  final dx = kTiltDirs[d][0], dy = kTiltDirs[d][1];
  final order = blocks.keys.toList()
    ..sort((a, b) => ((b % w) * dx + (b ~/ w) * dy).compareTo((a % w) * dx + (a ~/ w) * dy));
  final nb = <int, int>{};
  for (final p in order) {
    var x = p % w, y = p ~/ w;
    while (true) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) break;
      final q = ny * w + nx;
      if (walls.contains(q) || nb.containsKey(q)) break;
      x = nx;
      y = ny;
    }
    nb[y * w + x] = blocks[p]!;
  }
  final seen = <int>{}, remove = <int>{};
  for (final p in nb.keys) {
    if (seen.contains(p) || nb[p] == kStone) continue;
    final c = nb[p]!;
    final comp = <int>[p];
    seen.add(p);
    for (var i = 0; i < comp.length; i++) {
      final a = comp[i];
      final ax = a % w, ay = a ~/ w;
      for (final dd in kTiltDirs) {
        final bx = ax + dd[0], by = ay + dd[1];
        if (bx < 0 || by < 0 || bx >= w || by >= h) continue;
        final b = by * w + bx;
        if (!seen.contains(b) && nb[b] == c) {
          seen.add(b);
          comp.add(b);
        }
      }
    }
    if (comp.length >= 2) remove.addAll(comp);
  }
  for (final p in remove) {
    nb.remove(p);
  }
  return (nb, remove.length);
}

bool _cleared(Map<int, int> b) => b.values.every((c) => c == kStone);

String _key(Map<int, int> b) {
  final k = b.keys.toList()..sort();
  return [for (final p in k) '$p:${b[p]}'].join(',');
}

/// En kısa çözümün ilk hamlesi ve uzunluğu; çözüm yoksa (null, -1).
(int?, int) tiltSolve(int w, int h, Set<int> walls, Map<int, int> start, {int maxDepth = 14, int cap = 60000}) {
  if (_cleared(start)) return (null, 0);
  final seen = <String>{_key(start)};
  final q = Queue<(Map<int, int>, int, int)>(); // durum, derinlik, ilk hamle
  q.add((start, 0, -1));
  while (q.isNotEmpty) {
    final (b, dep, first) = q.removeFirst();
    if (dep >= maxDepth) continue;
    final count = <int, int>{};
    for (final c in b.values) {
      if (c != kStone) count[c] = (count[c] ?? 0) + 1;
    }
    if (count.values.any((n) => n < 2)) continue; // tek kalan renk asla erimez
    for (var d = 0; d < 4; d++) {
      final (nb, _) = tiltStep(w, h, walls, b, d);
      final f = first < 0 ? d : first;
      if (_cleared(nb)) return (f, dep + 1);
      if (!seen.add(_key(nb))) continue;
      if (seen.length > cap) return (null, -1);
      q.add((nb, dep + 1, f));
    }
  }
  return (null, -1);
}

TiltLevel generateTiltLevel(LevelSpec spec) {
  final r = SeededRandom(mixSeed([spec.seed, 7311]));
  final d = spec.difficulty.clamp(1, 10);
  final w = 4 + d ~/ 3, h = w + 1;
  final lo = (1 + d ~/ 2).clamp(2, 6), hi = 4 + d;
  TiltLevel? best;
  for (var tries = 0; tries < 300; tries++) {
    final cells = [for (var i = 0; i < w * h; i++) i];
    for (var i = cells.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = cells[i];
      cells[i] = cells[j];
      cells[j] = t;
    }
    final nWalls = r.nextInt(2 + d ~/ 2);
    final walls = cells.take(nWalls).toSet();
    final free = cells.skip(nWalls).toList();
    final colors = (2 + d ~/ 3).clamp(2, 5);
    final blocks = <int, int>{};
    var i = 0;
    for (var c = 0; c < colors; c++) {
      final per = 2 + ((d >= 4 && r.chance(0.5)) ? 1 : 0);
      for (var k = 0; k < per; k++) {
        blocks[free[i++]] = c;
      }
    }
    if (d >= 6) {
      for (var k = 0; k < 1 + (d >= 9 ? 1 : 0); k++) {
        blocks[free[i++]] = kStone;
      }
    }
    // Başlangıçta zaten yan yana duran aynı renkler olmasın.
    var touching = false;
    blocks.forEach((p, c) {
      if (c == kStone) return;
      final x = p % w, y = p ~/ w;
      if ((x + 1 < w && blocks[p + 1] == c) || (y + 1 < h && blocks[p + w] == c)) touching = true;
    });
    if (touching) continue;
    final (_, n) = tiltSolve(w, h, walls, blocks);
    if (n <= 0) continue;
    final lvl = TiltLevel(w: w, h: h, walls: walls, blocks: blocks, seed: spec.seed, difficulty: d, optimal: n);
    if (n >= lo && n <= hi) return lvl;
    if (best == null || (n - lo).abs() < (best.optimal - lo).abs()) best = lvl;
  }
  return best ??
      TiltLevel(w: 4, h: 5, walls: const {}, blocks: const {0: 0, 19: 0}, seed: spec.seed, difficulty: d, optimal: 1);
}

class TiltGame {
  final TiltLevel level;
  Map<int, int> blocks;
  int moves = 0, melted = 0, bestChain = 0;
  final List<String> _history = [];

  TiltGame(this.level) : blocks = Map.of(level.blocks);

  int get w => level.w;
  int get h => level.h;
  bool get won => _cleared(blocks);
  int get colorLeft => blocks.values.where((c) => c != kStone).length;

  /// Yön ver; erime sayısını döndürür (hiç kıpırdamadıysa -1).
  int tilt(int d) {
    final (nb, m) = tiltStep(w, h, level.walls, blocks, d);
    if (m == 0 && _key(nb) == _key(blocks)) return -1;
    _history.add(serialize());
    blocks = nb;
    moves++;
    melted += m;
    if (m > bestChain) bestChain = m;
    return m;
  }

  /// Bu durumdan çözüm hâlâ var mı?
  bool get stuck {
    final count = <int, int>{};
    for (final c in blocks.values) {
      if (c != kStone) count[c] = (count[c] ?? 0) + 1;
    }
    return count.values.any((n) => n < 2);
  }

  int? hint() => tiltSolve(w, h, level.walls, blocks).$1;

  bool get canUndo => _history.isNotEmpty;

  void undo() {
    if (_history.isEmpty) return;
    _load(jsonDecode(_history.removeLast()) as Map<String, dynamic>);
  }

  String serialize() => jsonEncode({
        'b': [for (final e in blocks.entries) [e.key, e.value]],
        's': [moves, melted, bestChain],
      });

  void _load(Map<String, dynamic> j) {
    blocks = {for (final e in j['b'] as List) ((e as List)[0] as num).toInt(): (e[1] as num).toInt()};
    final s = [for (final v in j['s'] as List) (v as num).toInt()];
    moves = s[0];
    melted = s[1];
    bestChain = s[2];
  }

  static TiltGame restore(TiltLevel l, String snap) {
    final g = TiltGame(l);
    g._load(jsonDecode(snap) as Map<String, dynamic>);
    return g;
  }
}
