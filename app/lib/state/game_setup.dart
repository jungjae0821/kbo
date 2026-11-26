import 'package:kbo_engine/kbo_engine.dart';

import '../data/app_data.dart';
import 'auto_bullpen.dart';

/// 시뮬레이션 준비 화면에서 고른 것: 두 팀, 선발투수, 불펜 운용, 타순, 승리 예측(또는 예측 없이 돌려보기).
/// "다시하기"는 직전 설정을 그대로 채워서 준비 화면을 연다 (초안 판정 14).
class GameSetup {
  GameSetup();

  /// 끝난 경기의 설정을 이어받는다 (예측은 다시 고른다).
  GameSetup.from(GameEngine engine, {Map<String, BullpenPlan> bullpens = const {}})
      : awayId = engine.awayTeamId,
        homeId = engine.homeTeamId {
    for (final t in [engine.awayTeamId, engine.homeTeamId]) {
      starters[t] = engine.startingPitcherFor(t);
      orders[t] = engine.startingBattingOrderFor(t);
      final plan = bullpens[t];
      if (plan != null) this.bullpens[t] = plan;
    }
  }

  String? awayId;
  String? homeId;
  final Map<String, String> starters = {};
  final Map<String, List<String>> orders = {};

  /// 사용자가 바꾼 불펜 운용. 없는 팀은 [suggestedBullpen].
  final Map<String, BullpenPlan> bullpens = {};
  String? _predictedWinnerId;
  bool _watchOnly = false;

  String? get predictedWinnerId => _predictedWinnerId;

  /// 이길 팀을 고른다. 예측 없이 돌려보기는 꺼진다.
  set predictedWinnerId(String? id) {
    _predictedWinnerId = id;
    if (id != null) _watchOnly = false;
  }

  /// 예측 없이 돌려보기: 채점·기록 없이 두 팀 모두 앱이 운영한다.
  bool get watchOnly => _watchOnly;
  set watchOnly(bool value) {
    _watchOnly = value;
    if (value) _predictedWinnerId = null;
  }

  /// 예측 단계에서 시작할 수 있는가.
  bool get hasPrediction => _predictedWinnerId != null || _watchOnly;

  bool get hasTeams => awayId != null && homeId != null;

  /// 팀이 바뀌면 그 팀의 선발·타순·예측을 지운다.
  void setTeams(String? away, String? home) {
    for (final old in [awayId, homeId]) {
      if (old != null && old != away && old != home) {
        starters.remove(old);
        orders.remove(old);
        bullpens.remove(old);
      }
    }
    if (_predictedWinnerId != away && _predictedWinnerId != home) _predictedWinnerId = null;
    awayId = away;
    homeId = home;
  }

  String starterOf(AppData data, String teamId) => starters[teamId] ?? data.season.lineups[teamId]!.pitcherId;

  List<String> orderOf(AppData data, String teamId) =>
      orders[teamId] ?? autoOrder(data, teamId);

  bool isAutoOrder(AppData data, String teamId) {
    final order = orderOf(data, teamId);
    final auto = autoOrder(data, teamId);
    for (var i = 0; i < 9; i++) {
      if (order[i] != auto[i]) return false;
    }
    return true;
  }

  static List<String> autoOrder(AppData data, String teamId) =>
      [for (final s in data.season.lineups[teamId]!.battingOrder) s.playerId];

  /// 자동 라인업의 수비 위치. 바꿔 넣은 타자는 빠진 타자의 자리를 맡는다.
  String positionOf(AppData data, String teamId, String playerId) {
    final slots = data.season.lineups[teamId]!.battingOrder;
    for (final s in slots) {
      if (s.playerId == playerId) return s.position;
    }
    final auto = autoOrder(data, teamId);
    final order = orderOf(data, teamId);
    final outs = [for (final id in auto) if (!order.contains(id)) id];
    final ins = [for (final id in order) if (!auto.contains(id)) id];
    final i = ins.indexOf(playerId);
    if (i < 0 || i >= outs.length) return '';
    return slots.firstWhere((s) => s.playerId == outs[i]).position;
  }

  /// 선발 후보: 엔진이 허용하는 투수 중 시즌 선발 출장 기록이 있는 선수 (초안 판정 8).
  /// 선발 등판이 많은 순.
  static List<String> starterCandidates(AppData data, String teamId) {
    final auto = data.season.lineups[teamId]!.pitcherId;
    return [
      for (final id in GameEngine.starterCandidates(data.season, teamId))
        if (data.player(id).pitcherStarts > 0 || id == auto) id,
    ]..sort((a, b) => data.player(b).pitcherStarts.compareTo(data.player(a).pitcherStarts));
  }

  /// 타순에 넣을 수 있는 벤치 타자: 타격 기록이 있고 지금 타순과 선발투수가 아닌 선수. 타석이 많은 순.
  List<String> benchBatters(AppData data, String teamId) {
    final order = orderOf(data, teamId);
    final starter = starterOf(data, teamId);
    return [
      for (final id in GameEngine.batterCandidates(data.season, teamId))
        if (!order.contains(id) && id != starter) id,
    ]..sort((a, b) => (data.player(b).plateAppearances ?? 0).compareTo(data.player(a).plateAppearances ?? 0));
  }

  /// [a]번과 [b]번 타순을 맞바꾼다 (1~9).
  void swapOrder(AppData data, String teamId, int a, int b) {
    final order = List.of(orderOf(data, teamId));
    final t = order[a - 1];
    order[a - 1] = order[b - 1];
    order[b - 1] = t;
    orders[teamId] = order;
  }

  /// [slot]번 타자를 [playerId]로 바꾼다.
  void replaceBatter(AppData data, String teamId, int slot, String playerId) {
    final order = List.of(orderOf(data, teamId));
    order[slot - 1] = playerId;
    orders[teamId] = order;
  }

  void resetOrder(String teamId) => orders.remove(teamId);

  /// 선발을 바꿨는데 그 투수가 타순에 있으면(투타 겸업) 타순을 자동으로 되돌린다.
  void setStarter(AppData data, String teamId, String playerId) {
    if (playerId == data.season.lineups[teamId]!.pitcherId) {
      starters.remove(teamId);
    } else {
      starters[teamId] = playerId;
    }
    if (orderOf(data, teamId).contains(playerId)) orders.remove(teamId);
    // 새 선발이 불펜 운용에 있으면 빼고, 빠진 자리는 기본 운용을 다시 짠다.
    final plan = bullpens[teamId];
    if (plan != null) bullpens[teamId] = plan.without(playerId);
  }

  /// 시즌 기록으로 짠 기본 불펜 운용 (지금 선발 제외).
  BullpenPlan suggestedBullpen(AppData data, String teamId) =>
      BullpenPlan.suggested(data, teamId, starterOf(data, teamId));

  BullpenPlan bullpenOf(AppData data, String teamId) => bullpens[teamId] ?? suggestedBullpen(data, teamId);

  bool isAutoBullpen(AppData data, String teamId) {
    final plan = bullpens[teamId];
    return plan == null || plan.sameAs(suggestedBullpen(data, teamId));
  }

  void setBullpen(String teamId, BullpenPlan plan) => bullpens[teamId] = plan;
  void resetBullpen(String teamId) => bullpens.remove(teamId);

  /// 불펜에 넣을 수 있는 투수: 엔진이 허용하는 투수 중 지금 선발과 타순에 없는 선수. 구원 이닝이 많은 순.
  List<String> bullpenCandidates(AppData data, String teamId) {
    final starter = starterOf(data, teamId);
    final order = orderOf(data, teamId);
    return [
      for (final id in GameEngine.starterCandidates(data.season, teamId))
        if (id != starter && !order.contains(id)) id,
    ]..sort((a, b) => (data.player(b).outsPitched ?? 0).compareTo(data.player(a).outsPitched ?? 0));
  }

  /// 경기에 넘길 두 팀의 불펜 운용.
  Map<String, BullpenPlan> bullpenPlans(AppData data) => {
        for (final t in [awayId!, homeId!]) t: bullpenOf(data, t),
      };

  /// 엔진에 넘길 값. 자동 값은 빼서 넘긴다.
  Map<String, String> get startingPitchers => Map.of(starters);
  Map<String, List<String>> battingOrders(AppData data) => {
        for (final t in [awayId!, homeId!])
          if (!isAutoOrder(data, t)) t: orderOf(data, t),
      };
}
