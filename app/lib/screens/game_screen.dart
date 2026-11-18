import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/feed_layout.dart';
import '../widgets/line_score.dart';
import '../widgets/substitute_sheet.dart';
import 'result_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.awayId,
    required this.homeId,
    required this.predictedWinnerId,
    required this.seed,
    this.startingPitchers = const {},
  });

  final String awayId;
  final String homeId;
  final String predictedWinnerId;
  final int seed;

  /// 경기 전에 고른 선발투수 (팀 ID → 선수 ID). 없으면 자동 선발.
  final Map<String, String> startingPitchers;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameEngine? _engine;
  late AppData _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine != null) return;
    _data = AppScope.of(context).data.data!;
    _engine = GameEngine(
      dataset: _data.season,
      awayTeamId: widget.awayId,
      homeTeamId: widget.homeId,
      seed: widget.seed,
      startingPitchers: widget.startingPitchers,
    );
  }

  GameEngine get engine => _engine!;

  void _step() {
    setState(() => engine.step());
    if (engine.state.isFinished) _score();
  }

  /// 내 팀이 지금 공격 중인가.
  bool get _myTeamAttacking =>
      (engine.state.isTop ? widget.awayId : widget.homeId) == widget.predictedWinnerId;

  /// 내 팀 수비가 막 시작됐다: 이 공수에서 아직 타석이 없다.
  bool get _defenseJustStarted {
    final s = engine.state;
    if (s.isFinished || _myTeamAttacking) return false;
    final logs = engine.logs;
    return logs.isEmpty || logs.last.inning != s.inning || logs.last.isTop != s.isTop;
  }

  /// 경기 끝 또는 내 팀 수비가 시작될 때까지 진행한다. 그 자리에서 투수 교체를 묻는다.
  void _playToNextDefense() {
    setState(() {
      do {
        engine.step();
      } while (!engine.state.isFinished && !_defenseJustStarted);
    });
    if (engine.state.isFinished) _score();
  }

  /// 경기가 끝나면 한 번만 채점한다 (RecordBook이 경기 ID 중복을 막는다).
  void _score() {
    final s = engine.state;
    AppScope.of(context).records.score(GameRecord(
          gameId: engine.gameId,
          awayTeamId: widget.awayId,
          homeTeamId: widget.homeId,
          awayScore: s.awayScore,
          homeScore: s.homeScore,
          predictedWinnerId: widget.predictedWinnerId,
          winnerTeamId: engine.winnerTeamId,
          finishedAt: DateTime.now(),
        ));
  }

  /// 예측한 팀만 교체할 수 있다. 공격 중이면 대타, 수비 중이면 투수 교체.
  Future<void> _substitute() async {
    final teamId = widget.predictedWinnerId;
    final attacking = _myTeamAttacking;
    final kind = attacking ? SubstitutionKind.pinchHitter : SubstitutionKind.pitcher;
    final outId = attacking ? engine.nextBatterFor(teamId) : engine.pitcherFor(teamId);
    final outName = _data.player(outId).name;
    final order = engine.battingOrderFor(teamId).indexOf(outId) + 1;
    final chosen = await pickSubstitute(
      context,
      kind: kind,
      data: _data,
      candidateIds: attacking ? engine.pinchHitterCandidates(teamId) : engine.pitcherCandidates(teamId),
      outPlayerName: outName,
      title: attacking ? '$order번 $outName 대신 칠 타자' : '$outName 대신 던질 투수',
    );
    if (chosen == null || !mounted) return;
    // 결과는 그라운드 이름표와 최근 기록의 교체 줄로 바로 보인다.
    setState(() {
      if (attacking) {
        engine.pinchHit(teamId, chosen);
      } else {
        engine.substitutePitcher(teamId, chosen);
      }
    });
  }

  void _openResult() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(engine: engine, predictedWinnerId: widget.predictedWinnerId),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('경기를 그만둘까요?'),
        content: Text(keepAll('진행 중인 경기와 예측은 아직 저장되지 않아 처음부터 다시 해야 합니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('계속 보기')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('그만두기')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
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
    final inningText = finished ? '경기 종료' : halfLabel(s.inning, s.isTop);

    return PopScope(
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: FeedScaffold(
        title: '가상 경기',
        appBarActions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                finished ? '내 예측 ${predicted.shortName}, 채점 완료' : '내 예측 ${predicted.shortName} 승리',
                style: text.bodySmall?.copyWith(color: k.inkSub),
              ),
            ),
          ),
        ],
        header: StatusBar(
          awayName: away.shortName,
          awayScore: s.awayScore,
          homeName: home.shortName,
          homeScore: s.homeScore,
          center: inningText,
          outs: finished ? null : s.outs.clamp(0, 3),
          semanticsLabel: '$inningText, ${s.outs}아웃, ${away.name} ${s.awayScore}점, ${home.name} ${s.homeScore}점',
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _PlayFeed(data: _data, engine: engine, away: away, home: home)),
              const SizedBox(height: 6),
              _AtBatCard(data: _data, engine: engine, away: away, home: home),
            ],
          ),
        ),
        // 교체 묻기와 진행 버튼은 피드 밖 고정 영역에 둬서 스크롤 없이 항상 보인다.
        dock: finished
            ? ActionRow(
                primary: FilledButton(onPressed: _openResult, child: const Text('경기 결과 보기')),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ManagerBar(
                    teamName: predicted.shortName,
                    attacking: _myTeamAttacking,
                    askingAtDefenseStart: _defenseJustStarted &&
                        !engine.substitutions.any((x) =>
                            x.kind == SubstitutionKind.pitcher && x.inning == s.inning && x.isTop == s.isTop),
                    halfText: halfLabel(s.inning, s.isTop),
                    playerText: _myTeamAttacking
                        ? '다음 타자 ${(s.isTop ? s.awayBattingIndex : s.homeBattingIndex) + 1}번 '
                            '${_data.player(engine.nextBatterFor(widget.predictedWinnerId)).name}'
                        : '투수 ${_data.player(engine.pitcherFor(widget.predictedWinnerId)).name}',
                    onPressed: _substitute,
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    primary: FilledButton(onPressed: _step, child: const Text('다음 타석')),
                    secondary: FilledButton(
                      style: secondaryButtonStyle(context),
                      onPressed: _playToNextDefense,
                      child: const Text('다음 수비까지'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 문자중계 피드: 타석과 교체가 아래에서 위로 쌓이고, 이닝 공수가 바뀌는 곳에만 제목이 한 번 나온다.
/// 남은 높이에 온전히 들어가는 칸만 넣는다. 칸마다 한 줄 높이로 고정하고(넘치면 말줄임)
/// 들어갈 수 있는 개수를 미리 세서, 반쯤 잘린 칸이 보이지 않게 한다.
class _PlayFeed extends StatelessWidget {
  const _PlayFeed({required this.data, required this.engine, required this.away, required this.home});

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final events = playEvents(engine.logs, engine.substitutions);
    final rowHeight = scaler.scale(14) * 1.55 + playRowPadding * 2 + _gap;
    final headerHeight = scaler.scale(12) * 1.3 + HalfHeader.top + HalfHeader.bottom;

    if (events.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Bubble(
          child: Text(
            keepAll('첫 타석을 진행하세요. ${away.shortName}의 1번 타자가 나옵니다.'),
            style: text.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      // 최신 칸부터 거꾸로 채운다. 공수 묶음의 제목 높이는 그 묶음의 첫 칸을 넣을 때 함께 잡는다.
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
        children.add(HalfHeader(
          inning: half.$1,
          isTop: half.$2,
          attackingTeam: half.$2 ? away.shortName : home.shortName,
        ));
        for (final event in items.reversed) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: _gap),
            child: event is PlateAppearanceLog
                ? PlateRow(
                    log: event,
                    batterName: data.player(event.batterId).name,
                    emphasize: identical(event, latest),
                    singleLine: true,
                  )
                : SubstitutionRow(
                    sub: event as Substitution,
                    inName: data.player(event.inPlayerId).name,
                    outName: data.player(event.outPlayerId).name,
                    singleLine: true,
                  ),
          ));
        }
      }
      return ClipRect(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    });
  }
}

/// 피드 맨 아래 "지금 타석" 칸: 다음 타자와 투수, 주자 상황.
class _AtBatCard extends StatelessWidget {
  const _AtBatCard({required this.data, required this.engine, required this.away, required this.home});

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final s = engine.state;
    final String title;
    final String detail;
    if (s.isFinished) {
      title = '경기가 끝났습니다';
      detail = '${endLabel(s.end!)}, ${s.plateAppearances}타석';
    } else {
      final offenseId = s.isTop ? away.id : home.id;
      final b = data.player(engine.nextBatterFor(offenseId));
      final p = data.player(engine.pitcherFor(s.isTop ? home.id : away.id));
      final order = (s.isTop ? s.awayBattingIndex : s.homeBattingIndex) + 1;
      title = '$order번 ${b.name} 타석';
      detail = '타율 ${avg(b.battingAverage)}, 투수 ${p.name} 평균자책 ${era(p.era)}';
    }
    return Semantics(
      label: '$title, $detail${s.isFinished ? '' : ', 주자 ${basesLabel(s.bases)}'}',
      excludeSemantics: true,
      child: Bubble(
        stretch: true,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(detail, style: text.bodySmall?.copyWith(color: k.inkSub), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!s.isFinished) ...[
              const SizedBox(width: 8),
              BasesMini(bases: [for (final b in s.bases) b != null]),
            ],
          ],
        ),
      ),
    );
  }
}

/// 내가 예측한 팀의 감독 자리. 수비가 막 시작되면 투수 교체를 묻고,
/// 공격 중에는 다음 타자 대신 대타를 낼 수 있다.
class _ManagerBar extends StatelessWidget {
  const _ManagerBar({
    required this.teamName,
    required this.attacking,
    required this.askingAtDefenseStart,
    required this.halfText,
    required this.playerText,
    required this.onPressed,
  });

  final String teamName;
  final bool attacking;
  final bool askingAtDefenseStart;
  final String halfText;
  final String playerText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    // 좁은 화면에서도 두 줄을 넘지 않게: 위 줄은 상황, 아래 줄은 선수 (각각 한 줄, 넘치면 말줄임).
    final headline = askingAtDefenseStart ? '$halfText $teamName 수비 시작' : '$teamName ${attacking ? '공격' : '수비'} 중';
    final detail = askingAtDefenseStart ? '$playerText, 바꿀까요?' : playerText;
    return DecoratedBox(
      // 지금 묻는 중이면 강조 면으로 칠해 눈에 띄게 한다.
      decoration: BoxDecoration(
        color: askingAtDefenseStart ? k.soft : k.surface,
        borderRadius: BorderRadius.circular(bubbleRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: askingAtDefenseStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: askingAtDefenseStart
                          ? base.copyWith(fontWeight: FontWeight.w700)
                          : base.copyWith(color: k.inkSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail,
                      style: askingAtDefenseStart ? base.copyWith(fontWeight: FontWeight.w700) : base,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: secondaryButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
                backgroundColor: WidgetStatePropertyAll(askingAtDefenseStart ? k.surface : k.fill),
              ),
              onPressed: onPressed,
              child: Text(attacking ? '대타 내기' : '투수 교체'),
            ),
          ],
        ),
      ),
    );
  }
}
