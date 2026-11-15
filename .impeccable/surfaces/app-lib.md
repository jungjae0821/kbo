---
version: 1
slug: "app-lib"
primary_target: "app/lib"
related_targets: []
---

# 경기 흐름 화면 (Flutter 앱 6개 화면)

모드: Operate. 대상: 야구팬 개인 플레이어. 할 일: 두 팀을 고르고 승리 팀을 예측한 뒤 가상 경기를 한 타석씩 진행해 결과를 확인한다.

## Direction contract

THESIS: 화면 위쪽은 실제 그라운드(잔디·흙·석회선)이고 경기 상태는 그 위에 선수 이름으로 선다. 흔한 스포츠 앱의 "카드 더미 + 점수 배너"를 거부한다.
OWN-WORLD: 잔디 #2C6440 면이 화면 30~50%, 내야 흙 #B65C33는 다이아몬드와 주 버튼에만, 석회 흰색 글자. 아래는 회녹 시트 #F4F5F1, 테두리 없이 면 단계. 경기천년제목/바탕, 알약형 버튼.
STORY: 사용자는 지금 몇 회 몇 아웃, 누가 어느 베이스에 있는지를 그림으로 이해하고, 내 예측이 확정됐다는 것을 믿고, 다음 타석을 누른다.
FIRST VIEWPORT: 앱 바(뒤로, "가상 경기"), 그 아래 원정 점수 · 이닝 · 홈 점수(52sp), 가운데 흙 다이아몬드에 주자·타자·투수 이름표와 아웃 표시, 아래 시트에 한 크기 라인스코어와 최근 타석 3개, 예측 상태, 맨 아래 흙색 "다음 타석"과 보조 "끝까지".
FORM: 자체 방향 목록 6번째(내야 그라운드 재료), 시간표 시안의 "한 크기, 굵기로 위계" 규율을 기록 시트에 반영. seed:a686c2ff9db55993
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
