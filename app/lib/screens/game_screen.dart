import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/auto_bullpen.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../state/saved_game.dart';
import '../theme/kbo_theme.dart';
import '../widgets/field_view.dart';
import '../widgets/frame.dart';
import '../widgets/play_feed.dart';
import '../widgets/player_sheet.dart';
import 'result_screen.dart';

/// 경기 진행: 기존 기능 그대로 (초안 확정 구조 3). 띠에 점수·이닝·아웃·주자,
/// 가운데 타석 기록, 아래 감독 줄(예측한 팀만 투수 교체·대타)과 진행 버튼.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.awayId,
    required this.homeId,
    required this.predictedWinnerId,
    required this.seed,
    this.startingPitchers = const {},
    this.battingOrders = const {},
  }) : restored = null;

  /// 기기에 저장해 둔 중단 경기를 이어서 진행한다.
  GameScreen.resume({super.key, required GameEngine engine, required this.predictedWinnerId})
      : awayId = engine.awayTeamId,
        homeId = engine.homeTeamId,
        seed = engine.seed,
        startingPitchers = const {},
        battingOrders = const {},
        restored = engine;

  final String awayId;
  final String homeId;
  final String predictedWinnerId;
  final int seed;

  /// 경기 전에 고른 선발투수와 타순 (팀 ID → 값). 없으면 자동.
  final Map<String, String> startingPitchers;
  final Map<String, List<String>> battingOrders;

  /// 이어하기로 되살린 엔진. 새 경기면 null.
  final GameEngine? restored;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameEngine? _engine;
  late AppData _data;
  late RecordBook _records;
  late SavedGameStore _savedGame;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine != null) return;
    final scope = AppScope.of(context);
    _data = scope.data.data!;
    _records = scope.records;
    _savedGame = scope.savedGame;
    _engine = widget.restored ??
        GameEngine(
          dataset: _data.season,
          awayTeamId: widget.awayId,
          homeTeamId: widget.homeId,
          seed: widget.seed,
          startingPitchers: widget.startingPitchers,
          battingOrders: widget.battingOrders,
        );
    // 새 경기는 바로 저장하고, 저장된 뒤 채점 전에 꺼진 경기는 이어하자마자 채점한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterChange());
  }

  GameEngine get engine => _engine!;

  /// 타석·교체마다 기기에 저장한다. 끝났으면 채점하고 중단 경기를 지운다.
  void _afterChange() {
    if (engine.state.isFinished) {
      _score();
    } else {
      _savedGame.save(engine, widget.predictedWinnerId);
    }
  }

  /// 예측하지 않은 팀. 이 팀의 투수 교체는 앱이 정한다.
  String get _opponentId => widget.predictedWinnerId == widget.awayId ? widget.homeId : widget.awayId;

  /// 다음 타석 전에 상대 팀 불펜을 움직이고 한 타석 진행한다.
  void _advance() {
    autoPitchingChange(engine, _data, _opponentId);
    engine.step();
  }

  void _step() {
    // 빠르게 두 번 누르면 화면이 바뀌기 전에 끝난 경기에서 한 번 더 들어올 수 있다.
    if (engine.state.isFinished) return;
    setState(_advance);
    _afterChange();
  }

  bool get _myTeamAttacking => (engine.state.isTop ? widget.awayId : widget.homeId) == widget.predictedWinnerId;

  /// 내 팀 수비가 막 시작됐다: 이 공수에서 아직 타석이 없다.
  bool get _defenseJustStarted {
    final s = engine.state;
    if (s.isFinished || _myTeamAttacking) return false;
    final logs = engine.logs;
    return logs.isEmpty || logs.last.inning != s.inning || logs.last.isTop != s.isTop;
  }

  /// 경기 끝 또는 내 팀 수비가 시작될 때까지 진행한다. 그 자리에서 투수 교체를 묻는다.
  void _playToNextDefense() {
    if (engine.state.isFinished) return;
    setState(() {
      do {
        _advance();
      } while (!engine.state.isFinished && !_defenseJustStarted);
    });
    _afterChange();
  }

  /// 경기가 끝나면 한 번만 채점한다. 기록 저장이 끝난 뒤 중단 경기를 지운다.
  Future<void> _score() async {
    final s = engine.state;
    _records.score(GameRecord(
      gameId: engine.gameId,
      awayTeamId: widget.awayId,
      homeTeamId: widget.homeId,
      awayScore: s.awayScore,
      homeScore: s.homeScore,
      predictedWinnerId: widget.predictedWinnerId,
      winnerTeamId: engine.winnerTeamId,
      finishedAt: DateTime.now(),
      engineVersion: GameEngine.version,
      dataVersion: _data.season.dataVersion,
    ));
    await _records.saved;
    _savedGame.clear(gameId: engine.gameId);
  }

  /// 예측한 팀만 교체할 수 있다. 공격 중이면 대타, 수비 중이면 투수 교체.
  Future<void> _substitute() async {
    final teamId = widget.predictedWinnerId;
    final attacking = _myTeamAttacking;
    final outId = attacking ? engine.nextBatterFor(teamId) : engine.pitcherFor(teamId);
    final outName = _data.player(outId).name;
    final order = engine.battingOrderFor(teamId).indexOf(outId) + 1;
    final candidates = attacking ? engine.pinchHitterCandidates(teamId) : engine.pitcherCandidates(teamId);
    candidates.sort((a, b) => attacking
        ? (_data.player(b).plateAppearances ?? 0).compareTo(_data.player(a).plateAppearances ?? 0)
        : (_data.player(b).outsPitched ?? 0).compareTo(_data.player(a).outsPitched ?? 0));
    final chosen = await pickPlayer(
      context,
      title: attacking ? '$order번 $outName 대신 칠 타자' : '$outName 대신 던질 투수',
      candidateIds: candidates,
      data: _data,
      pitcher: !attacking,
      emptyMessage: '남은 교체 선수가 없습니다.',
    );
    if (chosen == null || !mounted) return;
    final name = _data.player(chosen).name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepAll(attacking ? '$outName 대신 ${withObject(name)} 낼까요?' : '$outName 대신 ${withObject(name)} 올릴까요?')),
        content: Text(keepAll('$outName 선수는 이 경기에 다시 나올 수 없습니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(attacking ? '대타 내기' : '투수 교체')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      if (attacking) {
        engine.pinchHit(teamId, chosen);
      } else {
        engine.substitutePitcher(teamId, chosen);
      }
    });
    _afterChange();
  }

  void _openResult() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(engine: engine, predictedWinnerId: widget.predictedWinnerId),
    ));
  }

  /// 지금 타석의 그라운드: 주자 이름, 마운드의 투수, 홈의 타자.
  Widget _field(TeamSummary away, TeamSummary home) {
    final s = engine.state;
    final offenseId = s.isTop ? away.id : home.id;
    final defenseId = s.isTop ? home.id : away.id;
    final batterId = engine.nextBatterFor(offenseId);
    final pitcherId = engine.pitcherFor(defenseId);
    final b = _data.player(batterId), p = _data.player(pitcherId);
    var ab = 0, hits = 0, came = 0;
    for (final l in engine.logs.where((l) => l.batterId == batterId)) {
      came++;
      if (l.outcome != PlateOutcome.walk && l.outcome != PlateOutcome.hitByPitch && l.transition.note != PlayNote.runScoredOnOut) ab++;
      if (isHit(l.outcome)) hits++;
    }
    final faced = engine.logs.where((l) => l.pitcherId == pitcherId).length;
    final order = (s.isTop ? s.awayBattingIndex : s.homeBattingIndex) + 1;
    return FieldView(
      runners: [for (final id in s.bases) id == null ? null : _data.player(id).name],
      pitcherName: p.name,
      pitcherDetail: '오늘 $faced타자, 평균자책 ${era(p.era)}',
      batterName: '$order번 ${b.name}',
      batterDetail: '타율 ${avg(b.battingAverage)}, ${came == 0 ? '오늘 첫 타석' : '오늘 $ab타수 $hits안타'}',
      outs: s.outs.clamp(0, 3),
      // 이닝은 위 띠에 있으므로 여기는 공격 팀만.
      situation: '${(s.isTop ? away : home).shortName} 공격',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = engine.state;
    final away = _data.team(widget.awayId);
    final home = _data.team(widget.homeId);
    final finished = s.isFinished;
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final predicted = _data.team(widget.predictedWinnerId);
    final mine = widget.predictedWinnerId;

    return AppFrame(
      band: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BandTitle(
            title: '가상 경기',
            back: true,
            trailing: Text(
              '예측 ${predicted.shortName}',
              style: text.bodySmall!.copyWith(color: k.bandSub),
            ),
          ),
          ScoreBand(
            awayName: away.shortName,
            awayScore: s.awayScore,
            homeName: home.shortName,
            homeScore: s.homeScore,
            center: finished ? '경기 종료' : halfLabel(s.inning, s.isTop),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 위: 그라운드 (주자·투수·타자·아웃). 아래 문자 기록과 면 색으로 나눈다.
          ColoredBox(
            color: k.stripe,
            child: SizedBox(
              height: 226,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: finished ? _FinalNote(engine: engine) : _field(away, home),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: _PlayFeed(data: _data, engine: engine, away: away, home: home),
            ),
          ),
        ],
      ),
      dock: finished
          ? FilledButton(onPressed: _openResult, child: const Text('경기 결과 보기'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ManagerBar(
                  teamName: predicted.shortName,
                  attacking: _myTeamAttacking,
                  asking: _defenseJustStarted &&
                      engine.canSubstitutePitcher(mine) &&
                      !engine.substitutions.any(
                        (x) => x.kind == SubstitutionKind.pitcher && x.inning == s.inning && x.isTop == s.isTop,
                      ),
                  halfText: halfLabel(s.inning, s.isTop),
                  playerText: _myTeamAttacking
                      ? '다음 타자 ${(s.isTop ? s.awayBattingIndex : s.homeBattingIndex) + 1}번 '
                          '${_data.player(engine.nextBatterFor(mine)).name}'
                      : '투수 ${_data.player(engine.pitcherFor(mine)).name}'
                          '${engine.canSubstitutePitcher(mine) ? '' : ', 첫 타자 상대 전'}',
                  // 투수는 한 타자 이상 상대한 뒤에만 바꿀 수 있다 (야구 규칙 5.10).
                  onPressed: _myTeamAttacking || engine.canSubstitutePitcher(mine) ? _substitute : null,
                ),
                const SizedBox(height: 8),
                ActionRow(
                  secondary: FilledButton(style: bandButtonStyle(context, height: 56), onPressed: _playToNextDefense, child: const Text('다음 수비까지')),
                  primary: FilledButton(onPressed: _step, child: const Text('다음 타석')),
                ),
              ],
            ),
    );
  }
}

/// 타석 기록: 아래에서 위로 쌓이고, 이닝 공수가 바뀌는 곳에만 제목이 한 번 나온다.
/// 남은 높이에 온전히 들어가는 줄만 넣어 반쯤 잘린 줄이 보이지 않게 한다.
class _PlayFeed extends StatelessWidget {
  const _PlayFeed({required this.data, required this.engine, required this.away, required this.home});

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;

  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final k = context.kbo;
    final scaler = MediaQuery.textScalerOf(context);
    final events = playEvents(engine.logs, engine.substitutions);
    final rowHeight = scaler.scale(14) * 1.5 + playRowPadding * 2 + _gap;
    final headerHeight = scaler.scale(12) * 1.3 + HalfHeader.top + HalfHeader.bottom;

    if (events.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(keepAll('다음 타석을 누르면 ${away.shortName}의 1번 타자부터 경기가 시작됩니다.'),
              style: text.bodyMedium!.copyWith(color: k.inkSub)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final groups = <((int, bool), List<Object>)>[];
        var used = 0.0;
        for (final event in events.reversed) {
          final half = eventHalf(event);
          final newGroup = groups.isEmpty || groups.last.$1 != half;
          final needed = rowHeight + (newGroup ? headerHeight : 0);
          if (used + needed > box.maxHeight) break;
          used += needed;
          if (newGroup) groups.add((half, <Object>[]));
          groups.last.$2.add(event);
        }
        final latest = events.last;
        final children = <Widget>[];
        for (final (half, items) in groups.reversed) {
          children.add(HalfHeader(inning: half.$1, isTop: half.$2, attackingTeam: half.$2 ? away.shortName : home.shortName));
          for (final event in items.reversed) {
            children.add(Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: event is PlateAppearanceLog
                  ? PlateRow(log: event, batterName: data.player(event.batterId).name, latest: identical(event, latest))
                  : SubstitutionRow(
                      sub: event as Substitution,
                      inName: data.player(event.inPlayerId).name,
                      outName: data.player(event.outPlayerId).name,
                      teamName: data.team(event.teamId).shortName,
                    ),
            ));
          }
        }
        return ClipRect(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
      },
    );
  }
}

/// 예측한 팀의 감독 자리. 수비가 막 시작되면 투수 교체를 묻고, 공격 중에는 대타를 낼 수 있다.
class _ManagerBar extends StatelessWidget {
  const _ManagerBar({
    required this.teamName,
    required this.attacking,
    required this.asking,
    required this.halfText,
    required this.playerText,
    required this.onPressed,
  });

  final String teamName;
  final bool attacking;
  final bool asking;
  final String halfText;
  final String playerText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final headline = asking ? '$halfText $teamName 수비 시작' : '$teamName ${attacking ? '공격' : '수비'} 중';
    final detail = asking ? '$playerText, 바꿀까요?' : playerText;
    return Panel(
      color: asking ? k.accentSoft : k.stripe,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: asking,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline,
                      style: asking ? base.copyWith(fontWeight: FontWeight.w700) : base.copyWith(color: k.inkSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(detail,
                      style: asking ? base.copyWith(fontWeight: FontWeight.w700) : base,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: bandButtonStyle(context),
            onPressed: onPressed,
            child: Text(attacking ? '대타 내기' : '투수 교체'),
          ),
        ],
      ),
    );
  }
}

/// 경기가 끝났을 때 그라운드 자리에 남기는 한 줄.
class _FinalNote extends StatelessWidget {
  const _FinalNote({required this.engine});
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = engine.state;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('경기가 끝났습니다', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text('${endLabel(s.end!)}, ${s.plateAppearances}타석', style: text.bodyMedium!.copyWith(color: context.kbo.inkSub)),
      ],
    );
  }
}
