# Dart 경기 엔진용 시즌 데이터 계약 v1.0.0

이 문서는 1주 차에 확정한 앱 입력 JSON의 구조·검증·보정·소속 기준입니다. 2주 차에 구현한 [Dart 경기 엔진](../dart_engine/README.md)이 이 계약을 사용합니다. 시즌 데이터는 `python -m tools.prepare_season_dataset`로 네트워크 호출 없이 생성합니다.

## 파일과 버전

- 입력: `aggregated/corrected_team_season_stats.json`, `corrected_player_season_stats.json`, `team_lineups.json`.
- 출력: `app/season_dataset.json`, `app/dataset_validation_report.json`(시즌 폴더 내부).
- `schema_version`: JSON 구조 버전 `1.0.0`. 앱은 지원하지 않는 버전을 거부합니다.
- `rules.version`: 보정·경기 입력 규칙 버전 `1.0.0`. 200 PA/BF는 초기 기준이며 반복 검증으로 조정하면 규칙·데이터 버전을 갱신합니다.
- `data_version`: 시즌 연도와 내용 SHA-256. 이 필드 자체를 제외한 JSON을 키 정렬·UTF-8·공백 없는 형식으로 직렬화한 해시입니다. 같은 원본·규칙이면 동일합니다. Dart 앱은 이를 불투명한 문자열 ID로 저장하면 됩니다.
- `sources`: 입력 파일명별 원본 바이트 SHA-256. 라인업이 참조한 선수 원본 해시가 현재 입력과 다르면 생성을 중단합니다.
- 데이터 버전과 엔진 버전은 별도입니다. 경기 저장 시 둘 다 기록하며 다른 데이터로 조용히 복구하지 않습니다.

## JSON 구조와 Dart 타입

JSON 키는 snake_case를 유지합니다. Dart에서 `Map<String, dynamic>`으로 디코딩한 뒤 모델의 camelCase 필드로 매핑합니다. 배열의 모든 원소를 읽으며 이름은 표시용이고 ID만 연결 키로 사용합니다. 정수 통계는 `int`, 비율은 `(value as num).toDouble()`, `null`은 nullable 타입으로 읽습니다.

| 최상위 키 | Dart 타입 | 내용 |
| --- | --- | --- |
| `schema_version`, `data_version` | `String` | 구조·데이터 버전 |
| `season` | `Map<String, dynamic>` | 기존 공식 수정본의 시즌 객체. `id`, `year`, `name`은 문자열; 날짜·대회 ID도 보존 |
| `sources` | `Map<String, String>` | 입력 3개 파일 해시 |
| `rules` | `Map<String, dynamic>` | 버전, 7종 사건, prior PA/BF, 결합·소속 규칙, 최대 12회, 선발 전 경기 적용 |
| `league_baselines` | `Map<String, dynamic>` | 타격·투구의 7종 확률, 비홈런 안타 분배 비율, PA/BF 표본 합계·유효 선수 수 |
| `teams` | `List<Team>` | 팀 10개, 원본 팀 통계와 로스터 ID·소속 안내 |
| `players` | `List<PlayerSeasonStats>` | 공식 선수 전체 기록, 소속과 엔진 입력 확률 |
| `lineups` | `List<Lineup>` | 팀별 타자 9명·선발 ID |

`Team`은 `team_id`, `team_name`, `official_team_name`(String), `games`, `wins`, `losses`, `ties`, `runs_scored`, `runs_allowed`(int), `batting`, `pitching`, `fielding`, `running`(통계 Map), `source_files`, `roster_player_ids`(List<String>), `membership_notice`(String)를 갖습니다. 공식 표의 미제공 통계 값은 null로 유지합니다. 팀 지표는 비교 표시·누락 보완용이며 타자·투수 확률에 중복 가산하지 않습니다.

`PlayerSeasonStats`는 `player_id`(`kbo:player:<ID>`), `kbo_player_id`, `player_name`(String), `official_team_names`, `source_files`(List<String>), `batting`, `pitching`, `running`(nullable 통계 Map), `fielding_by_position`(수비 포지션·선발·수비 아웃 수의 List), `assigned_team_id`(String?), `membership_status`, `record_scope`(String), `engine_profiles`를 갖습니다. 공식 수정본의 통계 키와 값을 그대로 보존합니다.

`Lineup`은 `team_id`, `starting_pitcher_id`(String), `batting_order`(List)입니다. 각 타순 원소는 `order`(int 1~9), `player_id`(String), `position_code`(C/1B/2B/3B/SS/LF/CF/RF/DH)입니다. 타순으로 정렬해 사용하고 선수 상세는 players에서 ID로 찾습니다. 팀 내·팀 간 중복 선수는 금지합니다.

`engine_profiles`는 `batting`, `pitching`을 갖고, 해당 역할 기록 자체가 없으면 null입니다. 존재하는 프로필은 다음 필드를 가집니다.

| 키 | 타입 | 의미 |
| --- | --- | --- |
| `sample_size` | `int?` | 타자 PA 또는 투수 BF |
| `prior_sample_size` | `int` | 타자 200 PA / 투수 200 BF |
| `observed_weight` | `double` | n/(n+200), 전부 리그 평균을 쓰면 0 |
| `missing_fields` | `List<String>` | 미제공 필수 필드 |
| `fallback_reason` | `String?` | null / zero_denominator / missing_required_fields |
| `uses_league_hit_split` | `bool` | 투수 피2·3루타 대신 리그 비홈런 안타 분포 사용 여부 |
| `probabilities` | `Map<String, double>` | 아래 7종 확률, 비음수·합계 1 |

## 필수 필드와 7종 결과

타자 필수 정수: `plate_appearances`, `at_bats`, `hits`, `doubles`, `triples`, `home_runs`, `walks`, `batting_strikeouts`.

투수 필수 정수: `batters_faced`, `outs_pitched`, `hits_allowed`, `home_runs_allowed`, `walks_allowed`, `pitcher_strikeouts`. 이닝은 소수 연산 대신 아웃 수를 사용합니다. 피2·3루타는 선택 항목입니다.

| 사건 키 | 타자 관측 건수 | 투수 관측 건수 |
| --- | --- | --- |
| `strikeout` | 타격 삼진 | 투수 탈삼진 |
| `walk` | 볼넷(고의4구 포함, 별도 가산 안 함) | 허용 볼넷 |
| `single` | H−2B−3B−HR | 피안타−피2루타−피3루타−피홈런 |
| `double`, `triple` | 2루타, 3루타 | 피2루타, 피3루타 |
| `home_run` | 홈런 | 피홈런 |
| `other_out` | PA−H−BB−K | BF−피안타−허용볼넷−탈삼진 |

사구·희생타 등은 초기 단순화 규칙에 따라 잔여 사건 `other_out`에 포함합니다. 따라서 이 사건은 실제 야구의 아웃만 집계한 수치가 아닙니다. 게임에서는 1아웃·주자 유지로 처리하며 득점 편향은 5주 차 반복 검증 대상입니다. 타율 H/AB를 타석 안타 확률로 쓰지 않습니다.

## 누락·0분모·소표본 기준

1. 원본의 null·역할 부재·실제 0을 구분하며, 없는 공식 수치를 0으로 채우지 않습니다.
2. 필수 정수의 음수·bool·비정수, H>AB, AB>PA, 음수 단타·잔여 사건 등 불일치는 오류로 생성 중단합니다.
3. 리그 평균은 공식 선수 ID별 시즌 합계를 한 번씩만 합산하고 유효한 양수 PA/BF 기록만 사용합니다. 타율의 단순 평균이 아니라 사건 합계/PA 또는 BF 합계입니다. 리그 표본 자체가 없으면 중단합니다.
4. 역할 통계가 있으나 필수 필드가 누락되면 해당 역할의 전체 확률을 리그 평균으로 대체하고 사유·필드 목록을 기록합니다. PA/BF=0도 같은 방식으로 처리합니다. 원본은 바꾸지 않습니다. 역할 기록 자체가 없는 경우 프로필은 null입니다.
5. **자동 선발 라인업은 필수 누락·0분모·역할 부재 선수를 허용하지 않습니다.** 전체 선수 목록에는 남기되 현재 선택된 선수에 문제가 있으면 데이터 생성을 중단합니다.
6. 유효 표본 n에 대해 사건별 `p=(관측 건수+200×리그 사건 확률)/(n+200)`를 적용합니다. 타자는 PA, 투수는 BF를 n으로 사용합니다. 확률은 부동소수 오차를 정규화하고 원본 성적과 구분합니다.
7. 투수의 피2·3루타 중 하나라도 없으면 둘 다 리그 타격의 비홈런 안타 내 2·3루타 비율로 분배합니다. 추정값은 원본 통계에 기록하지 않습니다.
8. Dart 엔진은 해당 타자·투수의 보정 확률을 사건별 산술평균하고 합계를 다시 정규화합니다. 음수·NaN·무한대·합계 0은 오류입니다. 이 결합과 200 PA/BF는 초기 모델이며 현실 예측 정확성을 보장하지 않습니다.

## 소속·이적·중복 편입 기준

- 선수는 KBO 공식 ID로 시즌 전체에서 한 번만 저장합니다. 공급처 ID 미확정은 이 데이터 생성의 필수 조건이 아닙니다.
- 공식 시즌 표의 팀 분류가 정확히 한 팀이며 참가 팀에 대응할 때만 그 팀에 편입합니다. 시즌 말 실제 등록이나 과거 특정 경기 소속을 주장하지 않습니다.
- 팀 분류가 없거나 복수·미지정이면 `assigned_team_id=null`, `membership_status=unresolved_excluded_from_lineups`로 보관하고 자동 편성에서 제외합니다. 임의로 첫 팀을 선택하지 않습니다.
- `record_scope=season_total_not_team_stint`: 공식 합산 성적을 이전 팀별로 나누거나 각 팀에 중복 복사하지 않습니다. 별도로 저장된 공급처 팀별 구간은 원본·관측 합산에 보존하며 이 공식 합계에 섞지 않습니다.
- 앱 전력 비교·라인업 화면은 `membership_notice`를 표시합니다. 표시 문구: “공식 시즌 표의 팀 분류입니다. 성적은 시즌 전체 합계이며 해당 팀 소속 기간만의 기록이나 현재 등록 명단을 뜻하지 않습니다.” 표시 구현은 3주 차입니다.

## 검증과 완료 범위

생성기는 시즌·원본 해시, 팀 10개, 선수 ID 유일성, 타순 1~9, 포지션 9자리, 선수 참조·소속, 팀 내·팀 간 중복, 선정 선수 필수 통계와 확률 범위를 검사합니다. 보고서의 `fallback_profiles`는 전체 선수 중 평균 대체 내역이며 선정 선수 결함을 뜻하지 않습니다. 실패 시 정상 완료로 표시하지 않습니다.

1주 차 완료는 이 계약과 실제 시즌 JSON·검증 결과가 준비된 상태입니다. Dart 상태 전이·추첨은 2주 차에 구현했습니다. 앱 로딩·캐시·화면 안내, 로컬 복구·채점과 1,000회 반복 검증은 후속 주차에 구현합니다.
