import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../state/labels.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
import '../widgets/record_sheet.dart';
import 'compare_screen.dart';

enum _Side { away, home }

class TeamSelectScreen extends StatefulWidget {
  const TeamSelectScreen({super.key});

  @override
  State<TeamSelectScreen> createState() => _TeamSelectScreenState();
}

class _TeamSelectScreenState extends State<TeamSelectScreen> {
  String? _awayId;
  String? _homeId;
  _Side _active = _Side.away;

  void _pick(TeamSummary team) {
    setState(() {
      if (_active == _Side.away) {
        _awayId = team.id;
        if (_homeId == null) _active = _Side.home;
      } else {
        _homeId = team.id;
        if (_awayId == null) _active = _Side.away;
      }
    });
  }

  void _swap() => setState(() {
        final a = _awayId;
        _awayId = _homeId;
        _homeId = a;
      });

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data.data!;
    final k = context.kbo;
    final otherId = _active == _Side.away ? _homeId : _awayId;
    final activeId = _active == _Side.away ? _awayId : _homeId;
    final teams = [...data.teams]..sort((a, b) => b.winRate.compareTo(a.winRate));

    Widget slot(_Side side) {
      final id = side == _Side.away ? _awayId : _homeId;
      final label = side == _Side.away ? '원정' : '홈';
      final active = _active == side;
      final name = id == null ? (active ? '아래 순위표에서 고르세요' : '선택 전') : data.team(id).name;
      return GroundTeamRow(
        side: label,
        name: name,
        muted: id == null,
        placeholder: id == null,
        selected: active,
        onTap: () => setState(() => _active = side),
        semanticsLabel: '$label ${id == null ? '선택 전' : data.team(id).name}${active ? ', 지금 고르는 자리' : ''}',
      );
    }

    return GroundLayout(
      title: '팀 선택',
      ground: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 28),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  slot(_Side.away),
                  const SizedBox(height: 6),
                  slot(_Side.home),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '원정과 홈 바꾸기',
              onPressed: _awayId == null && _homeId == null ? null : _swap,
              color: k.chalk,
              disabledColor: k.chalkSub.withValues(alpha: 0.5),
              icon: const Icon(Icons.swap_vert),
            ),
          ],
        ),
      ),
      sheet: SheetBody(
        children: [
          SheetHeading('${_active == _Side.away ? '원정' : '홈'}팀 고르기', first: true),
          const _StandingsHeader(),
          for (final (i, team) in teams.indexed)
            _StandingsRow(
              rank: i + 1,
              team: team,
              selected: team.id == activeId,
              takenBy: team.id == otherId ? (_active == _Side.away ? '홈' : '원정') : null,
              onTap: () => _pick(team),
            ),
        ],
      ),
      actions: ActionRow(
        primary: FilledButton(
          onPressed: _awayId != null && _homeId != null
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CompareScreen(awayId: _awayId!, homeId: _homeId!),
                    ),
                  )
              : null,
          child: const Text('전력 비교'),
        ),
      ),
    );
  }
}

/// 순위표 열 너비. 머리줄과 행이 같은 값을 쓴다.
const _rankW = 40.0;
const _numW = 34.0;
const _tieW = 26.0;
const _rateW = 48.0;

class _StandingsHeader extends StatelessWidget {
  const _StandingsHeader();

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodyMedium!.copyWith(color: context.kbo.inkSub);
    Widget n(String s, double w) => SizedBox(width: w, child: Text(s, style: sub, textAlign: TextAlign.end));
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        child: Row(
          children: [
            SizedBox(width: _rankW, child: Text('순위', style: sub)),
            Expanded(child: Text('팀', style: sub)),
            n('승', _numW),
            n('패', _numW),
            n('무', _tieW),
            n('승률', _rateW),
          ],
        ),
      ),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.rank,
    required this.team,
    required this.selected,
    required this.takenBy,
    required this.onTap,
  });

  final int rank;
  final TeamSummary team;
  final bool selected;

  /// 다른 자리에 이미 들어간 팀이면 그 자리 이름 ('원정' / '홈').
  final String? takenBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final disabled = takenBy != null;
    final fg = selected ? k.chalk : (disabled ? k.inkSub : k.ink);
    final style = base.copyWith(color: fg);
    final sub = base.copyWith(color: selected ? k.chalkSub : k.inkSub);
    Widget n(String s, double w) => SizedBox(width: w, child: Text(s, style: style, textAlign: TextAlign.end));

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$rank위 ${team.name}, ${team.wins}승 ${team.losses}패 ${team.ties}무'
          '${disabled ? ', $takenBy팀으로 선택됨' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? k.grass : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(width: _rankW, child: Text('$rank', style: sub)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: team.name, style: style.copyWith(fontWeight: FontWeight.w700)),
                        if (disabled) TextSpan(text: '  $takenBy', style: sub),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  n('${team.wins}', _numW),
                  n('${team.losses}', _numW),
                  n('${team.ties}', _tieW),
                  n(avg(team.winRate), _rateW),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
