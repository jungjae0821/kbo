import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_app/data/app_data.dart';
import 'package:kbo_app/state/record_book.dart';

void main() {
  test('번들 시즌 데이터를 읽고 계약 검사를 통과한다', () {
    final data = AppData.parse(File('assets/data/season_dataset.json').readAsStringSync());
    expect(data.teams, hasLength(10));
    expect(data.season.lineups, hasLength(10));
    expect(data.playerCount, 591);
    expect(data.year, '2026');
  });

  group('RecordBook 채점 규칙', () {
    GameRecord g(String id, String predicted, String? winner) => GameRecord(
          gameId: id,
          awayTeamId: 'a',
          homeTeamId: 'h',
          awayScore: 0,
          homeScore: 0,
          predictedWinnerId: predicted,
          winnerTeamId: winner,
          finishedAt: DateTime(2026),
        );

    test('적중 100점, 같은 경기 ID는 한 번만 채점', () {
      final book = RecordBook();
      expect(book.score(g('1', 'a', 'a')), isTrue);
      expect(book.score(g('1', 'a', 'a')), isFalse);
      expect(book.totalPoints, 100);
      expect(book.hitRate, 1.0);
    });

    test('무승부는 0점, 적중률 분모 제외, 연속 적중 유지', () {
      final book = RecordBook()
        ..score(g('1', 'a', 'a'))
        ..score(g('2', 'a', null))
        ..score(g('3', 'h', 'h'));
      expect(book.totalPoints, 200);
      expect(book.decidedCount, 2);
      expect(book.currentStreak, 2);
      expect(book.bestStreak, 2);
    });

    test('빗나가면 연속 적중이 끊기고 적중률은 승패 경기 기준', () {
      final book = RecordBook()
        ..score(g('1', 'a', 'a'))
        ..score(g('2', 'a', 'h'));
      expect(book.currentStreak, 0);
      expect(book.bestStreak, 1);
      expect(book.hitRate, 0.5);
    });

    test('승패 경기가 없으면 적중률은 null', () {
      expect(RecordBook().hitRate, isNull);
    });
  });
}
