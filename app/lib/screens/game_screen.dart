import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/diamond.dart';
import '../widgets/ground_layout.dart';
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
    // 작은 휴대폰(높이 860 미만의 좁은 화면)은 그라운드를 가로로 접어 기록 칸을 확보한다.
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 840 && screen.height < 860;

    return PopScope(
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: GroundLayout(
        title: '가상 경기',
        ground: _GameGround(
          data: _data,
          engine: engine,
          away: away,
          home: home,
          compact: compact,
          predictedTeamName: _data.team(widget.predictedWinnerId).name,
        ),
        sheet: _GameSheet(
          data: _data,
          engine: engine,
          away: away,
          home: home,
          predictedTeamName: _data.team(widget.predictedWinnerId).name,
          // 작은 화면에서는 내 예측을 그라운드 점수판에 두고 시트는 기록에 쓴다.
          showPrediction: !compact,
        ),
        // 교체 묻기와 진행 버튼은 시트 밖 고정 영역에 둬서 스크롤 없이 항상 보인다.
        actions: finished
            ? ActionRow(
                primary: FilledButton(onPressed: _openResult, child: const Text('경기 결과 보기')),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ManagerBar(
                    teamName: _data.team(widget.predictedWinnerId).shortName,
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

/// 경기 화면 시트: 라인스코어, 최근 기록, 내 예측을 스크롤 없이 보여준다.
/// 기록은 남은 높이에 온전히 들어가는 줄만 최신순으로 넣는다. 줄이 반쯤 잘려 보이지 않게,
/// 줄마다 한 줄 높이로 고정하고(넘치면 말줄임) 들어갈 수 있는 개수를 미리 센다.
class _GameSheet extends StatelessWidget {
  const _GameSheet({
    required this.data,
    required this.engine,
    required this.away,
    required this.home,
    required this.predictedTeamName,
    this.showPrediction = true,
  });

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;
  final String predictedTeamName;
  final bool showPrediction;

  /// 기록 목록 위·아래 고정 요소가 차지하는 최소 높이. 이보다 낮으면 스크롤로 되돌아간다.
  static const _minHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final s = engine.state;
    final logs = engine.logs;
    final text = Theme.of(context).textTheme;
    final lineScore = LineScore(awayName: away.shortName, homeName: home.shortName, state: s, logs: logs);
    final prediction = _PredictionLine(teamName: predictedTeamName, finished: s.isFinished);
    final events = playEvents(logs, engine.substitutions).reversed.toList();

    // 한 줄 높이: bodyMedium 14sp, 행간 1.6, 글자 크기 설정 반영.
    final line = MediaQuery.textScalerOf(context).scale(14) * 1.6;
    final rowHeight = line + 8 + 1; // PlateRow 위아래 4
    final headerHeight = line + 12 + 1; // HalfHeader 위 10, 아래 2

    Widget feed(double available) {
      if (events.isEmpty) {
        return Text(
          keepAll('첫 타석을 진행하세요. ${away.shortName}의 1번 타자가 나옵니다.'),
          style: text.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      }
      final children = <Widget>[];
      var used = 0.0;
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        final half = eventHalf(event);
        final needsHeader = i == 0 || eventHalf(events[i - 1]) != half;
        final needed = rowHeight + (needsHeader ? headerHeight : 0);
        if (used + needed > available) break; // 제목만 남고 줄이 빠지는 경우도 여기서 막힌다.
        used += needed;
        if (needsHeader) {
          children.add(HalfHeader(
            inning: half.$1,
            isTop: half.$2,
            attackingTeam: half.$2 ? away.shortName : home.shortName,
          ));
        }
        children.add(event is PlateAppearanceLog
            ? PlateRow(
                log: event,
                batterName: data.player(event.batterId).name,
                emphasize: i == 0,
                singleLine: true,
              )
            : SubstitutionRow(
                sub: event as Substitution,
                inName: data.player(event.inPlayerId).name,
                outName: data.player(event.outPlayerId).name,
                singleLine: true,
              ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight < _minHeight) {
        // 가로로 눕힌 휴대폰처럼 아주 낮은 화면: 기록을 최근 3개로 줄여 스크롤로 보여준다.
        return SheetBody(children: [
          lineScore,
          const SizedBox(height: 10),
          SizedBox(height: rowHeight * 3 + headerHeight * 2, child: LayoutBuilder(builder: (_, b) => feed(b.maxHeight))),
          if (showPrediction) prediction,
        ]);
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                lineScore,
                const SizedBox(height: 4),
                Expanded(
                  child: LayoutBuilder(builder: (_, b) => ClipRect(child: feed(b.maxHeight))),
                ),
                if (showPrediction) ...[
                  const SizedBox(height: 6),
                  prediction,
                ],
              ],
            ),
          ),
        ),
      );
    });
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
    final headline = askingAtDefenseStart
        ? '$halfText $teamName 수비 시작'
        : '$teamName ${attacking ? '공격' : '수비'} 중';
    final detail = askingAtDefenseStart ? '$playerText, 바꿀까요?' : playerText;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: DecoratedBox(
          decoration: BoxDecoration(color: k.sheetRaised, borderRadius: BorderRadius.circular(16)),
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
                  style: askingAtDefenseStart
                      ? FilledButton.styleFrom(
                          backgroundColor: k.grass,
                          foregroundColor: k.chalk,
                          minimumSize: const Size(64, 48),
                          shape: const StadiumBorder(),
                          textStyle: Theme.of(context).textTheme.labelMedium,
                        )
                      : secondaryButtonStyle(context).copyWith(
                          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
                        ),
                  onPressed: onPressed,
                  child: Text(attacking ? '대타 내기' : '투수 교체'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PredictionLine extends StatelessWidget {
  const _PredictionLine({required this.teamName, required this.finished});
  final String teamName;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '내 예측 ', style: base.copyWith(color: k.inkSub)),
        TextSpan(text: '$teamName 승리', style: base.copyWith(fontWeight: FontWeight.w700)),
        TextSpan(text: finished ? ', 채점 완료' : ', 확정됨', style: base.copyWith(color: k.inkSub)),
      ]),
    );
  }
}

class _GameGround extends StatelessWidget {
  const _GameGround({
    required this.data,
    required this.engine,
    required this.away,
    required this.home,
    required this.compact,
    required this.predictedTeamName,
  });

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;

  /// 작은 휴대폰: 다이아몬드 왼쪽, 점수판 오른쪽으로 높이를 아낀다.
  final bool compact;
  final String predictedTeamName;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final s = engine.state;
    final size = MediaQuery.sizeOf(context);

    // 다음 타석의 타자·투수 (경기가 끝났으면 표시하지 않는다).
    FieldTag? batter;
    FieldTag? pitcher;
    if (!s.isFinished) {
      // 교체가 반영된 현재 타자·투수는 엔진이 가지고 있다.
      final offenseId = s.isTop ? away.id : home.id;
      final b = data.player(engine.nextBatterFor(offenseId));
      final p = data.player(engine.pitcherFor(s.isTop ? home.id : away.id));
      final order = (s.isTop ? s.awayBattingIndex : s.homeBattingIndex) + 1;
      batter = FieldTag(b.id, b.name, '$order번 ${avg(b.battingAverage)}');
      pitcher = FieldTag(p.id, p.name, compact ? '자책 ${era(p.era)}' : '평균자책 ${era(p.era)}');
    }
    FieldTag? runner(String? id) => id == null ? null : FieldTag(id, data.player(id).name);

    final inningText = s.isFinished ? '경기 종료' : halfLabel(s.inning, s.isTop);
    final attack = s.isFinished ? endLabel(s.end!) : '${s.isTop ? away.shortName : home.shortName} 공격';
    final scoreLabel = '$inningText, ${away.name} ${s.awayScore}점, ${home.name} ${s.homeScore}점';
    final fieldLabel = '주자 ${basesLabel(s.bases)}, ${s.outs}아웃'
        '${batter != null ? ', 타자 ${batter.name}, 투수 ${pitcher!.name}' : ''}';

    if (compact) {
      // 점수판 칸 128, 다이아몬드 칸은 남은 폭. 이름표가 칸 밖으로 나가지 않게 반대각을 정한다.
      const boardWidth = 128.0;
      final d = ((size.width - 32 - boardWidth - 8 - 80) / 2).clamp(48.0, 58.0);
      Widget scoreLine(String name, int runs) => Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(name,
                    style: text.titleSmall?.copyWith(color: k.chalkSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('$runs', style: text.displaySmall?.copyWith(color: k.chalk, fontSize: 30, height: 1.15)),
            ],
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                label: fieldLabel,
                excludeSemantics: true,
                child: Diamond(
                  runners: [runner(s.bases[0]), runner(s.bases[1]), runner(s.bases[2])],
                  outs: s.outs.clamp(0, 3),
                  batter: batter,
                  pitcher: pitcher,
                  halfDiagonal: d,
                  compact: true,
                  showOuts: false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: boardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    label: scoreLabel,
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inningText, style: text.titleMedium?.copyWith(color: k.chalk)),
                        Text(attack,
                            style: text.bodySmall?.copyWith(color: k.chalkSub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        scoreLine(away.shortName, s.awayScore),
                        scoreLine(home.shortName, s.homeScore),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutsBoard(outs: s.outs.clamp(0, 3)),
                  const SizedBox(height: 6),
                  Text(
                    keepAll('내 예측 $predictedTeamName 승리'),
                    style: text.bodySmall?.copyWith(color: k.chalkSub),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final halfDiagonal = (size.height * 0.11).clamp(64.0, 104.0);
    Widget score(String name, int runs, bool end) => Column(
          crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(name, style: text.bodyMedium?.copyWith(color: k.chalkSub), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$runs', style: text.displaySmall?.copyWith(color: k.chalk)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Semantics(
            liveRegion: true,
            label: scoreLabel,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(child: score(away.name, s.awayScore, false)),
                  Column(
                    children: [
                      Text(inningText, style: text.titleMedium?.copyWith(color: k.chalk)),
                      Text(attack, style: text.bodySmall?.copyWith(color: k.chalkSub)),
                    ],
                  ),
                  Expanded(child: score(home.name, s.homeScore, true)),
                ],
              ),
            ),
          ),
          Semantics(
            label: fieldLabel,
            excludeSemantics: true,
            child: Diamond(
              runners: [runner(s.bases[0]), runner(s.bases[1]), runner(s.bases[2])],
              outs: s.outs.clamp(0, 3),
              batter: batter,
              pitcher: pitcher,
              halfDiagonal: halfDiagonal,
            ),
          ),
        ],
      ),
    );
  }
}
