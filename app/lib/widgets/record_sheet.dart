import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';

/// 그라운드 위 팀 한 줄. 라인스코어처럼 원정을 위, 홈을 아래에 쌓는다.
/// 고른 줄은 석회색 면으로 뒤집어 칠해 "이 줄이 선택됨"을 보인다.
class GroundTeamRow extends StatelessWidget {
  const GroundTeamRow({
    super.key,
    required this.side,
    required this.name,
    this.detail,
    this.score,
    this.selected = false,
    this.muted = false,
    this.onTap,
    this.semanticsLabel,
    this.radio = false,
    this.placeholder = false,
  });

  /// '원정' 또는 '홈'.
  final String side;
  final String name;

  /// 오른쪽 작은 글자 (시즌 승패 등).
  final String? detail;

  /// 오른쪽 큰 숫자 (최종 점수).
  final int? score;
  final bool selected;

  /// 이름이 비어 있거나 진 팀처럼 한 단계 낮춰 보일 때.
  final bool muted;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// 둘 중 하나만 고르는 줄이면 true (스크린리더에 라디오로 알린다).
  final bool radio;

  /// [name]이 팀 이름이 아니라 안내 문구일 때 (본문 글자로 쓴다).
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final fg = selected ? k.grassDeep : (muted ? k.chalkSub : k.chalk);
    final sub = selected ? k.grassDeep : k.chalkSub;
    final interactive = onTap != null;

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: score != null ? 56 : 52),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: interactive || selected ? 14 : 0, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
            if (score != null) ...[
              const SizedBox(width: 8),
              Text(
                '$score',
                style: text.displaySmall?.copyWith(color: fg, fontSize: 44),
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: interactive && !radio,
      inMutuallyExclusiveGroup: radio,
      checked: radio ? selected : null,
      selected: !radio && interactive ? selected : null,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Material(
        color: selected ? k.chalk : (interactive ? k.grassDeep : Colors.transparent),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: row,
        ),
      ),
    );
  }
}

/// 내 예측 성적 한 줄. 타자 시즌 성적표처럼 항목 이름이 위, 값이 아래.
/// 그라운드 위에 석회색 글자로 놓는다.
class PredictionStatLine extends StatelessWidget {
  const PredictionStatLine({super.key, required this.records});

  final RecordBook records;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final r = records;
    final missed = r.decidedCount - r.hitCount;
    final ties = r.predictionCount - r.decidedCount;
    final cols = [
      ('예측', '${r.predictionCount}', 4),
      ('적중', '${r.hitCount}', 4),
      ('빗나감', '$missed', 4),
      ('무', '$ties', 3),
      ('적중률', avg(r.hitRate), 6),
      ('점수', '${r.totalPoints}', 5),
    ];
    return Semantics(
      label: '예측 ${r.predictionCount}경기, 적중 ${r.hitCount}, 빗나감 $missed, 무승부 $ties, '
          '적중률 ${r.hitRate == null ? '없음' : avg(r.hitRate)}, 점수 ${r.totalPoints}점',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value, flex) in cols)
            Expanded(
              flex: flex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.bodySmall?.copyWith(color: k.chalkSub), maxLines: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: text.headlineSmall?.copyWith(color: k.chalk, height: 1.2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 끝낸 경기를 한 줄씩 적는 예측 기록지. 시트 위에 카드 없이 놓는다.
class PredictionLedger extends StatelessWidget {
  const PredictionLedger({super.key, required this.games, required this.data, this.showDate = false});

  final List<GameRecord> games;
  final AppData data;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final head = base.copyWith(color: k.inkSub);

    Widget line(List<Widget> cells) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
        );

    Widget dateCell(String s, TextStyle style) => SizedBox(width: 48, child: Text(s, style: style));
    Widget pickCell(String s, TextStyle style) =>
        SizedBox(width: 64, child: Text(s, style: style, maxLines: 1, overflow: TextOverflow.ellipsis));
    Widget resultCell(String s, TextStyle style) =>
        SizedBox(width: 76, child: Text(s, style: style, textAlign: TextAlign.end));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: line([
            if (showDate) dateCell('날짜', head),
            Expanded(child: Text('경기', style: head)),
            pickCell('내 예측', head),
            resultCell('결과', head),
          ]),
        ),
        for (final g in games) _row(g, base, k, line, dateCell, pickCell, resultCell),
      ],
    );
  }

  Widget _row(
    GameRecord g,
    TextStyle base,
    KboColors k,
    Widget Function(List<Widget>) line,
    Widget Function(String, TextStyle) dateCell,
    Widget Function(String, TextStyle) pickCell,
    Widget Function(String, TextStyle) resultCell,
  ) {
    final away = data.team(g.awayTeamId).shortName;
    final home = data.team(g.homeTeamId).shortName;
    final pick = data.team(g.predictedWinnerId).shortName;
    final date = '${g.finishedAt.month}.${g.finishedAt.day}';
    final result = g.isTie ? '무승부' : (g.isHit ? '적중 +${g.points}' : '빗나감');
    final hit = g.isHit && !g.isTie;
    return Semantics(
      label: '${showDate ? '$date, ' : ''}$away ${g.awayScore} 대 ${g.homeScore} $home, 내 예측 $pick, $result',
      excludeSemantics: true,
      child: line([
        if (showDate) dateCell(date, base.copyWith(color: k.inkSub)),
        Expanded(child: Text('$away ${g.awayScore} : ${g.homeScore} $home', style: base)),
        pickCell(pick, base),
        resultCell(
          result,
          hit ? base.copyWith(color: k.accentText, fontWeight: FontWeight.w700) : base.copyWith(color: k.inkSub),
        ),
      ]),
    );
  }
}
