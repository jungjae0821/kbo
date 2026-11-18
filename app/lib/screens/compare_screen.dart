import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/feed_layout.dart';
import '../widgets/record_sheet.dart';
import '../widgets/substitute_sheet.dart';
import 'game_screen.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.awayId, required this.homeId});

  final String awayId;
  final String homeId;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String? _pick;

  /// 경기 전에 고른 선발투수. 비어 있으면 자동 선정 선발.
  final Map<String, String> _starters = {};

  String _starterOf(AppData data, String teamId) =>
      _starters[teamId] ?? data.season.lineups[teamId]!.pitcherId;

  Future<void> _changeStarter(AppData data, String teamId) async {
    final current = _starterOf(data, teamId);
    final chosen = await pickSubstitute(
      context,
      kind: SubstitutionKind.pitcher,
      data: data,
      candidateIds: [
        for (final id in GameEngine.starterCandidates(data.season, teamId))
          if (id != current) id,
      ],
      outPlayerName: data.player(current).name,
      title: '${data.team(teamId).shortName} 선발투수 고르기',
      confirmNoReturn: false,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      if (chosen == data.season.lineups[teamId]!.pitcherId) {
        _starters.remove(teamId);
      } else {
        _starters[teamId] = chosen;
      }
    });
  }

  Future<void> _confirm(AppData data) async {
    final winner = data.team(_pick!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepAll('${winner.name} 승리로 확정할까요?')),
        content: Text(keepAll(
            '확정하면 경기가 끝날 때까지 바꿀 수 없습니다. 맞히면 ${RecordBook.pointsPerHit}점을 받습니다.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('다시 고르기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확정하고 시작'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          awayId: widget.awayId,
          homeId: widget.homeId,
          predictedWinnerId: _pick!,
          seed: Random().nextInt(2147483645),
          startingPitchers: Map.of(_starters),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data.data!;
    final away = data.team(widget.awayId);
    final home = data.team(widget.homeId);
    final k = context.kbo;
    final text = Theme.of(context).textTheme;

    Widget pickRow(String side, TeamSummary team) => TeamPickRow(
          side: side,
          name: team.name,
          detail: '${team.wins}승 ${team.losses}패 ${team.ties}무',
          selected: _pick == team.id,
          radio: true,
          onTap: () => setState(() => _pick = team.id),
          semanticsLabel: '$side ${team.name} 승리 예측',
        );

    final awayP = data.player(_starterOf(data, away.id));
    final homeP = data.player(_starterOf(data, home.id));
    String? replaced(String teamId) {
      final auto = data.season.lineups[teamId]!.pitcherId;
      return _starterOf(data, teamId) == auto ? null : '자동 선발 ${data.player(auto).name} 대신';
    }

    Widget card(Widget child) => Bubble(stretch: true, padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), child: child);

    return FeedScaffold(
      title: '전력 비교와 예측',
      // 예측 선택은 스크롤하지 않는 위쪽 고정 칸.
      header: Bubble(
        stretch: true,
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text('어느 팀이 이길까요?', style: text.titleMedium),
            ),
            pickRow('원정', away),
            const SizedBox(height: 4),
            pickRow('홈', home),
          ],
        ),
      ),
      body: FeedList(
        children: [
          const FeedHeading('시즌 전력', first: true),
          card(_AxisTable(
            awayName: away.shortName,
            homeName: home.shortName,
            rows: [
              _Cmp.num('승률', away.winRate, home.winRate, avg, higherIsBetter: true),
              _Cmp.num('득점', away.runsScored.toDouble(), home.runsScored.toDouble(), _int, higherIsBetter: true),
              _Cmp.num('실점', away.runsAllowed.toDouble(), home.runsAllowed.toDouble(), _int, higherIsBetter: false),
              _Cmp.num('팀 타율', away.battingAverage, home.battingAverage, avg, higherIsBetter: true),
              _Cmp.num('팀 홈런', away.homeRuns?.toDouble(), home.homeRuns?.toDouble(), _int, higherIsBetter: true),
              _Cmp.num('팀 평균자책', away.era, home.era, era, higherIsBetter: false),
            ],
          )),
          const FeedHeading('선발 맞대결'),
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AxisTable(
                rows: [
                  _Cmp.text('선발', awayP.name, homeP.name, strong: true),
                  if (replaced(away.id) != null || replaced(home.id) != null)
                    _Cmp.text('', replaced(away.id) ?? '', replaced(home.id) ?? '', accent: true),
                  _Cmp.num('평균자책', awayP.era, homeP.era, era, higherIsBetter: false),
                  _Cmp.text('승패', '${awayP.wins ?? 0}승 ${awayP.losses ?? 0}패', '${homeP.wins ?? 0}승 ${homeP.losses ?? 0}패'),
                  _Cmp.text('이닝', awayP.inningsPitched ?? '—', homeP.inningsPitched ?? '—'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (i, team) in [away, home].indexed) ...[
                    if (i == 1) const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: secondaryButtonStyle(context).copyWith(
                          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
                          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
                        ),
                        onPressed: () => _changeStarter(data, team.id),
                        child: Text('${team.shortName} 선발 바꾸기', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          )),
          const FeedHeading('타순'),
          card(_LineupCards(data: data, awayId: away.id, homeId: home.id)),
          const SizedBox(height: 16),
          Text(
            keepAll('예측은 확정하면 경기가 끝날 때까지 바꿀 수 없습니다. 무승부면 0점이고 적중률 계산에서 빠집니다.'),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: k.inkSub),
          ),
        ],
      ),
      dock: ActionRow(
        primary: FilledButton(
          onPressed: _pick == null ? null : () => _confirm(data),
          child: Text(_pick == null ? '이길 팀을 고르세요' : '${data.team(_pick!).shortName} 승리로 확정'),
        ),
      ),
    );
  }
}

String _int(double v) => '${v.round()}';

/// 가운데 항목 이름을 축으로 두 팀 값을 좌우에 놓는 한 줄.
class _Cmp {
  _Cmp.num(this.label, double? a, double? h, String Function(double) f, {required bool higherIsBetter})
      : away = a == null ? '—' : f(a),
        home = h == null ? '—' : f(h),
        better = (a == null || h == null || a == h)
            ? 0
            : ((higherIsBetter ? a > h : a < h) ? -1 : 1),
        strong = false,
        accent = false;

  _Cmp.text(this.label, this.away, this.home, {this.strong = false, this.accent = false}) : better = 0;

  final String label;
  final String away;
  final String home;

  /// 더 나은 쪽: -1 원정, 1 홈, 0 같음·비교 안 함.
  final int better;
  final bool strong;
  final bool accent;
}

/// 시트 위에 카드 없이 놓는 비교표. 더 나은 값은 굵게 쓴다.
class _AxisTable extends StatelessWidget {
  const _AxisTable({required this.rows, this.awayName, this.homeName});

  final List<_Cmp> rows;
  final String? awayName;
  final String? homeName;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final sub = base.copyWith(color: k.inkSub);
    final accent = Theme.of(context).textTheme.bodySmall!.copyWith(color: k.accentText);

    Widget line(String a, String label, String h, TextStyle sa, TextStyle sh, {TextStyle? sl}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Text(keepAll(a), style: sa)),
              Expanded(flex: 2, child: Text(label, style: sl ?? sub, textAlign: TextAlign.center)),
              Expanded(flex: 3, child: Text(keepAll(h), style: sh, textAlign: TextAlign.end)),
            ],
          ),
        );

    return Column(
      children: [
        if (awayName != null) ExcludeSemantics(child: line(awayName!, '', homeName!, sub, sub)),
        for (final r in rows)
          Semantics(
            label: r.label.isEmpty ? '${r.away} ${r.home}' : '${r.label}, ${r.away} 대 ${r.home}',
            excludeSemantics: true,
            child: r.accent
                ? line(r.away, '', r.home, accent, accent)
                : line(
                    r.away,
                    r.label,
                    r.home,
                    r.strong || r.better == -1 ? bold : base,
                    r.strong || r.better == 1 ? bold : base,
                  ),
          ),
      ],
    );
  }
}

/// 양 팀 타순을 나란히 적은 라인업 카드. 포지션은 전광판처럼 한 글자.
class _LineupCards extends StatelessWidget {
  const _LineupCards({required this.data, required this.awayId, required this.homeId});
  final AppData data;
  final String awayId;
  final String homeId;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final sub = base.copyWith(color: k.inkSub);
    final bold = base.copyWith(fontWeight: FontWeight.w700);

    Widget column(String teamId) {
      final lineup = data.season.lineups[teamId]!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(data.team(teamId).shortName, style: sub),
          ),
          for (final slot in lineup.battingOrder)
            Semantics(
              label: '${slot.order}번 ${positionLabel(slot.position)} ${data.player(slot.playerId).name}, '
                  '타율 ${avg(data.player(slot.playerId).battingAverage)}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 18, child: Text('${slot.order}', style: sub)),
                    SizedBox(width: 20, child: Text(positionShort(slot.position), style: sub)),
                    Expanded(
                      child: Text(
                        data.player(slot.playerId).name,
                        style: bold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(avg(data.player(slot.playerId).battingAverage), style: base),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(awayId)),
        const SizedBox(width: 20),
        Expanded(child: column(homeId)),
      ],
    );
  }
}
