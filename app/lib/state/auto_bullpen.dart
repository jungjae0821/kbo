import 'package:kbo_engine/kbo_engine.dart';

import '../data/app_data.dart';

/// 경기 전에 정한 한 팀의 구원 운용: 중간 계투가 올라갈 순서와 마무리.
class BullpenPlan {
  BullpenPlan({required List<String> order, this.closer}) : order = List.unmodifiable(order);

  /// 중간 계투가 마운드에 오르는 순서. 교체 시점마다 아직 안 나온 첫 투수가 올라간다.
  final List<String> order;

  /// 9회 이후 1~3점 앞설 때 올라가는 투수. 없으면 계투 순서대로.
  final String? closer;

  /// 계투 순서에 넣는 인원 수 (선발 다음 2~6번째 투수).
  static const size = 5;

  /// 시즌 기록으로 짠 기본 운용: 세이브가 가장 많은 구원이 마무리,
  /// 나머지 구원은 홀드 → 구원 이닝이 많은 순으로 [size]명.
  /// 선발 요원(시즌 선발 10경기 이상)은 구원이 모자랄 때만 넣는다.
  factory BullpenPlan.suggested(AppData data, String teamId, String starterId) {
    final pitchers = [
      for (final id in GameEngine.starterCandidates(data.season, teamId))
        if (id != starterId) id,
    ];
    final relievers = pitchers.where((id) => data.player(id).pitcherStarts < 10).toList();
    final starters = pitchers.where((id) => data.player(id).pitcherStarts >= 10).toList()
      ..sort((a, b) => (data.player(b).outsPitched ?? 0).compareTo(data.player(a).outsPitched ?? 0));
    String? closer;
    var bestSaves = 0;
    for (final id in relievers) {
      final s = data.player(id).saves ?? 0;
      if (s > bestSaves) {
        bestSaves = s;
        closer = id;
      }
    }
    final rest = [for (final id in relievers) if (id != closer) id]..sort((a, b) {
        final pa = data.player(a), pb = data.player(b);
        final c = (pb.holds ?? 0).compareTo(pa.holds ?? 0);
        return c != 0 ? c : (pb.outsPitched ?? 0).compareTo(pa.outsPitched ?? 0);
      });
    return BullpenPlan(order: [...rest, ...starters].take(size).toList(), closer: closer);
  }

  /// 선발이 바뀌어 그 투수가 계투 순서·마무리에 있으면 뺀다.
  BullpenPlan without(String playerId) => BullpenPlan(
        order: [for (final id in order) if (id != playerId) id],
        closer: closer == playerId ? null : closer,
      );

  /// 계투 순서에서 [index]번째(0부터)를 [playerId]로 바꾼다. 이미 다른 칸이나 마무리에 있으면 자리를 맞바꾼다.
  BullpenPlan withOrder(int index, String playerId) {
    final next = List.of(order);
    final old = index < next.length ? next[index] : null;
    final at = next.indexOf(playerId);
    var newCloser = closer;
    if (at >= 0 && old != null) {
      next[at] = old;
    } else if (closer == playerId) {
      newCloser = old;
    }
    if (index < next.length) {
      next[index] = playerId;
    } else {
      next.add(playerId);
    }
    return BullpenPlan(order: next, closer: newCloser);
  }

  /// 마무리를 [playerId]로 바꾼다. 계투 순서에 있던 투수면 기존 마무리와 자리를 맞바꾼다.
  BullpenPlan withCloser(String? playerId) {
    final next = List.of(order);
    final at = playerId == null ? -1 : next.indexOf(playerId);
    if (at >= 0) {
      if (closer != null) {
        next[at] = closer!;
      } else {
        next.removeAt(at);
      }
    }
    return BullpenPlan(order: next, closer: playerId);
  }

  bool sameAs(BullpenPlan other) =>
      closer == other.closer && order.length == other.order.length && [for (var i = 0; i < order.length; i++) order[i] == other.order[i]].every((x) => x);

  Map<String, dynamic> toJson() => {'order': order, 'closer': closer};

  /// 저장 파일에서 읽는다. 모양이 다르면 null (그 팀은 기록 기반 자동 운용).
  static BullpenPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final order = json['order'];
    final closer = json['closer'];
    if (order is! List || order.any((e) => e is! String) || (closer != null && closer is! String)) return null;
    return BullpenPlan(order: order.cast<String>(), closer: closer as String?);
  }
}

/// 투수 교체를 정한다. 다음 타석 직전(과 타석 직후)에 부른다. 교체 시점이 아니면 아무것도 하지 않는다.
///
/// 규칙 (실제 불펜 운용을 단순하게 흉내 낸다):
/// - 선발은 잘 던지면(2실점 이하) 7이닝, 아니면 6이닝을 채우고 다음 이닝 시작에 내려간다.
///   선발이 5실점하면 이닝 중이라도 바로 바꾼다.
/// - 구원은 한 이닝을 맡고 다음 이닝 시작에 바뀐다. 한 이닝에 3실점하면 이닝 중에도 바꾼다.
/// - [plan]이 있으면: 9회 이후 1~3점 앞서면 마무리, 그 밖에는 계투 순서에서 아직 안 나온 첫 투수.
///   순서를 다 쓰면 아래 기록 기반 규칙을 따른다.
/// - 기록 기반: 9회 이후 1~3점 앞서면 시즌 세이브가 가장 많은 투수, 7·8회에 앞서거나 동점이면
///   홀드가 가장 많은 투수, 그 밖에는 시즌 구원 이닝이 많은 투수.
///
/// 교체는 엔진의 교체 기록에 남으므로 이어하기·재현에서도 같은 시점에 같은 교체가 일어난다.
/// 반환값: 교체했으면 새 투수 ID.
String? autoPitchingChange(GameEngine engine, AppData data, String teamId, {BullpenPlan? plan}) {
  final s = engine.state;
  if (s.isFinished || !engine.canSubstitutePitcher(teamId)) return null;
  final defenseId = s.isTop ? engine.homeTeamId : engine.awayTeamId;
  if (defenseId != teamId) return null;

  final current = engine.pitcherFor(teamId);
  final mine = engine.logs.where((l) => l.pitcherId == current).toList();
  var outs = 0, runs = 0, runsThisHalf = 0;
  for (final l in mine) {
    outs += l.transition.outsAfterPlay - l.before.outs;
    runs += l.transition.scored.length;
    if (l.inning == s.inning && l.isTop == s.isTop) runsThisHalf += l.transition.scored.length;
  }
  final starter = current == engine.startingPitcherFor(teamId);
  final halfStart = s.outs == 0 && s.bases.every((b) => b == null) &&
      (engine.logs.isEmpty || engine.logs.last.inning != s.inning || engine.logs.last.isTop != s.isTop);

  final bool change;
  if (starter) {
    change = runs >= 5 || (halfStart && outs >= (runs <= 2 ? 21 : 18));
  } else {
    // 구원은 자기 이닝을 마쳤으면(다른 공수에서 던진 기록이 있으면) 다음 이닝 시작에 바꾼다.
    final pitchedEarlierHalf = mine.any((l) => l.inning != s.inning || l.isTop != s.isTop);
    change = runsThisHalf >= 3 || (halfStart && pitchedEarlierHalf);
  }
  if (!change) return null;

  final candidates = engine.pitcherCandidates(teamId);
  if (candidates.isEmpty) return null;
  final lead = teamId == engine.homeTeamId ? s.homeScore - s.awayScore : s.awayScore - s.homeScore;
  final saveSituation = s.inning >= 9 && lead >= 1 && lead <= 3;

  if (plan != null) {
    String? chosen;
    if (saveSituation && plan.closer != null && candidates.contains(plan.closer)) {
      chosen = plan.closer;
    } else {
      chosen = plan.order.where(candidates.contains).firstOrNull;
    }
    if (chosen != null) {
      engine.substitutePitcher(teamId, chosen);
      return chosen;
    }
  }

  // 선발 요원(시즌 선발 10경기 이상)은 불펜에 남은 투수가 없을 때만 쓴다.
  final relievers = candidates.where((id) => data.player(id).pitcherStarts < 10).toList();
  final pool = relievers.isEmpty ? candidates : relievers;

  int by(String id) {
    final p = data.player(id);
    if (saveSituation) return p.saves ?? 0;
    if (s.inning >= 7 && lead >= 0) return p.holds ?? 0;
    return p.outsPitched ?? 0;
  }

  final ranked = [...pool]..sort((a, b) {
      final c = by(b).compareTo(by(a));
      return c != 0 ? c : (data.player(b).outsPitched ?? 0).compareTo(data.player(a).outsPitched ?? 0);
    });
  engine.substitutePitcher(teamId, ranked.first);
  return ranked.first;
}
