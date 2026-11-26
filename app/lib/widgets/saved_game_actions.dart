import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../screens/game_screen.dart';
import '../screens/setup_screen.dart';
import '../state/game_setup.dart';
import '../state/labels.dart';

/// 저장된 경기를 되살려 경기 화면을 연다. 되살리지 못하면 이유를 알리고 버릴지 묻는다.
Future<void> resumeSavedGame(BuildContext context) async {
  final scope = AppScope.of(context);
  final game = scope.savedGame.current;
  final data = scope.data.data;
  if (game == null || data == null) return;
  try {
    final engine = game.restore(data.season);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen.resume(engine: engine, predictedWinnerId: game.predictedWinnerId, bullpens: game.bullpens),
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

/// 시뮬레이션 준비 화면을 연다. 중단된 경기가 있으면 새 경기가 그 자리를 덮으므로 먼저 확인한다.
/// [setup]이 있으면 그 설정을 채운 채로 연다 (다시하기).
Future<void> startNewGame(BuildContext context, {GameSetup? setup}) async {
  final store = AppScope.of(context).savedGame;
  if (store.current != null) {
    final ok = await discardSavedGame(
      context,
      message: '중단된 경기가 있습니다. 새 경기를 시작하면 중단된 경기는 사라지고 점수도 받지 않습니다.',
    );
    if (!ok || !context.mounted) return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(initial: setup)));
}
