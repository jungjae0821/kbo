import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import 'feed_layout.dart';

/// 고를 수 있는 팀 한 줄. 원정을 위, 홈을 아래에 쌓는다 (라인스코어 관례).
/// 고른 줄은 코발트 면으로 칠한다.
class TeamPickRow extends StatelessWidget {
  const TeamPickRow({
    super.key,
    required this.side,
    required this.name,
    this.detail,
    this.selected = false,
    this.placeholder = false,
    this.onTap,
    this.semanticsLabel,
    this.radio = false,
  });

  /// '원정' 또는 '홈'.
  final String side;
  final String name;

  /// 오른쪽 작은 글자 (시즌 승패 등).
  final String? detail;
  final bool selected;

  /// [name]이 팀 이름이 아니라 안내 문구일 때.
  final bool placeholder;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// 둘 중 하나만 고르는 줄이면 true (스크린리더에 라디오로 알린다).
  final bool radio;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final fg = selected ? k.onAccent : (placeholder ? k.inkSub : k.ink);
    final sub = selected ? k.onAccent : k.inkSub;
    return Semantics(
      button: !radio,
      inMutuallyExclusiveGroup: radio,
      checked: radio ? selected : null,
      selected: radio ? null : selected,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Material(
        color: selected ? k.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Text(side, style: text.bodySmall?.copyWith(color: sub))),
                  Expanded(
                    child: Text(
                      name,
                      style: (placeholder ? text.bodyLarge : text.titleMedium)?.copyWith(color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(width: 8),
                    Text(detail!, style: text.bodySmall?.copyWith(color: sub)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 내 예측 성적을 문장 두 줄로 (문자중계의 경기 요약처럼).
class PredictionSummary extends StatelessWidget {
  const PredictionSummary({super.key, required this.records, this.showStreak = false});

  final RecordBook records;
  final bool showStreak;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final r = records;
    final missed = r.decidedCount - r.hitCount;
    final ties = r.predictionCount - r.decidedCount;
    final streak = r.predictionCount == 0
        ? '연속 적중 기록이 아직 없습니다'
        : '지금 ${r.currentStreak}경기 연속 적중, 최다 ${r.bestStreak}경기';
    return Semantics(
      label: '누적 ${r.totalPoints}점, 예측 ${r.predictionCount}경기, 적중 ${r.hitCount}, 빗나감 $missed, 무승부 $ties, '
          '적중률 ${r.hitRate == null ? '없음' : avg(r.hitRate)}${showStreak ? ', $streak' : ''}',
      excludeSemantics: true,
      child: Bubble(
        stretch: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('누적 ${r.totalPoints}점, ${r.predictionCount}경기 예측', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              keepAll('적중 ${r.hitCount} 빗나감 $missed 무 $ties, 적중률 ${avg(r.hitRate)}'),
              style: text.bodySmall?.copyWith(color: k.inkSub),
            ),
            if (showStreak)
              Text(keepAll(streak), style: text.bodySmall?.copyWith(color: k.inkSub)),
          ],
        ),
      ),
    );
  }
}

/// 끝낸 경기 한 건을 메시지 한 칸으로. 적중한 경기는 강조 면.
class PredictionFeed extends StatelessWidget {
  const PredictionFeed({super.key, required this.games, required this.data, this.showDate = false});

  final List<GameRecord> games;
  final AppData data;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, g) in games.indexed) ...[
          if (i > 0) const SizedBox(height: 6),
          _GameBubble(game: g, data: data, showDate: showDate),
        ],
      ],
    );
  }
}

class _GameBubble extends StatelessWidget {
  const _GameBubble({required this.game, required this.data, required this.showDate});

  final GameRecord game;
  final AppData data;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final g = game;
    final away = data.team(g.awayTeamId).shortName;
    final home = data.team(g.homeTeamId).shortName;
    final pick = data.team(g.predictedWinnerId).shortName;
    final date = '${g.finishedAt.month}.${g.finishedAt.day}';
    final result = g.isTie ? '무승부, 0점' : (g.isHit ? '적중, +${g.points}점' : '빗나감, 0점');
    final hit = g.isHit && !g.isTie;
    return Semantics(
      label: '${showDate ? '$date, ' : ''}$away ${g.awayScore} 대 ${g.homeScore} $home, 내 예측 $pick, $result',
      excludeSemantics: true,
      child: Bubble(
        soft: hit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                if (showDate) TextSpan(text: '$date  ', style: text.bodySmall?.copyWith(color: k.inkSub)),
                TextSpan(text: '$away ${g.awayScore} : ${g.homeScore} $home', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            Text(
              '내 예측 $pick 승리, $result',
              style: text.bodySmall?.copyWith(
                color: hit ? k.accentText : k.inkSub,
                fontWeight: hit ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
