import 'package:flutter/material.dart';

import '../data/app_data.dart';
import '../theme/kbo_theme.dart';

/// 팀 엠블럼 (앱에 포함한 이미지). 이미지가 없거나 읽지 못하면 같은 크기의 빈 칸이라 줄 맞춤이 유지된다.
class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.team, this.size = 22});

  final TeamSummary team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = team.logoAsset;
    final box = SizedBox(width: size, height: size);
    if (asset == null) return box;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => box,
        ),
      ),
    );
  }
}

/// 선수 얼굴 사진 (KBO 공식 사이트). 받는 동안이나 받지 못하면 이름 첫 글자를 보인다.
class PlayerPhoto extends StatelessWidget {
  const PlayerPhoto({super.key, required this.player, this.size = 56});

  final PlayerCard player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.kbo;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(size * 0.18);
    final initial = player.name.isEmpty ? '?' : player.name.characters.first;
    final placeholder = Container(
      width: size,
      height: size * 1.25,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: k.stripe, borderRadius: radius),
      child: Text(initial, style: text.titleLarge!.copyWith(color: k.inkSub, fontSize: size * 0.4)),
    );
    final url = player.photoUrl;
    if (url == null) return ExcludeSemantics(child: placeholder);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: radius,
        child: Image.network(
          url,
          width: size,
          height: size * 1.25,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          // 사진을 받는 동안·받지 못했을 때는 글자 자리표시. 경기 진행에는 영향이 없다.
          loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
          errorBuilder: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}
