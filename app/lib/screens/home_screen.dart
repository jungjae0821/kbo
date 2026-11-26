import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../data/data_controller.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../state/saved_game.dart';
import '../theme/kbo_theme.dart';
import '../widgets/frame.dart';
import '../widgets/saved_game_actions.dart';
import '../widgets/standings_table.dart';
import 'records_screen.dart';

/// 메인: 내 기록 한 줄 → (멈춘 경기) 이어하기 → 2026 정규시즌 순위표 → 시뮬레이션 시작.
/// 휴대폰 한 화면에 스크롤 없이 들어간다 (초안 확정 구조 1, 판정 17).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.data, scope.records, scope.savedGame]),
      builder: (context, _) {
        final data = scope.data;
        final records = scope.records;
        final ready = data.status == DataStatus.ready;
        final saved = scope.savedGame.current;
        final year = ready && data.data!.year.isNotEmpty ? data.data!.year : '2026';
        final notices = [
          ?records.notice,
          ?scope.savedGame.notice,
          if (scope.savedGame.saveFailed) '진행 중인 경기를 기기에 저장하지 못했습니다. 앱을 닫으면 이어할 수 없습니다.',
        ];

        final Widget table;
        if (data.status == DataStatus.loading) {
          table = const _Loading();
        } else if (data.status == DataStatus.failed) {
          table = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: NoticePanel(
              message: data.error ?? '시즌 데이터를 읽지 못했습니다.',
              action: TextButton(onPressed: data.load, child: const Text('다시 불러오기')),
            ),
          );
        } else {
          table = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: StandingsTable(teams: data.data!.teams),
          );
        }

        return AppFrame(
          band: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BandTitle(title: 'KBO 가상야구'),
              _MyRecordLine(
                records: records,
                onTap: ready ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordsScreen())) : null,
              ),
            ],
          ),
          overlap: ready && saved != null ? _ResumeCard(game: saved, data: data.data!) : null,
          body: LayoutBuilder(
            builder: (context, box) {
              // 남는 높이에 맞춰 순위표 줄 높이를 정한다 (32~40). 스크롤 없이 한 화면에.
              final extra = notices.length + (ready && data.notice != null ? 1 : 0);
              final rowHeight = ((box.maxHeight - 40 - 34 - extra * 56) / 10).clamp(30.0, 40.0);
              return SingleChildScrollView(
                // 글자를 크게 키운 기기에서만 스크롤된다.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final n in notices)
                      Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 6), child: NoticePanel(message: n)),
                    if (ready && data.notice != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        child: NoticePanel(
                          message: data.notice!,
                          action: data.canRetry ? TextButton(onPressed: data.load, child: const Text('다시 불러오기')) : null,
                        ),
                      ),
                    SectionTitle('$year 정규시즌 순위', padding: const EdgeInsets.fromLTRB(16, 10, 16, 2)),
                    if (ready)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: StandingsTable(teams: data.data!.teams, rowHeight: rowHeight),
                      )
                    else
                      table,
                  ],
                ),
              );
            },
          ),
          dock: FilledButton(
            // 기록을 다 읽기 전에는 새 경기를 시작하지 않는다 (채점 기록이 덮이지 않게).
            onPressed: ready && records.isLoaded && scope.savedGame.isLoaded ? () => startNewGame(context) : null,
            child: const Text('시뮬레이션 시작'),
          ),
        );
      },
    );
  }
}

/// 띠 위 내 기록 한 줄: 경기 수, 적중률, 누적 점수. 누르면 개인 기록.
class _MyRecordLine extends StatelessWidget {
  const _MyRecordLine({required this.records, this.onTap});

  final RecordBook records;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final sub = text.bodySmall!.copyWith(color: k.bandSub, fontSize: 13);
    final big = text.titleMedium!.copyWith(color: k.onBand, fontSize: 18);
    final rate = records.hitRate == null ? '-' : '${(records.hitRate! * 100).round()}%';
    Widget item(String value, String label, {bool valueFirst = true}) => Text.rich(
          TextSpan(children: valueFirst
              ? [TextSpan(text: value, style: big), TextSpan(text: ' $label', style: sub)]
              : [TextSpan(text: '$label ', style: sub), TextSpan(text: value, style: big)]),
        );
    return Semantics(
      button: true,
      label: '내 기록 보기. ${records.gameCount}경기, 적중률 ${records.hitRate == null ? '없음' : rate}, ${records.totalPoints}점',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rowRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 숫자가 커져도 한 줄에 들어가게 줄인다.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        item('${records.gameCount}', '경기'),
                        const SizedBox(width: 16),
                        item(rate, '적중률', valueFirst: false),
                        const SizedBox(width: 16),
                        item('${records.totalPoints}', '점'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('내 기록', style: text.labelLarge!.copyWith(color: k.onBand, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 띠에 걸친 이어하기 카드. 데이터·엔진이 바뀌어 이어할 수 없으면 버리기만 보인다.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.game, required this.data});

  final SavedGame game;
  final AppData data;

  bool get _usable =>
      game.compatibleWith(data.season) &&
      data.season.teams.containsKey(game.awayTeamId) &&
      data.season.teams.containsKey(game.homeTeamId);

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final usable = _usable;
    final String title, detail;
    if (usable) {
      final away = data.team(game.awayTeamId), home = data.team(game.homeTeamId);
      title = '${away.shortName} ${game.awayScore} : ${game.homeScore} ${home.shortName}';
      detail = '${game.isFinished ? (game.predictedWinnerId == null ? '경기 종료, 기록 전' : '경기 종료, 채점 전') : '${halfLabel(game.inning, game.isTop)}에서 멈춤'}, '
          '${game.predictedWinnerId == null ? '예측 없이 돌려보기' : '예측 ${data.team(game.predictedWinnerId!).shortName}'}';
    } else {
      title = '이어할 수 없는 경기';
      detail = '시즌 데이터나 경기 엔진이 바뀌었습니다';
    }
    return Semantics(
      container: true,
      label: '중단된 경기',
      child: LiftedCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(detail, style: text.bodySmall!.copyWith(color: k.inkSub), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            TextButton(onPressed: () => discardSavedGame(context), child: const Text('버리기')),
            if (usable) ...[
              const SizedBox(width: 4),
              FilledButton(style: bandButtonStyle(context, height: 44), onPressed: () => resumeSavedGame(context), child: const Text('이어하기')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: Text(keepAll('시즌 순위와 선수 기록을 읽는 중입니다'), style: text.bodyMedium)),
        ],
      ),
    );
  }
}
