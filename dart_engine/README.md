# Dart 경기 엔진 v2.1.0

1주 차 `season_dataset.json`을 읽어 타석 단위로 가상 경기를 진행합니다. Flutter와 외부 패키지, API 키가 필요하지 않습니다. Dart SDK 3 이상을 사용하며 Dart 3.13.7에서 검증했습니다.

## 실행

저장소 루트에서 PowerShell로 실행합니다.

```powershell
cd dart_engine
dart run bin/simulate.dart --list-teams
dart run bin/simulate.dart --away sr:competitor:249967 --home sr:competitor:249977 --seed 42 --game-id engine-2.1.0-example-42 --output ../outputs/engine_2_1_0_example_game.json
```

기본 대진은 JSON의 첫 두 팀입니다. 위 `seed=42` 예제(원정 KT, 홈 삼성)의 2.1.0 결과는 **KT 5 : 4 삼성**, 9회 종료, 75타석입니다. 가상 결과이며 실제 경기 결과가 아닙니다. 2주 차 1.0 예제(KT 9 : 2 삼성)는 다른 규칙 버전의 기록입니다.

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
- `src/probability.dart`: 보정된 타자·투수의 8종 사건 확률을 산술평균 후 정규화합니다. 200 PA/BF 보정을 다시 적용하지 않습니다. 음수·비수치·비정상 합계는 거부합니다.
- `src/game.dart`: 화면과 독립된 진루 규칙, 불변 경기 상태, 타석 로그, 진행 엔진입니다. 교체가 없으면 선발투수 성적을 끝까지 사용합니다.

## 적용 규칙

| 타석 결과 | 주자 이동 규칙 (엔진 2.1.0) |
| --- | --- |
| 삼진 | 아웃 1개 증가, 주자는 현재 베이스 유지 |
| 기타 아웃 | 아웃 1개 증가. 0·1아웃에 1루 주자가 있으면 18% 확률로 병살(아웃 2개). 병살이 아니면 3루 주자가 52% 확률로 득점(희생플라이·땅볼 타점)하고, 그다음 2루 주자가 3루가 비어 있으면 35%, 1루 주자가 2루가 비어 있으면 20% 확률로 한 베이스 진루(진루타) |
| 볼넷·몸에 맞는 공 | 타자는 1루, 밀어내기가 필요한 주자만 이동 |
| 단타 | 3루 주자 득점, 2루 주자 60% 득점·나머지 3루, 1루 주자는 3루가 비면 28% 3루·나머지 2루 |
| 2루타 | 2·3루 주자 득점, 1루 주자 42% 득점·나머지 3루 |
| 3루타 | 기존 주자 전원 득점, 타자는 3루 |
| 홈런 | 기존 주자와 타자 모두 득점 |

안타 때 추가 진루율은 프로야구 장기 평균 근사치이고, 병살·득점 아웃 확률은 2026 시즌 시뮬레이션의 병살타/타석과 희생플라이/타석이 실제 리그 값(1.84%, 0.77%)과 맞도록 2.0.0에서 보정했습니다. 2.1.0에서 아웃 때 진루를 더한 뒤 18,000경기 기준 병살타/타석은 1.89%, 아웃 중 득점/타석은 0.88%입니다. 아웃 중 득점에는 땅볼 타점도 들어가므로 희생플라이만 센 실제 값보다 높은 것이 맞습니다. 아웃 때 진루율(35%, 20%)은 데이터에 KBO 집계가 없어 근사치이며, 후보 격자에서 득점 변화가 작아(팀당 4.20~4.32점) 가운데 값을 골랐습니다([보정 근거](../outputs/week5_calibration_report.json)). 3아웃이 되는 플레이에서는 득점을 인정하지 않습니다. 도루·실책·폭투·희생번트의 주자 진루는 아직 생략합니다.

상황 진루 확률은 `BaserunningRates`에 모여 있고, 그 추첨값은 타석 로그의 `baserunning_draws`에, 병살·득점 아웃·진루타는 `play_note`(`double_play`, `run_scored_on_out`, `runner_advanced_on_out`)에 남습니다. 득점과 진루가 함께 일어나면 `run_scored_on_out`입니다. 순수 함수 `advanceBases`·`applyPlateAppearance`에 `draw`를 넘기지 않으면 상황 진루는 일어나지 않습니다. 3아웃에 공수를 교대하고 타순은 팀별로 다음 이닝에도 이어집니다.

9회초 종료 후 홈팀이 앞서면 9회말을 생략합니다. 9회말부터 승리 득점이 나오면 즉시 끝내며, 일반 끝내기는 승리 득점까지만 인정하고 끝내기 홈런은 모든 득점을 인정합니다. 동점은 최대 11회(`maxInnings`)까지 진행합니다. 이닝별 점수의 `null`은 진행하지 않은 공수, `0`은 진행한 공수의 무득점을 뜻합니다.

타석 로그에는 결과를 낸 이닝·공수와 타자·투수 ID, 확률, 추첨값, 난수 상태, 득점한 선수, 해당 타석 직후 아웃·주자, 전후 경기 상태를 기록합니다. `after`는 공수 교대까지 반영하므로 3아웃 타석의 `after.outs`는 다음 공수의 0일 수 있습니다. `outs_after_play`는 그 타석에서 발생한 3아웃을 그대로 남깁니다.

## 투수 교체와 대타

타석 사이에 `substitutePitcher(팀, 선수)`와 `pinchHit(팀, 선수)`로 교체합니다. 후보는 `pitcherCandidates`·`pinchHitterCandidates`가 돌려주며, 그 팀에 공식 소속으로 분류되고 해당 역할 프로필을 그대로 쓸 수 있으며 이 경기에 아직 나오지 않은 선수만 들어갑니다. 실제 야구처럼 빠진 선수는 다시 나올 수 없고, 대타는 그 타순을 이어받아 경기 끝까지 칩니다. 수비 위치는 엔진 계산에 쓰지 않으므로 바꾸지 않습니다. 교체는 엔진 API에서는 양 팀 모두 가능하고, 앱은 사용자가 예측한 팀만 허용합니다. 투수는 최소 한 타자를 상대해야 바꿀 수 있으며(`canSubstitutePitcher`), 그 전에 바꾸려 하면 오류를 냅니다.

교체는 경기 JSON의 `substitutions`에 종류, 팀, 나간·들어간 선수, 적용된 첫 타석 번호, 이닝·공수, 대타의 타순으로 기록됩니다. 같은 seed에서 같은 타석 번호에 같은 교체를 하면 경기가 그대로 재현됩니다. 2.1.0은 아웃 때 진루 추첨이 더해져 2.0.0 경기를 재현하지 않습니다. 회귀 기준 예제는 `outputs/engine_2_1_0_example_game.json`입니다. 두 아웃 진루율을 0으로 넘기면(`GameEngine(baserunning: ...)`, 보정 도구 전용) 2.0.0 예제를 그대로 재현하며 테스트로 확인합니다. 앱 경기는 항상 기본값을 쓰고, 체크포인트 복원도 기본값으로 합니다.

경기 전 선발은 생성자의 `startingPitchers: {팀 ID: 선수 ID}`로 정합니다. 후보는 `GameEngine.starterCandidates(dataset, 팀)`이며 자동 선발을 포함하고 자동 타순의 타자는 뺍니다. 고른 선발은 교체가 아니므로 `substitutions`에 남지 않고 경기 JSON의 `starting_pitchers`에 기록됩니다. 고르지 않은 자동 선발은 그 경기의 교체 후보로 남습니다.

## 재현과 경기 ID

난수 알고리즘은 고정된 `park_miller_16807_v1`이며 seed 범위는 0~2147483645입니다. 같은 데이터 버전·엔진 버전·대진·타순·seed이면 타석 순서와 결과를 재현합니다. JSON 전체를 바이트 단위로 비교하려면 `--game-id`도 동일하게 지정합니다. ID를 생략하면 실행 시각과 프로세스 내 순번으로 새 ID를 발급합니다. 향후 여러 기기에서 공유하는 ID는 호출 측에서 UUID 등을 전달할 수 있습니다.

경기 JSON은 `game_id`, `engine_version`, `data_version`, `seed`, `random_algorithm`, `random_state`, `max_innings`, `baserunning_rates`, 대진, 승리 팀, 상태와 로그를 포함합니다. 무승부 또는 진행 중일 때 승리 팀은 `null`입니다. 중단 상태 저장에는 `toCheckpoint()`를 씁니다. 체크포인트는 경기 ID, 엔진·데이터 버전, 난수 알고리즘, seed, 대진, 선발, 교체 목록, 진행한 타석 수, 난수 상태와 현재 상태만 담습니다. `GameEngine.restore(dataset, checkpoint)`는 같은 seed로 타석을 다시 진행하면서 기록된 타석 번호에 교체를 적용해 경기를 되살리고, 난수 상태와 현재 상태가 저장값과 같은지 확인합니다. 엔진·데이터 버전이 다르거나 내용이 맞지 않으면 `FormatException`을 냅니다. 예측·채점과 파일 저장은 앱(`app/lib/state/`)이 맡습니다. 비정상 입력으로 한 경기가 10,000타석을 넘으면 미완료 상태로 오류를 반환하며 임의로 종료 결과를 만들지 않습니다.

## 검증

```powershell
dart analyze
dart run test/engine_test.dart
```

검증 보고서를 다시 생성하려면 `dart run test/engine_test.dart ../kbo_data/kbo_2026_138278/app/season_dataset.json ../outputs/week5_engine_validation_report.json`을 실행합니다.

테스트 러너는 외부 테스트 패키지 없이 실패 시 종료 코드 1을 반환합니다. **48개 검사 통과** (5주 차에 아웃 때 진루, 2.1.0 예제 재현, 진루율 0일 때 2.0.0 예제 재현, seed 분산, 반복 집계 합계 일치, 1,000경기 유효성·추첨 편향(z<4), 신뢰구간·상관계수, 리그 평균 기준선 8개 추가, `outputs/week5_engine_validation_report.json`. 4주 차에 체크포인트 복원·완료 경기 복원·버전과 변조 거부 3개 추가, `outputs/week4_engine_validation_report.json`). 3주 차까지의 38개: 실제 시즌 입력, 잘못된 버전·선수·확률 거부, 8종 추첨, PRNG 고정 벡터, 8가지 볼넷·사구 강제 진루, 주자 배치·타석 결과·아웃 수·추첨 전 조합의 주자 보존, 안타 추가 진루·병살·희생플라이, 타순·공수 교대, 9회말 생략, 끝내기, 연장·11회 무승부, 동일 seed 재현, 10개 실제 팀 대진의 점수·로그 일관성, 교체 없는 2.0.0 경기가 저장 예제와 같은지, 투수 최소 1타자 규칙, 진루 추첨 기록과 재현, 투수 교체·대타 규칙과 교체 포함 재현, 경기 전 선발 지정과 잘못된 선발 거부를 확인했습니다. 테스트에서 사용하는 선수 수는 현재 2026 시즌 데이터의 591명을 기준으로 합니다.

검증 기록: [2주 차 검증 결과](../outputs/week2_validation_report.json), [5주 차 검증 결과](../outputs/week5_validation_report.json). 실행 예제 전체 로그: [2.1.0 seed 42 경기](../outputs/engine_2_1_0_example_game.json).

## 반복 시뮬레이션과 보정 근거

```powershell
dart run bin/batch_simulate.dart --seeds 200 --fixed-seeds 2000 --output ../outputs/week5_simulation_report.json
dart run bin/calibrate.dart ../outputs/week5_calibration_report.json
```

`batch_simulate.dart`는 고정 대진(기본: 첫 두 팀) 2,000경기와 90개 대진 × 200경기(18,000경기)를 자동 타순·선발, 교체 없이 진행합니다. 원정 승률과 95% 구간(Wilson), 득점 평균·표준편차·분포, 무승부·연장·끝내기 비율, 8종 사건 비율을 계산해 실제 2026 리그 값(시즌 JSON의 팀 합계·리그 기준값)과 비교합니다. 팀별 득점·승률 상관도 함께 기록합니다. 모두 합쳐 2초 안팎이 걸립니다. `calibrate.dart`는 아웃 때 진루율 격자별 득점과, 모든 타석에 리그 평균 확률을 넣었을 때의 9이닝 득점(엔진 구조만의 기준선)을 계산합니다.

경기마다 `spreadSeeds`가 `dart:math` Random으로 뽑은 서로 다른 seed를 씁니다. 앱이 seed를 고르는 방식(`Random().nextInt`)과 같습니다. 연속된 작은 seed는 Park–Miller 첫 추첨값이 `(seed + 1) × 16807 / (2³¹ − 1)`이라 모두 삼진으로 시작하고, Park–Miller 수열에서 뽑은 seed는 그 수열의 상태 자체라 경기들이 한 칸씩 밀린 같은 수열이 됩니다. 여러 대진에 같은 seed 목록을 재사용하면 표본이 목록 길이만큼으로 줄어듭니다. 세 경우 모두 5주 차 분석 중 실제로 결과를 왜곡해 바로잡았습니다.

5주 차 결과(엔진 2.1.0): 사건 비율은 엔진이 추첨한 입력 확률과 0.1%p 안에서 일치하고, 병살타/타석은 실제와 맞습니다. 팀당 득점은 4.21점으로 실제 5.07점보다 약 17% 낮습니다. 리그 평균 확률만 넣어도 9이닝 4.55점이라 약 10%는 도루·실책·폭투가 없는 엔진 구조에서, 나머지는 주전 9명과 선발투수만 쓰는 입력(삼진 많고 볼넷 적음)에서 옵니다. 새 사건을 넣어 맞추지 않고 이 차이를 한계로 기록했습니다.
