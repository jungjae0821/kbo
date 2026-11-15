import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_data.dart';
import '../theme/kbo_theme.dart';
import '../widgets/ground_layout.dart';
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
    final text = Theme.of(context).textTheme;
    final otherId = _active == _Side.away ? _homeId : _awayId;
    final activeId = _active == _Side.away ? _awayId : _homeId;
    final teams = [...data.teams]..sort((a, b) => b.winRate.compareTo(a.winRate));

    return GroundLayout(
      title: '팀 선택',
      ground: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('대결할 두 팀을 고르세요', style: text.headlineSmall?.copyWith(color: k.chalk)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Slot(
                    label: '원정',
                    team: _awayId == null ? null : data.team(_awayId!),
                    active: _active == _Side.away,
                    onTap: () => setState(() => _active = _Side.away),
                  ),
                ),
                IconButton(
                  tooltip: '원정과 홈 바꾸기',
                  onPressed: _awayId == null && _homeId == null ? null : _swap,
                  color: k.chalk,
                  disabledColor: k.chalkSub.withValues(alpha: 0.5),
                  icon: const Icon(Icons.swap_horiz),
                ),
                Expanded(
                  child: _Slot(
                    label: '홈',
                    team: _homeId == null ? null : data.team(_homeId!),
                    active: _active == _Side.home,
                    onTap: () => setState(() => _active = _Side.home),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      sheet: SheetBody(
        children: [
          SheetHeading(_active == _Side.away ? '원정팀 고르기' : '홈팀 고르기', first: true),
          for (final team in teams)
            _TeamTile(
              team: team,
              selected: team.id == activeId,
              takenBy: team.id == otherId ? (_active == _Side.away ? '홈팀' : '원정팀') : null,
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

class _Slot extends StatelessWidget {
  const _Slot({required this.label, required this.team, required this.active, required this.onTap});

  final String label;
  final TeamSummary? team;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: active,
      label: '$label ${team?.name ?? '선택 안 함'}',
      excludeSemantics: true,
      child: Material(
        color: active ? k.grassDeep : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: active ? k.chalk : k.chalkSub.withValues(alpha: 0.5), width: active ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall?.copyWith(color: k.chalkSub)),
                const SizedBox(height: 2),
                Text(
                  team?.name ?? '선택',
                  style: text.titleMedium?.copyWith(color: team == null ? k.chalkSub : k.chalk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.team, required this.selected, required this.takenBy, required this.onTap});

  final TeamSummary team;
  final bool selected;
  final String? takenBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final disabled = takenBy != null;
    final record = '${team.wins}승 ${team.losses}패 ${team.ties}무, 득점 ${team.runsScored} 실점 ${team.runsAllowed}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? k.grass : k.sheetRaised,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: text.titleMedium?.copyWith(
                            color: selected ? k.chalk : (disabled ? k.inkSub : k.ink),
                          ),
                        ),
                        Text(
                          record,
                          style: text.bodySmall?.copyWith(color: selected ? k.chalkSub : k.inkSub),
                        ),
                      ],
                    ),
                  ),
                  if (disabled)
                    Text('$takenBy로 선택됨', style: text.bodySmall?.copyWith(color: k.inkSub))
                  else if (selected)
                    Icon(Icons.check, color: k.chalk),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
