import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/app_data.dart';
import 'package:kbo_app/data/data_controller.dart';
import 'package:kbo_app/data/local_store.dart';
import 'package:kbo_app/data/local_store_io.dart';
import 'package:kbo_app/main.dart';
import 'package:kbo_app/state/auto_bullpen.dart';
import 'package:kbo_app/state/record_book.dart';
import 'package:kbo_app/state/saved_game.dart';
import 'package:kbo_engine/kbo_engine.dart';

const _datasetPath = 'assets/data/season_dataset.json';

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

/// 쓰기가 늘 실패하는 저장소 (저장 공간 부족 등).
class _BrokenStore extends MemoryLocalStore {
  @override
  Future<void> write(String name, String contents) async => throw const FileSystemException('disk full');
}

GameRecord _record(String id, {required String predicted, String? winner, int away = 3, int home = 2}) => GameRecord(
      gameId: id,
      awayTeamId: 'A',
      homeTeamId: 'B',
      awayScore: away,
      homeScore: home,
      predictedWinnerId: predicted,
      winnerTeamId: winner,
      finishedAt: DateTime.utc(2026, 11, 19),
    );

Finder _plainContains(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').replaceAll('⁠', '').contains(text),
    );

void main() {
  final season = SeasonDataset.fromJson(jsonDecode(File(_datasetPath).readAsStringSync()) as Map<String, dynamic>);
  final teamIds = season.teams.keys.toList();

  group('개인 기록 저장', () {
    test('저장한 기록을 다시 켜면 그대로 읽고, 같은 경기는 다시 채점하지 않는다', () async {
      final store = MemoryLocalStore();
      final first = RecordBook(store: store);
      await first.load();
      expect(first.score(_record('g1', predicted: 'A', winner: 'A')), isTrue);
      expect(first.score(_record('g2', predicted: 'A', winner: 'A')), isTrue);
      expect(first.score(_record('g3', predicted: 'B', winner: null)), isTrue); // 무승부
      expect(first.score(_record('g4', predicted: 'B', winner: 'A')), isTrue); // 빗나감
      expect(first.score(_record('g5', predicted: 'A', winner: 'A')), isTrue);
      await first.saved;

      final again = RecordBook(store: store);
      await again.load();
      expect(again.predictionCount, 5);
      expect(again.decidedCount, 4);
      expect(again.hitCount, 3);
      expect(again.totalPoints, 300);
      expect(again.currentStreak, 1);
      expect(again.bestStreak, 2);
      expect(again.hitRate, 0.75);
      expect(again.recent.first.gameId, 'g5');
      expect(again.score(_record('g1', predicted: 'A', winner: 'A')), isFalse);
      expect(again.totalPoints, 300);

      final saved = jsonDecode(store.files[RecordBook.fileName]!) as Map;
      expect(saved['format'], RecordBook.format);
      expect(saved['schema_version'], RecordBook.schemaVersion);
      expect(saved['total_points'], 300);
    });

    test('손상된 기록 파일은 따로 보관하고 빈 기록으로 시작한다', () async {
      final store = MemoryLocalStore()..files[RecordBook.fileName] = '{"format": "kbo_records", "games": [';
      final book = RecordBook(store: store);
      await book.load();
      expect(book.predictionCount, 0);
      expect(book.notice, isNotNull);
      expect(store.files[RecordBook.corruptFileName], startsWith('{"format"'));
      book.score(_record('g1', predicted: 'A', winner: 'A'));
      await book.saved;
      expect(RecordBook.decode(store.files[RecordBook.fileName]!).single.gameId, 'g1');
    });

    test('지원하지 않는 버전·잘못된 항목은 거부한다', () {
      expect(() => RecordBook.decode('{"format":"kbo_records","schema_version":99,"games":[]}'), throwsFormatException);
      expect(() => RecordBook.decode('{"format":"kbo_records","schema_version":1,"games":[{"game_id":1}]}'),
          throwsFormatException);
      expect(() => RecordBook.decode('[]'), throwsFormatException);
    });

    test('읽기 전에 끝난 경기는 읽은 기록 뒤에 합쳐 저장한다', () async {
      final store = MemoryLocalStore();
      final old = RecordBook(store: store);
      await old.load();
      old.score(_record('old', predicted: 'A', winner: 'A'));
      await old.saved;

      final book = RecordBook(store: store);
      book.score(_record('new', predicted: 'A', winner: 'A'));
      expect(store.files[RecordBook.fileName], contains('"old"')); // 읽기 전에는 덮어쓰지 않는다
      await book.load();
      await book.saved;
      expect(book.recent.map((g) => g.gameId), ['new', 'old']);
      expect(book.currentStreak, 2);
      expect(RecordBook.decode(store.files[RecordBook.fileName]!).length, 2);
    });

    test('저장에 실패하면 안내를 띄우고 기록은 메모리에 남긴다', () async {
      final book = RecordBook(store: _BrokenStore());
      await book.load();
      book.score(_record('g1', predicted: 'A', winner: 'A'));
      await book.saved;
      expect(book.totalPoints, 100);
      expect(book.notice, contains('저장하지 못했습니다'));
    });
  });

  group('기기 파일 저장소', () {
    test('임시 파일에 쓴 뒤 바꾸고, 덮어쓰기·삭제가 된다', () async {
      final dir = await Directory.systemTemp.createTemp('kbo_store_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileLocalStore(() async => dir);
      expect(await store.read('records'), isNull);
      await store.write('records', '첫 내용');
      await Future.wait([store.write('records', '둘째'), store.write('records', '셋째 내용')]);
      expect(await store.read('records'), '셋째 내용');
      expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['records.json']);
      await store.delete('records');
      expect(await store.read('records'), isNull);
    });
  });

  group('중단 경기 저장', () {
    GameEngine newGame({int seed = 77}) =>
        GameEngine(dataset: season, awayTeamId: teamIds[0], homeTeamId: teamIds[1], seed: seed);

    test('저장한 경기를 다시 켜면 같은 상태로 되살리고 끝까지 같은 결과가 나온다', () async {
      final store = MemoryLocalStore();
      final saved = SavedGameStore(store: store);
      await saved.load();
      final game = newGame();
      for (var i = 0; i < 30; i++) {
        game.step();
      }
      final home = teamIds[1];
      if (game.canSubstitutePitcher(home)) game.substitutePitcher(home, game.pitcherCandidates(home).first);
      saved.save(game, home);
      await saved.saved;

      final reopened = SavedGameStore(store: store);
      await reopened.load();
      final current = reopened.current!;
      expect(current.predictedWinnerId, home);
      expect(current.plateAppearances, 30);
      expect(current.compatibleWith(season), isTrue);
      final restored = current.restore(season);
      expect(restored.gameId, game.gameId);
      expect(jsonEncode(restored.state.toJson()), jsonEncode(game.state.toJson()));
      game.playToEnd();
      restored.playToEnd();
      expect(jsonEncode(restored.toJson()), jsonEncode(game.toJson()));

      reopened.clear(gameId: 'other');
      expect(reopened.current, isNotNull);
      reopened.clear(gameId: game.gameId);
      await reopened.saved;
      expect(store.files.containsKey(SavedGameStore.fileName), isFalse);
    });

    test('손상된 파일은 지우고 안내한다', () async {
      final store = MemoryLocalStore()..files[SavedGameStore.fileName] = 'not json';
      final saved = SavedGameStore(store: store);
      await saved.load();
      await saved.saved;
      expect(saved.current, isNull);
      expect(saved.notice, isNotNull);
      expect(store.files.containsKey(SavedGameStore.fileName), isFalse);
    });

    test('다른 데이터 버전에서 저장한 경기는 이어할 수 없다고 판단한다', () {
      final game = newGame();
      final checkpoint = game.toCheckpoint()..['data_version'] = 'old-data';
      final saved = SavedGame(checkpoint: checkpoint, predictedWinnerId: teamIds[0], savedAt: DateTime.now());
      final decoded = SavedGame.decode(saved.encode());
      expect(decoded.compatibleWith(season), isFalse);
      expect(() => decoded.restore(season), throwsFormatException);
    });

    test('예측 팀이 대진에 없으면 거부한다', () {
      final saved = SavedGame(checkpoint: newGame().toCheckpoint(), predictedWinnerId: 'X', savedAt: DateTime.now());
      expect(() => SavedGame.decode(saved.encode()), throwsFormatException);
    });
  });

  group('앱 재실행', () {
    late MemoryLocalStore store;
    late DataController data;

    setUp(() => store = MemoryLocalStore());

    /// 같은 기기 저장소로 앱을 새로 켠다.
    Future<(RecordBook, SavedGameStore)> launch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      data = DataController(bundle: _FileBundle(), remoteUrl: '');
      final records = RecordBook(store: store);
      final saved = SavedGameStore(store: store);
      await tester.runAsync(() => Future.wait([data.load(), records.load(), saved.load()]));
      await tester.pumpWidget(KboApp(key: UniqueKey(), data: data, records: records, savedGame: saved));
      await tester.pumpAndSettle();
      return (records, saved);
    }

    testWidgets('중단한 경기를 이어서 끝내면 한 번만 채점되고, 다시 켜도 기록이 남는다', (tester) async {
      addTearDown(tester.view.reset);
      final away = teamIds[0], home = teamIds[1];
      // 이전 실행에서 12타석까지 진행하고 꺼진 경기.
      final game = GameEngine(dataset: season, awayTeamId: away, homeTeamId: home, seed: 4242);
      for (var i = 0; i < 12; i++) {
        game.step();
      }
      store.files[SavedGameStore.fileName] =
          SavedGame(checkpoint: game.toCheckpoint(), predictedWinnerId: away, savedAt: DateTime.now()).encode();

      var (records, saved) = await launch(tester);
      expect(find.text('이어하기'), findsOneWidget);
      expect(_plainContains('${halfLabel(game.state.inning, game.state.isTop)}에서 멈춤'), findsOneWidget);

      await tester.tap(find.text('이어하기'));
      await tester.pumpAndSettle();
      // 이어서 한 타석 진행하면 저장된 타석 수가 늘어난다.
      await tester.tap(find.text('다음 타석'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => saved.saved);
      expect(SavedGame.decode(store.files[SavedGameStore.fileName]!).plateAppearances, 13);

      // 뒤로 나가면 확인 없이 홈으로 가고, 홈에 다시 이어하기가 보인다.
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.text('이어하기'), findsOneWidget);

      // 앱을 다시 켜고 이어서 끝까지 진행한다.
      (records, saved) = await launch(tester);
      await tester.tap(find.text('이어하기'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && find.text('경기 결과 보기').evaluate().isEmpty; i++) {
        await tester.tap(find.text('다음 수비까지'));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        await records.saved;
        await saved.saved;
      });
      await tester.pumpAndSettle();
      expect(records.predictionCount, 1);
      expect(records.recent.single.gameId, game.gameId);
      expect(saved.current, isNull);
      expect(store.files.containsKey(SavedGameStore.fileName), isFalse);

      // 같은 경기를 끝까지 돌린 결과와 같다 (사용자 교체 없음, 상대 팀 홈은 자동 교체).
      final appData = AppData.parse(File(_datasetPath).readAsStringSync());
      while (!game.state.isFinished) {
        autoPitchingChange(game, appData, home);
        game.step();
      }
      expect(records.recent.single.awayScore, game.state.awayScore);
      expect(records.recent.single.homeScore, game.state.homeScore);

      // 다시 켜도 기록은 남고 중단 경기는 없다.
      (records, saved) = await launch(tester);
      expect(records.predictionCount, 1);
      expect(find.text('이어하기'), findsNothing);
    });

    testWidgets('채점 전에 꺼진 끝난 경기는 이어하면 바로 한 번만 채점한다', (tester) async {
      addTearDown(tester.view.reset);
      final game = GameEngine(dataset: season, awayTeamId: teamIds[2], homeTeamId: teamIds[3], seed: 31)..playToEnd();
      final file =
          SavedGame(checkpoint: game.toCheckpoint(), predictedWinnerId: teamIds[2], savedAt: DateTime.now()).encode();
      store.files[SavedGameStore.fileName] = file;

      var (records, saved) = await launch(tester);
      expect(_plainContains('경기 종료, 채점 전'), findsOneWidget);
      await tester.tap(find.text('이어하기'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await records.saved;
        await saved.saved;
      });
      expect(records.predictionCount, 1);
      expect(saved.current, isNull);

      // 기록 저장 뒤 중단 파일 삭제 전에 꺼진 경우를 흉내 낸다: 같은 경기가 다시 와도 점수는 그대로.
      store.files[SavedGameStore.fileName] = file;
      (records, saved) = await launch(tester);
      await tester.tap(find.text('이어하기'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await records.saved;
        await saved.saved;
      });
      expect(records.predictionCount, 1);
      expect(saved.current, isNull);
    });

    testWidgets('중단된 경기가 있을 때 새 경기를 만들면 먼저 묻는다', (tester) async {
      addTearDown(tester.view.reset);
      final game = GameEngine(dataset: season, awayTeamId: teamIds[0], homeTeamId: teamIds[1], seed: 8);
      store.files[SavedGameStore.fileName] =
          SavedGame(checkpoint: game.toCheckpoint(), predictedWinnerId: teamIds[0], savedAt: DateTime.now()).encode();
      final (_, saved) = await launch(tester);

      await tester.tap(find.text('시뮬레이션 시작'));
      await tester.pumpAndSettle();
      expect(find.text('중단된 경기를 버릴까요?'), findsOneWidget);
      await tester.tap(find.text('남겨 두기'));
      await tester.pumpAndSettle();
      expect(saved.current, isNotNull);

      await tester.tap(find.text('시뮬레이션 시작'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '버리기'));
      await tester.pumpAndSettle();
      expect(saved.current, isNull);
      expect(find.text('시뮬레이션 준비'), findsOneWidget);
    });

    testWidgets('다른 데이터 버전의 중단 경기는 이어하기 없이 버리기만 보인다', (tester) async {
      addTearDown(tester.view.reset);
      final game = GameEngine(dataset: season, awayTeamId: teamIds[0], homeTeamId: teamIds[1], seed: 8);
      store.files[SavedGameStore.fileName] = SavedGame(
        checkpoint: game.toCheckpoint()..['data_version'] = 'old',
        predictedWinnerId: teamIds[0],
        savedAt: DateTime.now(),
      ).encode();
      await launch(tester);
      expect(find.text('이어할 수 없는 경기'), findsOneWidget);
      expect(find.text('이어하기'), findsNothing);
      expect(find.text('버리기'), findsOneWidget);
    });
  });
}

String halfLabel(int inning, bool isTop) => '$inning회${isTop ? '초' : '말'}';
