import 'package:flutter/material.dart';
import 'package:kbo_engine/kbo_engine.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/box_score.dart';
import '../theme/kbo_theme.dart';
import '../widgets/frame.dart';

/// 상세보기: 팀별 타자 기록(타수·안타·홈런·타점·볼넷·삼진)과 투수 기록(이닝·피안타·실점·볼넷·삼진).
class BoxScoreScreen extends StatelessWidget {
  const BoxScoreScreen({super.key, required this.engine});

  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data.data!;
    final k = context.kbo;
    final box = BoxScore.from(engine);
    final away = data.team(engine.awayTeamId), home = data.team(engine.homeTeamId);
    return DefaultTabController(
      length: 2,
      child: AppFrame(
        band: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BandTitle(title: '경기 상세 기록', back: true),
            TabBar(
              labelColor: k.onBand,
              unselectedLabelColor: k.bandSub,
              indicatorColor: k.onBand,
              tabs: [Tab(text: '원정 ${away.shortName}'), Tab(text: '홈 ${home.shortName}')],
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _TeamTables(team: box.away, box: box, data: data),
            _TeamTables(team: box.home, box: box, data: data),
          ],
        ),
      ),
    );
  }
}

class _TeamTables extends StatelessWidget {
  const _TeamTables({required this.team, required this.box, required this.data});

  final TeamBox team;
  final BoxScore box;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    String decision(String id) {
      if (id == box.winningPitcherId) return '승';
      if (id == box.losingPitcherId) return '패';
      if (id == box.savePitcherId) return '세';
      if (box.holdPitcherIds.contains(id)) return '홀';
      return '';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      children: [
        const SectionTitle('타자', padding: EdgeInsets.fromLTRB(8, 0, 8, 2)),
        _StatTable(
          headers: const ['타수', '안타', '홈런', '타점', '볼넷', '삼진'],
          rows: [
            for (final b in team.batters)
              (
                '${b.pinchHitter ? '  ' : '${b.order} '}${data.player(b.playerId).name}${b.pinchHitter ? ' (대타)' : ''}',
                [b.atBats, b.hits, b.homeRuns, b.runsBattedIn, b.walks, b.strikeouts].map((v) => '$v').toList(),
              ),
          ],
          total: (
            '합계',
            [
              team.batters.fold(0, (s, b) => s + b.atBats),
              team.hits,
              team.batters.fold(0, (s, b) => s + b.homeRuns),
              team.batters.fold(0, (s, b) => s + b.runsBattedIn),
              team.walks,
              team.batters.fold(0, (s, b) => s + b.strikeouts),
            ].map((v) => '$v').toList(),
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('투수', padding: EdgeInsets.fromLTRB(8, 0, 8, 2)),
        _StatTable(
          headers: const ['결과', '이닝', '피안타', '실점', '볼넷', '삼진'],
          rows: [
            for (final p in team.pitchers)
              (
                data.player(p.playerId).name,
                [decision(p.playerId), p.innings, '${p.hits}', '${p.runs}', '${p.walks}', '${p.strikeouts}'],
              ),
          ],
        ),
      ],
    );
  }
}

/// 이름 열 + 숫자 열 여섯. 줄무늬로 줄을 나눈다.
class _StatTable extends StatelessWidget {
  const _StatTable({required this.headers, required this.rows, this.total});

  final List<String> headers;
  final List<(String, List<String>)> rows;
  final (String, List<String>)? total;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final head = text.labelSmall!.copyWith(color: k.inkSub);
    final num = text.bodyMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    TableRow row((String, List<String>) r, {Decoration? deco, bool bold = false}) => TableRow(
          decoration: deco,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                height: 38,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(r.$1, style: bold ? text.titleSmall : text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            for (final v in r.$2)
              Center(child: Text(v, style: bold ? num.copyWith(fontWeight: FontWeight.w700) : num, maxLines: 1)),
          ],
        );

    return Table(
      columnWidths: {0: const FlexColumnWidth(2.6), for (var i = 1; i <= headers.length; i++) i: const FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          const SizedBox(height: 28),
          for (final h in headers) Center(child: Text(h, style: head)),
        ]),
        for (final (i, r) in rows.indexed)
          row(r, deco: i.isEven ? BoxDecoration(color: k.stripe) : null),
        if (total != null) row(total!, bold: true),
      ],
    );
  }
}
