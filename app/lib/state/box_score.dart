import 'package:kbo_engine/kbo_engine.dart';

/// 타자 한 명의 경기 기록.
class BatterLine {
  BatterLine(this.playerId, this.order);

  final String playerId;

  /// 타순 1~9. 대타는 이어받은 타순.
  final int order;

  /// 대타로 나왔으면 true.
  bool pinchHitter = false;
  int plateAppearances = 0;
  int atBats = 0;
  int hits = 0;
  int homeRuns = 0;
  int runsBattedIn = 0;
  int walks = 0;
  int strikeouts = 0;
  int runs = 0;
}

/// 투수 한 명의 경기 기록.
class PitcherLine {
  PitcherLine(this.playerId);

  final String playerId;
  int outs = 0;
  int battersFaced = 0;
  int hits = 0;
  int runs = 0;
  int walks = 0;
  int strikeouts = 0;
  int homeRuns = 0;

  /// "5 1/3"처럼 이닝 표기.
  String get innings {
    final whole = outs ~/ 3, part = outs % 3;
    if (part == 0) return '$whole';
    return whole == 0 ? '$part/3' : '$whole $part/3';
  }
}

/// 한 팀의 경기 기록과 투수 결정.
class TeamBox {
  TeamBox(this.teamId);
  final String teamId;
  final List<BatterLine> batters = [];
  final List<PitcherLine> pitchers = [];
  int get hits => batters.fold(0, (s, b) => s + b.hits);
  int get walks => batters.fold(0, (s, b) => s + b.walks);
}

/// 타석 기록에서 계산한 경기 기록표.
///
/// 투수 결정은 공식 야구 규칙 9.16~9.19를 이 엔진에 맞게 줄여서 적용한다.
/// - 실점은 그 주자를 내보낸 투수의 몫이다 (승계 주자).
/// - 승리: 이긴 팀이 마지막으로 앞서 나간 때의 그 팀 투수. 선발은 5이닝 이상 던져야 하고,
///   못 채웠으면 구원 중 가장 많은 아웃을 잡은 투수.
/// - 패전: 이긴 팀에 결승점을 내준 투수.
/// - 세이브: 이긴 팀에서 경기를 끝낸 투수(승리투수 아님)가 앞선 상황에 나와
///   (3점 이하 리드에서 1이닝 이상) 또는 (동점 주자가 누상·타석·대기 타석에 있을 때) 또는 (3이닝 이상) 던졌을 때.
/// - 홀드: 세이브 상황에 나와 1아웃 이상 잡고 리드를 지킨 채 내려간 구원투수 (경기를 끝내지 않음).
/// 엔진은 선발이 끝까지 던지고 교체는 사용자의 예측 팀만 하므로, 세이브·홀드는 교체가 있을 때만 나온다.
class BoxScore {
  BoxScore._(this.away, this.home, this.winningPitcherId, this.losingPitcherId, this.savePitcherId, this.holdPitcherIds);

  factory BoxScore.from(GameEngine engine) {
    final away = TeamBox(engine.awayTeamId);
    final home = TeamBox(engine.homeTeamId);
    TeamBox box(String teamId) => teamId == away.teamId ? away : home;

    // 선발 타순부터 줄을 만들고, 대타는 나올 때 그 타순 뒤에 붙인다.
    final batterLines = <String, BatterLine>{};
    for (final t in [away, home]) {
      for (final (i, id) in engine.startingBattingOrderFor(t.teamId).indexed) {
        final line = BatterLine(id, i + 1);
        t.batters.add(line);
        batterLines[id] = line;
      }
    }
    for (final s in engine.substitutions.where((s) => s.kind == SubstitutionKind.pinchHitter)) {
      final t = box(s.teamId);
      final line = BatterLine(s.inPlayerId, s.battingOrder!)..pinchHitter = true;
      final at = t.batters.lastIndexWhere((b) => b.order == s.battingOrder);
      t.batters.insert(at + 1, line);
      batterLines[s.inPlayerId] = line;
    }

    final pitcherLines = <String, PitcherLine>{};
    PitcherLine pitcher(String teamId, String id) => pitcherLines.putIfAbsent(id, () {
          final line = PitcherLine(id);
          box(teamId).pitchers.add(line);
          return line;
        });
    for (final t in [away, home]) {
      pitcher(t.teamId, engine.startingPitcherFor(t.teamId));
    }

    // 주자 → 그 주자를 내보낸 투수.
    final responsible = <String, String>{};
    // 투수가 마운드에 오른 순간의 상황 (세이브·홀드 판정용).
    final entry = <String, ({int lead, int tyingMargin})>{};
    // 투수가 마지막 타자를 상대한 뒤의 리드.
    final leadWhenLeft = <String, int>{};
    String? goAheadPitcher, winnerPitcherOfRecord;
    final winnerId = engine.winnerTeamId;

    for (final log in engine.logs) {
      final offenseId = log.isTop ? engine.awayTeamId : engine.homeTeamId;
      final defenseId = log.isTop ? engine.homeTeamId : engine.awayTeamId;
      final p = pitcher(defenseId, log.pitcherId);
      final before = log.before;
      final defenseLeadBefore =
          log.isTop ? before.homeScore - before.awayScore : before.awayScore - before.homeScore;
      if (p.battersFaced == 0) {
        final runnersOn = before.bases.where((b) => b != null).length;
        // 동점 주자가 누상, 타석, 대기 타석 중에 있으면: 리드 ≤ 주자 + 2.
        entry[p.playerId] = (lead: defenseLeadBefore, tyingMargin: runnersOn + 2);
      }
      p.battersFaced++;

      final b = batterLines[log.batterId]!;
      final t = log.transition;
      b.plateAppearances++;
      final o = log.outcome;
      final walk = o == PlateOutcome.walk;
      final hbp = o == PlateOutcome.hitByPitch;
      final sacFly = t.note == PlayNote.runScoredOnOut;
      if (!walk && !hbp && !sacFly) b.atBats++;
      final hit = o == PlateOutcome.single || o == PlateOutcome.doubleHit || o == PlateOutcome.triple || o == PlateOutcome.homeRun;
      if (hit) {
        b.hits++;
        p.hits++;
      }
      if (o == PlateOutcome.homeRun) {
        b.homeRuns++;
        p.homeRuns++;
      }
      if (walk) {
        b.walks++;
        p.walks++;
      }
      if (o == PlateOutcome.strikeout) {
        b.strikeouts++;
        p.strikeouts++;
      }
      // 병살타 중 들어온 점수는 타점이 아니다 (규칙 9.04(b)).
      if (t.note != PlayNote.doublePlay) b.runsBattedIn += t.scored.length;
      p.outs += t.outsAfterPlay - before.outs;

      // 이 타석 전 점수. 득점마다 앞서 나가는 순간을 찾는다.
      var offenseRuns = log.isTop ? before.awayScore : before.homeScore;
      final defenseRuns = log.isTop ? before.homeScore : before.awayScore;
      for (final runner in t.scored) {
        batterLines[runner]?.runs++;
        final charged = responsible[runner] ?? log.pitcherId;
        pitcherLines[charged]?.runs++;
        offenseRuns++;
        if (offenseId == winnerId && offenseRuns == defenseRuns + 1) {
          goAheadPitcher = charged;
          winnerPitcherOfRecord = _currentPitcher(box(offenseId));
        }
        responsible.remove(runner);
      }
      // 이 타석으로 누상에 나간 타자는 지금 투수의 책임 주자다.
      if (t.basesAfterPlay.contains(log.batterId)) responsible[log.batterId] = log.pitcherId;
      // 이닝이 끝나면 남은 주자는 지운다.
      if (t.outsAfterPlay >= 3 || log.after.inning != log.inning || log.after.isTop != log.isTop) responsible.clear();

      final after = log.after;
      leadWhenLeft[p.playerId] = log.isTop ? after.homeScore - after.awayScore : after.awayScore - after.homeScore;
    }

    String? win, loss, save;
    final holds = <String>[];
    if (winnerId != null) {
      final w = box(winnerId);
      final starter = w.pitchers.first;
      win = winnerPitcherOfRecord;
      if (win == starter.playerId && starter.outs < 15 && w.pitchers.length > 1) {
        final relievers = w.pitchers.skip(1).toList()..sort((a, b) => b.outs.compareTo(a.outs));
        win = relievers.first.playerId;
      }
      loss = goAheadPitcher;

      bool saveSituation(PitcherLine p) {
        final e = entry[p.playerId];
        if (e == null || e.lead <= 0) return false;
        return (e.lead <= 3 && p.outs >= 3) || e.lead <= e.tyingMargin || p.outs >= 9;
      }

      final finisher = w.pitchers.last;
      if (w.pitchers.length > 1 && finisher.playerId != win && saveSituation(finisher)) {
        save = finisher.playerId;
      }
      for (final p in w.pitchers.skip(1)) {
        if (p == finisher || p.playerId == win) continue;
        final e = entry[p.playerId];
        if (e == null || e.lead <= 0 || p.outs < 1) continue;
        final situation = e.lead <= 3 || e.lead <= e.tyingMargin;
        if (situation && (leadWhenLeft[p.playerId] ?? 0) > 0) holds.add(p.playerId);
      }
    }
    return BoxScore._(away, home, win, loss, save, holds);
  }

  /// 지금까지 이 팀에서 마지막으로 던진 투수.
  static String _currentPitcher(TeamBox t) => t.pitchers.last.playerId;

  final TeamBox away;
  final TeamBox home;
  final String? winningPitcherId;
  final String? losingPitcherId;
  final String? savePitcherId;
  final List<String> holdPitcherIds;
}
