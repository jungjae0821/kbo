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
import 'result_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.awayId,
    required this.homeId,
    required this.predictedWinnerId,
    required this.seed,
  });

  final String awayId;
  final String homeId;
  final String predictedWinnerId;
  final int seed;

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
    );
  }

  GameEngine get engine => _engine!;

  void _step() {
    setState(() => engine.step());
    if (engine.state.isFinished) _score();
  }

  void _playToEnd() {
    setState(() => engine.playToEnd());
    _score();
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
    final logs = engine.logs;
    final finished = s.isFinished;

    return PopScope(
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: GroundLayout(
        title: '가상 경기',
        ground: _GameGround(data: _data, engine: engine, away: away, home: home),
        sheet: SheetBody(
          children: [
            LineScore(awayName: away.shortName, homeName: home.shortName, state: s, logs: logs),
            const SizedBox(height: 14),
            if (logs.isEmpty)
              Text(keepAll('첫 타석을 진행하세요. ${away.shortName}의 1번 타자가 나옵니다.'), style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final (i, log) in logs.reversed.take(3).indexed)
                PlateRow(log: log, batterName: _data.player(log.batterId).name, emphasize: i == 0),
            const SizedBox(height: 10),
            _PredictionLine(
              teamName: _data.team(widget.predictedWinnerId).name,
              finished: finished,
            ),
          ],
        ),
        actions: finished
            ? ActionRow(
                primary: FilledButton(onPressed: _openResult, child: const Text('경기 결과 보기')),
              )
            : ActionRow(
                primary: FilledButton(onPressed: _step, child: const Text('다음 타석')),
                secondary: FilledButton(
                  style: secondaryButtonStyle(context),
                  onPressed: _playToEnd,
                  child: const Text('끝까지'),
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
  const _GameGround({required this.data, required this.engine, required this.away, required this.home});

  final AppData data;
  final GameEngine engine;
  final TeamSummary away;
  final TeamSummary home;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final s = engine.state;
    final height = MediaQuery.sizeOf(context).height;
    final halfDiagonal = (height * 0.12).clamp(70.0, 112.0);

    // 다음 타석의 타자·투수 (경기가 끝났으면 표시하지 않는다).
    FieldTag? batter;
    FieldTag? pitcher;
    if (!s.isFinished) {
      final offense = data.season.lineups[s.isTop ? away.id : home.id]!;
      final defense = data.season.lineups[s.isTop ? home.id : away.id]!;
      final slot = offense.battingOrder[s.isTop ? s.awayBattingIndex : s.homeBattingIndex];
      final b = data.player(slot.playerId);
      final p = data.player(defense.pitcherId);
      batter = FieldTag(b.id, b.name, '${slot.order}번 ${avg(b.battingAverage)}');
      pitcher = FieldTag(p.id, p.name, '평균자책 ${era(p.era)}');
    }
    FieldTag? runner(String? id) => id == null ? null : FieldTag(id, data.player(id).name);

    final inningText = s.isFinished ? '경기 종료' : halfLabel(s.inning, s.isTop);
    final attack = s.isFinished ? endLabel(s.end!) : '${s.isTop ? away.shortName : home.shortName} 공격';

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
            label: '$inningText, ${away.name} ${s.awayScore}점, ${home.name} ${s.homeScore}점',
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
            label: '주자 ${basesLabel(s.bases)}, ${s.outs}아웃'
                '${batter != null ? ', 타자 ${batter.name}, 투수 ${pitcher!.name}' : ''}',
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
