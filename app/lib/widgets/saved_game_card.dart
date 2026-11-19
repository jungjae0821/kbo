import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../screens/game_screen.dart';
import '../screens/team_select_screen.dart';
import '../state/labels.dart';
import '../state/saved_game.dart';
import 'feed_layout.dart';

/// 홈의 "중단된 경기" 칸: 점수·이닝·내 예측을 보여 주고 이어하거나 버린다.
class SavedGameCard extends StatelessWidget {
  const SavedGameCard({super.key, required this.game, required this.data});

  final SavedGame game;
  final AppData data;

  bool get _usable =>
      game.compatibleWith(data.season) &&
      data.season.teams.containsKey(game.awayTeamId) &&
      data.season.teams.containsKey(game.homeTeamId);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final usable = _usable;
    final String summary;
    if (usable) {
      final away = data.team(game.awayTeamId), home = data.team(game.homeTeamId);
      final where = game.isFinished ? '경기 종료, 채점 전' : '${halfLabel(game.inning, game.isTop)} 진행 중';
      summary = '${away.shortName} ${game.awayScore} : ${game.homeScore} ${home.shortName}, $where, '
          '내 예측 ${data.team(game.predictedWinnerId).shortName} 승리';
    } else {
      summary = '시즌 데이터나 경기 엔진이 바뀌어 이 경기는 이어할 수 없습니다. 버리면 새 경기를 만들 수 있습니다.';
    }
    return Bubble(
      stretch: true,
      soft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('중단된 경기', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(keepAll(summary), style: text.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              if (usable) ...[
                FilledButton(onPressed: () => resumeSavedGame(context), child: const Text('이어하기')),
                const SizedBox(width: 8),
              ],
              TextButton(onPressed: () => discardSavedGame(context), child: const Text('버리기')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 저장된 경기를 되살려 경기 화면을 연다. 되살리지 못하면 이유를 알리고 버릴지 묻는다.
Future<void> resumeSavedGame(BuildContext context) async {
  final scope = AppScope.of(context);
  final game = scope.savedGame.current;
  final data = scope.data.data;
  if (game == null || data == null) return;
  try {
    final engine = game.restore(data.season);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen.resume(engine: engine, predictedWinnerId: game.predictedWinnerId),
    ));
  } on FormatException {
    if (!context.mounted) return;
    await discardSavedGame(
      context,
      message: '저장된 경기를 되살리지 못했습니다. 파일이 손상됐거나 다른 버전에서 저장됐습니다. 이 경기를 버릴까요?',
    );
  }
}

/// 중단된 경기를 지운다. 채점하지 않은 경기이므로 먼저 확인한다. 지웠으면 true.
Future<bool> discardSavedGame(BuildContext context, {String? message}) async {
  final store = AppScope.of(context).savedGame;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('중단된 경기를 버릴까요?'),
      content: Text(keepAll(message ?? '버린 경기는 다시 이어할 수 없고 점수도 받지 않습니다.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('남겨 두기')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('버리기')),
      ],
    ),
  );
  if (ok != true) return false;
  store.clear();
  return true;
}

/// 새 경기 만들기. 중단된 경기가 있으면 새 경기가 그 자리를 덮으므로 먼저 확인한다.
Future<void> startNewGame(BuildContext context, {bool replace = false}) async {
  final store = AppScope.of(context).savedGame;
  if (store.current != null) {
    final ok = await discardSavedGame(
      context,
      message: '중단된 경기가 있습니다. 새 경기를 만들면 중단된 경기는 사라지고 점수도 받지 않습니다.',
    );
    if (!ok || !context.mounted) return;
  }
  final route = MaterialPageRoute(builder: (_) => const TeamSelectScreen());
  if (replace) {
    await Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
}
