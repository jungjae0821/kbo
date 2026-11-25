import 'dart:math';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/game_setup.dart';
import '../state/labels.dart';
import '../state/record_book.dart';
import '../theme/kbo_theme.dart';
import '../widgets/frame.dart';
import '../widgets/player_sheet.dart';
import 'game_screen.dart';

/// 시뮬레이션 준비: ① 두 팀 → ② 선발투수 → ③ 라인업 → ④ 승리 예측 → 경기 시작.
/// 한 화면 안에서 단계를 넘긴다 (초안 확정 구조 2).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.initial});

  /// 다시하기로 들어오면 직전 설정. 이때는 두 팀이 정해져 있어 선발 단계부터 연다.
  final GameSetup? initial;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { teams, starters, lineup, predict }

extension on _Step {
  String get label => switch (this) {
        _Step.teams => '두 팀',
        _Step.starters => '선발투수',
        _Step.lineup => '라인업',
        _Step.predict => '승리 예측',
      };
}

class _SetupScreenState extends State<SetupScreen> {
  late final GameSetup _setup = widget.initial ?? GameSetup();
  late _Step _step = widget.initial?.hasTeams == true ? _Step.starters : _Step.teams;

  /// 라인업 단계에서 보고 있는 팀.
  bool _lineupHome = false;

  AppData get _data => AppScope.of(context).data.data!;

  bool get _canNext => switch (_step) {
        _Step.teams => _setup.hasTeams,
        _Step.starters || _Step.lineup => true,
        _Step.predict => _setup.predictedWinnerId != null,
      };

  void _back() {
    if (_step == _Step.teams) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step = _Step.values[_step.index - 1]);
    }
  }

  void _next() {
    if (_step == _Step.predict) {
      _start();
    } else {
      setState(() => _step = _Step.values[_step.index + 1]);
    }
  }

  Future<void> _start() async {
    final data = _data;
    final winner = data.team(_setup.predictedWinnerId!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepAll('${winner.name} 승리로 확정할까요?')),
        content: Text(keepAll('확정하면 경기가 끝날 때까지 바꿀 수 없습니다. 맞히면 ${RecordBook.pointsPerHit}점을 받습니다.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('다시 고르기')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('확정하고 시작')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(
        awayId: _setup.awayId!,
        homeId: _setup.homeId!,
        predictedWinnerId: _setup.predictedWinnerId!,
        seed: Random().nextInt(2147483645),
        startingPitchers: _setup.startingPitchers,
        battingOrders: _setup.battingOrders(data),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    final Widget body = switch (_step) {
      _Step.teams => _TeamsStep(setup: _setup, data: data, onChanged: () => setState(() {})),
      _Step.starters => _StartersStep(setup: _setup, data: data, onChanged: () => setState(() {})),
      _Step.lineup => _LineupStep(
          setup: _setup,
          data: data,
          home: _lineupHome,
          onSide: (home) => setState(() => _lineupHome = home),
          onChanged: () => setState(() {}),
        ),
      _Step.predict => _PredictStep(setup: _setup, data: data, onChanged: () => setState(() {})),
    };

    return PopScope(
      canPop: _step == _Step.teams,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppFrame(
        band: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BandTitle(title: '시뮬레이션 준비', back: true, onBack: _back),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _StepStrip(current: _step),
            ),
          ],
        ),
        body: body,
        dock: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _canNext ? _next : null,
              child: Text(switch (_step) {
                _Step.teams => _setup.hasTeams ? '선발투수 고르기' : '두 팀을 고르세요',
                _Step.starters => '라인업 확인',
                _Step.lineup => '승리 팀 예측',
                _Step.predict => _setup.predictedWinnerId == null
                    ? '이길 팀을 고르세요'
                    : '${data.team(_setup.predictedWinnerId!).shortName} 승리로 경기 시작',
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// 띠 아래 줄의 단계 표시. 실제 순서가 있는 흐름이라 번호를 쓴다.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.current});
  final _Step current;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '${_Step.values.length}단계 중 ${current.index + 1}단계, ${current.label}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final s in _Step.values) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.index + 1} ${s.label}',
                    style: text.labelMedium!.copyWith(
                      color: s == current ? k.onBand : k.bandSub,
                      fontWeight: s == current ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ),
            ),
            if (s != _Step.predict) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// 고르는 줄: 고르면 남색 면 + 흰 글자 (자홍은 주 버튼에만).
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.child,
    required this.selected,
    required this.onTap,
    this.semanticsLabel,
    this.radio = false,
    this.minHeight = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool radio;
  final double minHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    return Semantics(
      button: !radio,
      inMutuallyExclusiveGroup: radio,
      checked: radio ? selected : null,
      selected: radio ? null : selected,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Material(
        color: selected ? k.band : k.stripe,
        borderRadius: BorderRadius.circular(cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(cardRadius),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: DefaultTextStyle.merge(style: TextStyle(color: selected ? k.onBand : k.ink), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// ① 두 팀: 위 원정·홈 칸, 아래 10개 팀. 비어 있는 칸부터 채우고, 고른 칸을 누르면 비운다.
class _TeamsStep extends StatelessWidget {
  const _TeamsStep({required this.setup, required this.data, required this.onChanged});

  final GameSetup setup;
  final AppData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final teams = [...data.teams]..sort((a, b) => b.winRate.compareTo(a.winRate));

    void tapTeam(TeamSummary t) {
      if (setup.awayId == t.id) {
        setup.setTeams(null, setup.homeId);
      } else if (setup.homeId == t.id) {
        setup.setTeams(setup.awayId, null);
      } else if (setup.awayId == null) {
        setup.setTeams(t.id, setup.homeId);
      } else if (setup.homeId == null) {
        setup.setTeams(setup.awayId, t.id);
      } else {
        // 둘 다 찼으면 홈을 바꾼다.
        setup.setTeams(setup.awayId, t.id);
      }
      onChanged();
    }

    Widget slot(String side, String? id, VoidCallback clear) {
      final t = id == null ? null : data.team(id);
      return Expanded(
        child: _PickTile(
          selected: t != null,
          onTap: t == null ? null : clear,
          minHeight: 64,
          semanticsLabel: t == null ? '$side 비어 있음' : '$side ${t.name}, 누르면 비움',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(side, style: text.bodySmall!.copyWith(color: t == null ? k.inkSub : k.onBand)),
              Text(t?.name ?? '-',
                  style: (t == null ? text.bodyMedium! : text.titleMedium!).copyWith(color: t == null ? k.inkSub : k.onBand),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              slot('원정', setup.awayId, () {
                setup.setTeams(null, setup.homeId);
                onChanged();
              }),
              const SizedBox(width: 8),
              slot('홈', setup.homeId, () {
                setup.setTeams(setup.awayId, null);
                onChanged();
              }),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                const cols = 2, gap = 6.0;
                final rows = (teams.length / cols).ceil();
                final h = ((box.maxHeight - gap * (rows - 1)) / rows).clamp(48.0, 60.0);
                return GridView.count(
                  crossAxisCount: cols,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: (box.maxWidth - gap) / cols / h,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    for (final t in teams)
                      _TeamButton(
                        team: t,
                        side: setup.awayId == t.id ? '원정' : (setup.homeId == t.id ? '홈' : null),
                        onTap: () => tapTeam(t),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamButton extends StatelessWidget {
  const _TeamButton({required this.team, required this.side, required this.onTap});

  final TeamSummary team;
  final String? side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final selected = side != null;
    return _PickTile(
      selected: selected,
      onTap: onTap,
      minHeight: 48,
      semanticsLabel: '${team.name}, ${team.wins}승 ${team.losses}패${selected ? ', $side팀으로 선택됨' : ''}',
      child: Row(
        children: [
          Expanded(child: Text(team.name, style: text.titleSmall!.copyWith(color: selected ? k.onBand : k.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// ② 선발투수: 팀마다 지금 선발과 시즌 기록, 바꾸기.
class _StartersStep extends StatelessWidget {
  const _StartersStep({required this.setup, required this.data, required this.onChanged});

  final GameSetup setup;
  final AppData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;

    Future<void> change(String teamId) async {
      final current = setup.starterOf(data, teamId);
      final chosen = await pickPlayer(
        context,
        title: '${data.team(teamId).shortName} 선발투수 고르기',
        candidateIds: [for (final id in GameSetup.starterCandidates(data, teamId)) if (id != current) id],
        data: data,
        pitcher: true,
      );
      if (chosen == null) return;
      setup.setStarter(data, teamId, chosen);
      onChanged();
    }

    Widget team(String side, String teamId) {
      final t = data.team(teamId);
      final p = data.player(setup.starterOf(data, teamId));
      final auto = data.season.lineups[teamId]!.pitcherId;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$side ${t.name}', style: text.bodySmall!.copyWith(color: k.inkSub)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(p.name, style: text.headlineSmall)),
                TextButton(onPressed: () => change(teamId), child: Text('${t.shortName} 선발 바꾸기')),
              ],
            ),
            Text(keepAll(pitcherLine(p)), style: text.bodyMedium!.copyWith(color: k.inkSub)),
            if (p.id != auto)
              Text('자동 선발 ${data.player(auto).name} 대신', style: text.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final notices = {for (final id in [setup.awayId!, setup.homeId!]) data.season.teams[id]!.membershipNotice};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: [
        team('원정', setup.awayId!),
        Divider(height: 28, color: k.stripe, thickness: 2),
        team('홈', setup.homeId!),
        const SizedBox(height: 14),
        for (final n in notices)
          if (n.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(keepAll(n), style: text.bodySmall!.copyWith(color: k.inkSub)),
            ),
      ],
    );
  }
}

/// ③ 라인업: 원정·홈을 바꿔 보며 타순 9명을 확인하고, 줄을 눌러 타순을 바꾸거나 다른 타자를 넣는다.
class _LineupStep extends StatelessWidget {
  const _LineupStep({
    required this.setup,
    required this.data,
    required this.home,
    required this.onSide,
    required this.onChanged,
  });

  final GameSetup setup;
  final AppData data;
  final bool home;
  final ValueChanged<bool> onSide;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final teamId = home ? setup.homeId! : setup.awayId!;
    final order = setup.orderOf(data, teamId);
    final auto = setup.isAutoOrder(data, teamId);

    Future<void> edit(int slot) async {
      final action = await showModalBottomSheet<(String, Object)>(
        context: context,
        showDragHandle: true,
        builder: (context) => _SlotActions(
          slot: slot,
          name: data.player(order[slot - 1]).name,
          order: [for (final id in order) data.player(id).name],
        ),
      );
      if (action == null || !context.mounted) return;
      if (action.$1 == 'swap') {
        setup.swapOrder(data, teamId, slot, action.$2 as int);
        onChanged();
      } else {
        final chosen = await pickPlayer(
          context,
          title: '$slot번 ${data.player(order[slot - 1]).name} 대신 칠 타자',
          candidateIds: setup.benchBatters(data, teamId),
          data: data,
          pitcher: false,
        );
        if (chosen == null) return;
        setup.replaceBatter(data, teamId, slot, chosen);
        onChanged();
      }
    }

    Widget side(String label, bool isHome) {
      final t = data.team(isHome ? setup.homeId! : setup.awayId!);
      return Expanded(
        child: _PickTile(
          selected: home == isHome,
          radio: true,
          minHeight: 44,
          onTap: () => onSide(isHome),
          semanticsLabel: '$label ${t.name} 라인업 보기',
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text('$label ${t.shortName}',
                style: text.titleSmall!.copyWith(color: home == isHome ? k.onBand : k.ink)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [side('원정', false), const SizedBox(width: 8), side('홈', true)]),
          SectionTitle(
            auto ? '자동 라인업' : '바꾼 라인업',
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
            trailing: auto
                ? null
                : TextButton(
                    onPressed: () {
                      setup.resetOrder(teamId);
                      onChanged();
                    },
                    child: const Text('자동으로 되돌리기'),
                  ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final h = (box.maxHeight / 9).clamp(36.0, 48.0);
              return ListView(
                physics: const ClampingScrollPhysics(),
                children: [
                  for (var i = 0; i < 9; i++)
                    _BatterRow(
                      slot: i + 1,
                      player: data.player(order[i]),
                      position: positionShortLabel(setup.positionOf(data, teamId, order[i])),
                      height: h,
                      striped: i.isEven,
                      onTap: () => edit(i + 1),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// 라인업 표의 수비 위치. 모르면 빈칸.
String positionShortLabel(String code) => code.isEmpty ? '' : positionLabel(code);

class _BatterRow extends StatelessWidget {
  const _BatterRow({
    required this.slot,
    required this.player,
    required this.position,
    required this.height,
    required this.striped,
    required this.onTap,
  });

  final int slot;
  final PlayerCard player;
  final String position;
  final double height;
  final bool striped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$slot번 ${player.name}, $position, 타율 ${avg(player.battingAverage)}. 눌러서 바꾸기',
      excludeSemantics: true,
      child: Material(
        color: striped ? k.stripe : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                SizedBox(width: 34, child: Center(child: Text('$slot', style: text.titleSmall!.copyWith(color: k.inkSub)))),
                Expanded(child: Text(player.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                SizedBox(width: 56, child: Text(position, style: text.bodySmall!.copyWith(color: k.inkSub))),
                SizedBox(
                  width: 92,
                  child: Text('타율 ${avg(player.battingAverage)}',
                      style: text.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 타순 한 줄을 눌렀을 때: 다른 타순과 맞바꾸기, 또는 벤치 타자로 바꾸기.
class _SlotActions extends StatelessWidget {
  const _SlotActions({required this.slot, required this.name, required this.order});

  final int slot;
  final String name;
  final List<String> order;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$slot번 $name', style: text.titleLarge),
            const SizedBox(height: 4),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 9; i++)
                  if (i != slot)
                    Semantics(
                      button: true,
                      label: '$i번 ${order[i - 1]}와 맞바꾸기',
                      excludeSemantics: true,
                      child: Material(
                        color: k.stripe,
                        borderRadius: BorderRadius.circular(cardRadius),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(cardRadius),
                          onTap: () => Navigator.pop(context, ('swap', i)),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('$i번', style: text.titleSmall),
                                  Text(order[i - 1], style: text.bodySmall!.copyWith(color: k.inkSub)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: bandButtonStyle(context),
              onPressed: () => Navigator.pop(context, ('replace', slot)),
              child: const Text('다른 타자로 바꾸기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ④ 승리 예측: 두 팀 중 하나. 팀마다 시즌 성적과 이번 경기 선발.
class _PredictStep extends StatelessWidget {
  const _PredictStep({required this.setup, required this.data, required this.onChanged});

  final GameSetup setup;
  final AppData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;

    Widget pick(String side, String teamId) {
      final t = data.team(teamId);
      final selected = setup.predictedWinnerId == teamId;
      final sp = data.player(setup.starterOf(data, teamId));
      final fg = selected ? k.onBand : k.ink;
      final sub = selected ? k.onBand : k.inkSub;
      return _PickTile(
        selected: selected,
        radio: true,
        minHeight: 88,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        semanticsLabel: '$side ${t.name} 승리 예측',
        onTap: () {
          setup.predictedWinnerId = teamId;
          onChanged();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(side, style: text.bodySmall!.copyWith(color: sub)),
            Text(t.name, style: text.headlineSmall!.copyWith(color: fg)),
            Text(
              keepAll('승률 ${t.winRate.toStringAsFixed(3)}, 타율 ${avg(t.battingAverage)}, 평균자책 ${era(t.era)}, 선발 ${sp.name}'),
              style: text.bodySmall!.copyWith(color: sub),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: [
        pick('원정', setup.awayId!),
        const SizedBox(height: 8),
        pick('홈', setup.homeId!),
      ],
    );
  }
}
