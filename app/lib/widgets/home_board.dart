import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';

/// 홈 맨 위 점수판. 경기 화면의 상태 띠와 같은 어두운 면에 내 예측 성적을 싣는다.
class PredictionBoard extends StatelessWidget {
  const PredictionBoard({super.key, required this.records});

  final RecordBook records;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final r = records;
    final missed = r.decidedCount - r.hitCount;
    final ties = r.predictionCount - r.decidedCount;
    final label = text.bodySmall!.copyWith(color: k.statusSub);
    final value = text.displaySmall!.copyWith(color: k.onStatus);

    Widget stat(String name, String v, {CrossAxisAlignment align = CrossAxisAlignment.start}) => Column(
          crossAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: label),
            Text(v, style: value, maxLines: 1),
          ],
        );

    final note = r.predictionCount == 0
        ? '이길 팀을 맞히면 ${RecordBook.pointsPerHit}점. 무승부는 0점이고 적중률에서 빠집니다.'
        : '적중 ${r.hitCount}, 빗나감 $missed, 무승부 $ties';

    return Semantics(
      label: '내 예측 누적 ${r.totalPoints}점, ${r.predictionCount}경기, '
          '적중률 ${r.hitRate == null ? '없음' : avg(r.hitRate)}. $note',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: k.status, borderRadius: BorderRadius.circular(statusRadius)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: stat('누적 점수', '${r.totalPoints}점')),
                  Expanded(child: stat('예측', '${r.predictionCount}경기')),
                  stat('적중률', avg(r.hitRate), align: CrossAxisAlignment.end),
                ],
              ),
              const SizedBox(height: 10),
              Text(keepAll(note), style: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2026 정규시즌 순위표. KBO 순위는 승률(무승부 제외) 순, 게임 차는 1위와의 차이.
class SeasonStandings extends StatelessWidget {
  const SeasonStandings({super.key, required this.teams});

  final List<TeamSummary> teams;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final sorted = [...teams]..sort((a, b) => b.winRate.compareTo(a.winRate));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final top = sorted.first;
    const tab = [FontFeature.tabularFigures()];
    final head = text.labelSmall!.copyWith(color: k.inkSub);
    final cell = text.bodyMedium!.copyWith(fontFeatures: tab);

    String gamesBehind(TeamSummary t) {
      final gb = ((top.wins - top.losses) - (t.wins - t.losses)) / 2;
      if (gb == 0) return '—';
      return gb == gb.truncateToDouble() ? gb.toStringAsFixed(0) : gb.toStringAsFixed(1);
    }

    Widget row(List<Widget> cells) => Row(children: cells);
    Widget c(String s, double w, TextStyle st) => SizedBox(width: w, child: Text(s, style: st, textAlign: TextAlign.end));

    // 승률이 같으면 같은 순위.
    final ranks = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      ranks.add(i > 0 && sorted[i].winRate == sorted[i - 1].winRate ? ranks[i - 1] : i + 1);
    }

    return Material(
      color: k.surface,
      borderRadius: BorderRadius.circular(bubbleRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: row([
                SizedBox(width: 26, child: Text('순위', style: head)),
                Expanded(child: Text('팀', style: head)),
                c('승', 30, head),
                c('패', 30, head),
                c('무', 22, head),
                c('승률', 46, head),
                c('차', 38, head),
              ]),
            ),
            const SizedBox(height: 4),
            for (final (i, t) in sorted.indexed)
              Semantics(
                label: '${ranks[i]}위 ${t.name}, ${t.wins}승 ${t.losses}패 ${t.ties}무, 승률 ${avg(t.winRate)}'
                    '${gamesBehind(t) == '—' ? '' : ', ${gamesBehind(t)}경기 차'}',
                excludeSemantics: true,
                child: SizedBox(
                  height: 36,
                  child: row([
                    SizedBox(
                      width: 26,
                      child: Text('${ranks[i]}', style: cell.copyWith(color: k.inkSub)),
                    ),
                    Expanded(
                      child: Text(
                        t.shortName,
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    c('${t.wins}', 30, cell),
                    c('${t.losses}', 30, cell),
                    c('${t.ties}', 22, cell),
                    c(avg(t.winRate), 46, cell.copyWith(fontWeight: FontWeight.w700)),
                    c(gamesBehind(t), 38, cell.copyWith(color: k.inkSub)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
