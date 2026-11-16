# Dart 경기 엔진 v1.1.0

1주 차 `season_dataset.json`을 읽어 타석 단위로 가상 경기를 진행합니다. Flutter와 외부 패키지, API 키가 필요하지 않습니다. Dart SDK 3 이상을 사용하며 Dart 3.13.7에서 검증했습니다.

## 실행

저장소 루트에서 PowerShell로 실행합니다.

```powershell
cd dart_engine
dart run bin/simulate.dart --list-teams
dart run bin/simulate.dart --seed 42 --game-id week2-example-42 --output ../outputs/week2_example_game.json
```

기본 대진은 JSON의 첫 두 팀인 원정 KT와 홈 삼성입니다. `seed=42` 예제 결과는 **KT 9 : 2 삼성**, 9회 종료, 79타석입니다. 가상 결과이며 실제 경기 결과가 아닙니다.

```powershell
dart run bin/simulate.dart --away sr:competitor:249969 --home sr:competitor:249965 --seed 123 --verbose
dart run bin/simulate.dart --help
```

`--dataset PATH`로 입력 파일을 지정합니다. 기본 경로는 `dart_engine` 작업 디렉터리 기준 `../kbo_data/kbo_2026_138278/app/season_dataset.json`입니다. 다른 디렉터리에서 실행할 때는 `--dataset`을 지정하세요. 옵션 오류나 잘못된 데이터는 메시지와 종료 코드 1을 반환합니다.

## 코드 연결

`lib/kbo_engine.dart`가 공개 진입점입니다. 엔진 라이브러리는 `dart:io`를 사용하지 않으며, JSON 파일 읽기와 저장은 CLI가 담당합니다. Flutter에서는 asset 또는 캐시에서 읽은 JSON Map을 전달하면 됩니다.

```dart
final dataset = SeasonDataset.fromJson(decodedJson);
final game = GameEngine(
  dataset: dataset,
  awayTeamId: 'sr:competitor:249969',
  homeTeamId: 'sr:competitor:249965',
  seed: 42,
);
final firstPlay = game.step(); // 한 타석; before/after와 진루·득점 상세
final snapshot = game.state; // 변경 불가능한 현재 상태
game.substitutePitcher(homeTeamId, game.pitcherCandidates(homeTeamId).first); // 투수 교체
game.pinchHit(awayTeamId, game.pinchHitterCandidates(awayTeamId).first); // 다음 타자 대신 대타
game.playToEnd(); // 남은 경기 전체 실행; 종료 후 다시 호출해도 결과 유지
final result = game.toJson(); // 메타데이터, 최종 상태, 모든 타석 로그
```

- `src/dataset.dart`: 팀·선수·라인업 입력 모델과 참조·소속·중복·포지션·선정 선수 프로필 검사. 지원하지 않는 스키마나 확률 결합 규칙을 거부합니다. 원본 통계의 정합성·해시 검증은 기존 Python 생성기에서 수행합니다.
- `src/probability.dart`: 보정된 타자·투수의 7종 사건 확률을 산술평균 후 정규화합니다. 200 PA/BF 보정을 다시 적용하지 않습니다. 음수·비수치·비정상 합계는 거부합니다.
- `src/game.dart`: 화면과 독립된 진루 규칙, 불변 경기 상태, 타석 로그, 진행 엔진입니다. 교체가 없으면 선발투수 성적을 끝까지 사용합니다.

## 적용 규칙

삼진·기타 아웃은 아웃 1개와 주자 유지, 볼넷은 강제 진루, 단타·2루타는 각각 1·2베이스 이동, 3루타는 기존 주자 전원 득점, 홈런은 타자까지 득점합니다. 3아웃에 공수를 교대하고 타순은 팀별로 다음 이닝에도 이어집니다.

9회초 종료 후 홈팀이 앞서면 9회말을 생략합니다. 9회말부터 승리 득점이 나오면 즉시 끝내며, 일반 끝내기는 승리 득점까지만 인정하고 끝내기 홈런은 모든 득점을 인정합니다. 동점은 최대 12회까지 진행합니다. 이닝별 점수의 `null`은 진행하지 않은 공수, `0`은 진행한 공수의 무득점을 뜻합니다.

타석 로그에는 결과를 낸 이닝·공수와 타자·투수 ID, 확률, 추첨값, 난수 상태, 득점한 선수, 해당 타석 직후 아웃·주자, 전후 경기 상태를 기록합니다. `after`는 공수 교대까지 반영하므로 3아웃 타석의 `after.outs`는 다음 공수의 0일 수 있습니다. `outs_after_play`는 그 타석에서 발생한 3아웃을 그대로 남깁니다.

## 투수 교체와 대타 (v1.1.0)

타석 사이에 `substitutePitcher(팀, 선수)`와 `pinchHit(팀, 선수)`로 교체합니다. 후보는 `pitcherCandidates`·`pinchHitterCandidates`가 돌려주며, 그 팀에 공식 소속으로 분류되고 해당 역할 프로필을 그대로 쓸 수 있으며 이 경기에 아직 나오지 않은 선수만 들어갑니다. 실제 야구처럼 빠진 선수는 다시 나올 수 없고, 대타는 그 타순을 이어받아 경기 끝까지 칩니다. 수비 위치는 엔진 계산에 쓰지 않으므로 바꾸지 않습니다. 교체는 엔진 API에서는 양 팀 모두 가능하고, 앱은 사용자가 예측한 팀만 허용합니다.

교체는 경기 JSON의 `substitutions`에 종류, 팀, 나간·들어간 선수, 적용된 첫 타석 번호, 이닝·공수, 대타의 타순으로 기록됩니다. 같은 seed에서 같은 타석 번호에 같은 교체를 하면 경기가 그대로 재현됩니다. 교체가 없으면 1.0.0과 같은 결과가 나옵니다.

경기 전 선발은 생성자의 `startingPitchers: {팀 ID: 선수 ID}`로 정합니다. 후보는 `GameEngine.starterCandidates(dataset, 팀)`이며 자동 선발을 포함하고 자동 타순의 타자는 뺍니다. 고른 선발은 교체가 아니므로 `substitutions`에 남지 않고 경기 JSON의 `starting_pitchers`에 기록됩니다. 고르지 않은 자동 선발은 그 경기의 교체 후보로 남습니다.

## 재현과 경기 ID

난수 알고리즘은 고정된 `park_miller_16807_v1`이며 seed 범위는 0~2147483645입니다. 같은 데이터 버전·엔진 버전·대진·타순·seed이면 타석 순서와 결과를 재현합니다. JSON 전체를 바이트 단위로 비교하려면 `--game-id`도 동일하게 지정합니다. ID를 생략하면 실행 시각과 프로세스 내 순번으로 새 ID를 발급합니다. 향후 여러 기기에서 공유하는 ID는 호출 측에서 UUID 등을 전달할 수 있습니다.

경기 JSON은 `game_id`, `engine_version`, `data_version`, `seed`, `random_algorithm`, `random_state`, 대진, 승리 팀, 상태와 로그를 포함합니다. 무승부 또는 진행 중일 때 승리 팀은 `null`입니다. 중단 상태의 파일 저장·복구와 예측·채점은 4주 차 작업입니다. 비정상 입력으로 한 경기가 10,000타석을 넘으면 미완료 상태로 오류를 반환하며 임의로 종료 결과를 만들지 않습니다.

## 검증

```powershell
dart analyze
dart run test/engine_test.dart
```

검증 보고서를 다시 생성하려면 `dart run test/engine_test.dart ../kbo_data/kbo_2026_138278/app/season_dataset.json ../outputs/week2_validation_report.json`을 실행합니다.

테스트 러너는 외부 테스트 패키지 없이 실패 시 종료 코드 1을 반환합니다. **34개 검사 통과**: 실제 시즌 입력, 잘못된 버전·선수·확률 거부, 7종 추첨, PRNG 고정 벡터, 8가지 볼넷 강제 진루, 56가지 주자 배치·타석 결과, 타순·공수 교대, 9회말 생략, 끝내기, 연장·12회 무승부, 동일 seed 재현, 10개 실제 팀 대진의 점수·로그 일관성, 교체 없는 1.1.0 경기가 2주 차 예제와 같은지, 투수 교체·대타 규칙과 교체 포함 재현, 경기 전 선발 지정과 잘못된 선발 거부를 확인했습니다. 테스트에서 사용하는 선수 수는 현재 2026 시즌 데이터의 591명을 기준으로 합니다.

검증 기록: [2주 차 검증 결과](../outputs/week2_validation_report.json). 실행 예제 전체 로그: [seed 42 경기](../outputs/week2_example_game.json). 1,000회 반복 시뮬레이션과 리그 득점 분포 보정은 5주 차에 수행합니다.
