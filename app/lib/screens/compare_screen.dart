import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
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
  late String _lineupTeam = widget.awayId;

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
        content: Text(keepAll('확정하면 경기가 끝날 때까지 바꿀 수 없습니다. 맞히면 100점을 받습니다.')),
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

    return GroundLayout(
      title: '전력 비교와 예측',
      ground: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _GroundTeam(label: '원정', team: away),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'vs',
                style: text.titleMedium?.copyWith(color: k.chalkSub),
              ),
            ),
            Expanded(
              child: _GroundTeam(label: '홈', team: home, end: true),
            ),
          ],
        ),
      ),
      sheet: SheetBody(
        children: [
          const SheetHeading('시즌 전력', first: true),
          _CompareTable(
            rows: [
              _Cmp(
                '승률',
                away.winRate,
                home.winRate,
                (v) => avg(v),
                higherIsBetter: true,
              ),
              _Cmp(
                '득점',
                away.runsScored.toDouble(),
                home.runsScored.toDouble(),
                (v) => '${v.round()}',
                higherIsBetter: true,
              ),
              _Cmp(
                '실점',
                away.runsAllowed.toDouble(),
                home.runsAllowed.toDouble(),
                (v) => '${v.round()}',
                higherIsBetter: false,
              ),
              _Cmp(
                '팀 타율',
                away.battingAverage,
                home.battingAverage,
                avg,
                higherIsBetter: true,
              ),
              _Cmp(
                '팀 홈런',
                away.homeRuns?.toDouble(),
                home.homeRuns?.toDouble(),
                (v) => '${v.round()}',
                higherIsBetter: true,
              ),
              _Cmp('팀 평균자책', away.era, home.era, era, higherIsBetter: false),
            ],
            awayName: away.shortName,
            homeName: home.shortName,
          ),
          const SheetHeading('선발투수'),
          // 두 카드 높이를 맞춰 '선발 바꾸기' 버튼이 같은 줄에 오게 한다.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, id) in [away.id, home.id].indexed) ...[
                  if (i == 1) const SizedBox(width: 8),
                  Expanded(
                    child: _Pitcher(
                      data: data,
                      teamId: id,
                      pitcherId: _starterOf(data, id),
                      onChange: () => _changeStarter(data, id),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SheetHeading('타순'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: away.id, label: Text(away.name)),
              ButtonSegment(value: home.id, label: Text(home.name)),
            ],
            selected: {_lineupTeam},
            onSelectionChanged: (s) => setState(() => _lineupTeam = s.first),
          ),
          const SizedBox(height: 8),
          _Lineup(data: data, teamId: _lineupTeam),
          const SheetHeading('어느 팀이 이길까요?'),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: away.id,
                label: Text('${away.shortName} 승리'),
              ),
              ButtonSegment(
                value: home.id,
                label: Text('${home.shortName} 승리'),
              ),
            ],
            selected: {?_pick},
            onSelectionChanged: (s) =>
                setState(() => _pick = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 8),
          Text(
            keepAll('경기 전에 한 팀을 골라 확정해야 시작할 수 있습니다. 무승부면 0점이고 적중률 계산에서 빠집니다.'),
            style: text.bodySmall?.copyWith(color: k.inkSub),
          ),
        ],
      ),
      actions: ActionRow(
        primary: FilledButton(
          onPressed: _pick == null ? null : () => _confirm(data),
          child: const Text('예측 확정'),
        ),
      ),
    );
  }
}

class _GroundTeam extends StatelessWidget {
  const _GroundTeam({
    required this.label,
    required this.team,
    this.end = false,
  });

  final String label;
  final TeamSummary team;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final align = end ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: k.chalkSub)),
        Text(
          team.name,
          style: text.headlineSmall?.copyWith(color: k.chalk),
          textAlign: end ? TextAlign.end : TextAlign.start,
        ),
        Text(
          '${team.wins}승 ${team.losses}패 ${team.ties}무',
          style: text.bodyMedium?.copyWith(color: k.chalkSub),
        ),
      ],
    );
  }
}

class _Cmp {
  _Cmp(
    this.label,
    this.away,
    this.home,
    this.format, {
    required this.higherIsBetter,
  });
  final String label;
  final double? away;
  final double? home;
  final String Function(double) format;
  final bool higherIsBetter;
}

/// 두 팀 값을 나란히 놓고 더 나은 쪽을 굵게 쓴다.
class _CompareTable extends StatelessWidget {
  const _CompareTable({
    required this.rows,
    required this.awayName,
    required this.homeName,
  });

  final List<_Cmp> rows;
  final String awayName;
  final String homeName;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final strong = base.copyWith(fontWeight: FontWeight.w700);
    final sub = base.copyWith(color: k.inkSub);

    TextStyle styleFor(double? mine, double? theirs, bool higher) {
      if (mine == null || theirs == null || mine == theirs) return base;
      final better = higher ? mine > theirs : mine < theirs;
      return better ? strong : base;
    }

    Widget line(
      String a,
      String label,
      String h,
      TextStyle sa,
      TextStyle sl,
      TextStyle sh,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(a, style: sa)),
          Expanded(
            flex: 2,
            child: Text(label, style: sl, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(h, style: sh, textAlign: TextAlign.end),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: k.sheetRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            line(awayName, '', homeName, sub, sub, sub),
            for (final r in rows)
              line(
                r.away == null ? '—' : r.format(r.away!),
                r.label,
                r.home == null ? '—' : r.format(r.home!),
                styleFor(r.away, r.home, r.higherIsBetter),
                sub,
                styleFor(r.home, r.away, r.higherIsBetter),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pitcher extends StatelessWidget {
  const _Pitcher({
    required this.data,
    required this.teamId,
    required this.pitcherId,
    required this.onChange,
  });
  final AppData data;
  final String teamId;
  final String pitcherId;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final autoId = data.season.lineups[teamId]!.pitcherId;
    final p = data.player(pitcherId);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: k.sheetRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.team(teamId).shortName,
              style: text.bodySmall?.copyWith(color: k.inkSub),
            ),
            Text(p.name, style: text.titleMedium),
            Text('평균자책 ${era(p.era)}', style: text.bodyMedium),
            Text(
              '${p.wins ?? 0}승 ${p.losses ?? 0}패, ${p.inningsPitched ?? '—'}이닝',
              style: text.bodySmall?.copyWith(color: k.inkSub),
            ),
            if (pitcherId != autoId)
              Text(
                '자동 선발 ${data.player(autoId).name} 대신',
                style: text.bodySmall?.copyWith(color: k.accentText),
              ),
            const Spacer(),
            const SizedBox(height: 8),
            FilledButton(
              style: secondaryButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
              ),
              onPressed: onChange,
              child: const Text('선발 바꾸기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lineup extends StatelessWidget {
  const _Lineup({required this.data, required this.teamId});
  final AppData data;
  final String teamId;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final sub = base.copyWith(color: k.inkSub);
    final lineup = data.season.lineups[teamId]!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: k.sheetRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('', style: sub)),
                  Expanded(child: Text('타자', style: sub)),
                  SizedBox(
                    width: 64,
                    child: Text('타율', style: sub, textAlign: TextAlign.end),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('홈런', style: sub, textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
            for (final slot in lineup.battingOrder)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${slot.order}', style: sub),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: data.player(slot.playerId).name,
                              style: base.copyWith(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: '  ${positionLabel(slot.position)}',
                              style: sub,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        avg(data.player(slot.playerId).battingAverage),
                        style: base,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${data.player(slot.playerId).homeRuns ?? '—'}',
                        style: base,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
