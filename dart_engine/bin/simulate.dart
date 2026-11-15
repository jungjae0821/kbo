import 'dart:convert';
import 'dart:io';

import '../lib/kbo_engine.dart';

const defaultDataset = '../kbo_data/kbo_2026_138278/app/season_dataset.json';

void main(List<String> args) {
  try {
    run(args);
  } catch (error) {
    stderr.writeln('Simulation failed: $error');
    exitCode = 1;
  }
}

void run(List<String> args) {
  const help = '''Usage (from dart_engine/):
  dart run bin/simulate.dart [options]
  --dataset PATH   Season JSON (default: $defaultDataset)
  --list-teams     Print team IDs and exit
  --away ID        Away team (default: first team)
  --home ID        Home team (default: second team)
  --seed INTEGER   Reproducible seed, 0..2147483645 (default: 42)
  --game-id ID     Optional logical match ID (generated if omitted)
  --output PATH    Save metadata, final state and all plate appearance logs
  --verbose       Print each plate appearance
  --help          Show usage''';
  final options = <String, String>{};
  final flags = <String>{};
  const valued = {
    '--dataset',
    '--away',
    '--home',
    '--seed',
    '--game-id',
    '--output',
  };
  const switches = {'--help', '--list-teams', '--verbose'};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (switches.contains(arg)) {
      flags.add(arg);
    } else if (valued.contains(arg) &&
        i + 1 < args.length &&
        !args[i + 1].startsWith('--')) {
      options[arg] = args[++i];
    } else {
      throw ArgumentError('Unknown option or missing value: $arg\n$help');
    }
  }
  if (flags.contains('--help')) {
    stdout.writeln(help);
    return;
  }
  final path = options['--dataset'] ?? defaultDataset;
  final dataset = SeasonDataset.fromJson(
    jsonDecode(File(path).readAsStringSync(encoding: utf8))
        as Map<String, dynamic>,
  );
  if (flags.contains('--list-teams')) {
    for (final team in dataset.teams.values) {
      stdout.writeln('${team.id}\t${team.name}');
    }
    return;
  }
  final ids = dataset.teams.keys.toList();
  final seed = int.parse(options['--seed'] ?? '42');
  final engine = GameEngine(
    dataset: dataset,
    awayTeamId: options['--away'] ?? ids[0],
    homeTeamId: options['--home'] ?? ids[1],
    seed: seed,
    gameId: options['--game-id'],
  );
  while (!engine.state.isFinished) {
    final log = engine.step();
    if (flags.contains('--verbose')) {
      stdout.writeln(
        '${log.inning}${log.isTop ? "초" : "말"} '
        '${dataset.players[log.batterId]!.name}: ${log.outcome.key}, '
        '+${log.transition.scored.length}점, ${log.after.awayScore}:${log.after.homeScore}',
      );
    }
  }
  final away = dataset.teams[engine.awayTeamId]!.name;
  final home = dataset.teams[engine.homeTeamId]!.name;
  stdout.writeln(
    '$away ${engine.state.awayScore} : ${engine.state.homeScore} $home',
  );
  stdout.writeln(
    '종료: ${engine.state.end!.name}, ${engine.state.inning}회, '
    '${engine.logs.length}타석, seed=$seed',
  );
  stdout.writeln(
    '승리: ${engine.winnerTeamId == null ? "무승부" : dataset.teams[engine.winnerTeamId]!.name}',
  );
  stdout.writeln(
    '이닝\t${List.generate(engine.state.inning, (i) => i + 1).join("\t")}',
  );
  stdout.writeln(
    '원정\t${engine.state.awayInnings.map((v) => v ?? "-").join("\t")}',
  );
  stdout.writeln(
    '홈\t${engine.state.homeInnings.map((v) => v ?? "-").join("\t")}',
  );
  final output = options['--output'];
  if (output != null) {
    final file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent("  ").convert(engine.toJson())}\n',
      encoding: utf8,
    );
    stdout.writeln('경기 로그: ${file.absolute.path}');
  }
}
