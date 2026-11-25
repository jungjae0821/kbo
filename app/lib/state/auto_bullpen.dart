import 'package:kbo_engine/kbo_engine.dart';

import '../data/app_data.dart';

/// 사용자가 고르지 않은 팀의 투수 교체를 정한다. 다음 타석 직전에 부른다.
///
/// 규칙 (실제 불펜 운용을 단순하게 흉내 낸다):
/// - 선발은 잘 던지면(2실점 이하) 7이닝, 아니면 6이닝을 채우고 다음 이닝 시작에 내려간다.
///   선발이 5실점하면 이닝 중이라도 바로 바꾼다.
/// - 구원은 한 이닝을 맡고 다음 이닝 시작에 바뀐다. 한 이닝에 3실점하면 이닝 중에도 바꾼다.
/// - 9회 이후 1~3점 앞서면 시즌 세이브가 가장 많은 투수, 7·8회에 앞서거나 동점이면
///   홀드가 가장 많은 투수, 그 밖에는 시즌 구원 이닝이 많은 투수를 올린다.
///
/// 교체는 엔진의 교체 기록에 남으므로 이어하기·재현에서도 같은 시점에 같은 교체가 일어난다.
/// 반환값: 교체했으면 새 투수 ID.
String? autoPitchingChange(GameEngine engine, AppData data, String teamId) {
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
  // 선발 요원(시즌 선발 10경기 이상)은 불펜에 남은 투수가 없을 때만 쓴다.
  final relievers = candidates.where((id) => data.player(id).pitcherStarts < 10).toList();
  final pool = relievers.isEmpty ? candidates : relievers;

  int by(String id) {
    final p = data.player(id);
    if (s.inning >= 9 && lead >= 1 && lead <= 3) return p.saves ?? 0;
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
