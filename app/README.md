# KBO 가상야구 Flutter 앱 (3주 차)

`dart_engine/`을 path 의존성으로 연결한 Flutter Android 앱입니다. 화면 6개(홈, 팀 선택, 전력 비교·예측, 경기 진행, 경기 결과, 개인 기록)와 흐름을 구현했습니다. 디자인 기준은 저장소 루트의 `DESIGN.md`입니다.

## 실행

```powershell
cd app
flutter pub get
flutter run            # 연결된 Android 기기 또는 에뮬레이터
flutter run -d chrome  # 화면 확인용
flutter test
```

`flutter analyze`는 경로에 한글이 있으면 분석 서버가 비정상 종료됩니다(Flutter 3.47.9, Windows에서 확인). 영문 경로의 연결 폴더에서 실행하세요.

```powershell
New-Item -ItemType Junction -Path C:\dev\kbo -Target "<이 저장소 경로>"
cd C:\dev\kbo\app; flutter analyze
```

웹 빌드(`flutter build web`)는 연결 폴더가 아니라 원래 경로에서 하세요. 연결 폴더에서 빌드하면 `build/web/assets`에 `FontManifest.json`과 글꼴 파일이 빠져 경기천년체가 적용되지 않습니다(2026-11-19 확인). 이미 그렇게 됐으면 원래 경로에서 `flutter clean` 후 다시 빌드합니다.

## 데이터와 글꼴

- `assets/data/season_dataset.json`은 `kbo_data/kbo_2026_138278/app/season_dataset.json`의 복사본입니다. 시즌 데이터를 다시 생성했다면 이 파일도 덮어써야 합니다.
- 앱 시작 시 엔진의 `SeasonDataset.fromJson` 계약과 2026 시즌·10개 팀 검사를 통과해야 경기를 시작할 수 있습니다. 실패하면 홈의 기존 안내 영역에서 원인과 "다시 불러오기"를 보여줍니다.
- 원격 주소가 있으면 HTTPS JSON → 검증된 기기 캐시 → 포함된 JSON 순서로 읽습니다. 원격 요청은 10초 후 시간 초과 처리하며, HTTP 오류·잘못된 JSON·다른 시즌·규칙 불일치는 캐시를 덮어쓰지 않습니다. 데이터는 UTF-8로 읽습니다.
- 검증된 JSON은 `SharedPreferencesAsync`로 기기에 보관합니다(웹은 해당 브라우저 저장소). 캐시 키는 시즌·규칙·원격 주소별로 분리합니다. 캐시가 손상되거나 저장소 접근이 실패해도 포함된 JSON으로 실행할 수 있습니다. 개인 기록·중단 경기 저장과는 별개입니다.
- 원격 실패 후 캐시·포함된 기록으로 시작하면 홈의 기존 새 경기 안내 안에서 사용 중인 기록과 재시도 버튼을 표시합니다. 정상 로딩 시 기존 홈 구성을 유지합니다. 선수 소속·시즌 합계의 의미는 기존 전력 비교 하단 안내에 표시합니다. 디자인 토큰·배치·공용 컴포넌트는 변경하지 않았습니다.
- 글꼴은 경기도청 공식 배포본 경기천년체(`경기천년체_260917.zip`)의 TTF입니다. 바탕체 두 파일이 각 11~12MB라 APK가 커집니다.

## 지금 범위와 남은 일

- 예측 확정·채점(적중 +100, 무승부 0점·적중률 제외·연속 유지, 경기 ID당 1회)은 동작하지만 앱이 켜져 있는 동안만 보관합니다. 기기 내 JSON 저장과 중단 경기 복구는 4주 차입니다.
- 경기 seed는 예측 확정 시 무작위로 정하고, 결과 화면에 "경기 번호"로 표시합니다.

## 원격 데이터 설정

주소를 지정하지 않으면 앱에 포함된 2026 시즌 데이터와 기기 캐시로 동작합니다. 실제 시즌 JSON을 제공하는 HTTPS 주소를 확보한 경우 다음처럼 지정합니다.

```powershell
flutter run --dart-define=KBO_DATA_URL=https://your-host.example/season_dataset.json
flutter build web --dart-define=KBO_DATA_URL=https://your-host.example/season_dataset.json
```

위 주소는 예시이므로 실제 호스트로 바꿉니다. 제공 파일은 `assets/data/season_dataset.json`과 같은 계약이어야 하며 웹에서는 앱 출처에 대한 CORS 허용이 필요합니다. 인증 키를 URL이나 앱에 넣지 않습니다. Android 릴리스 manifest에 인터넷 권한을 선언했습니다. 실제 호스팅·재배포 조건 확인은 최종 배포 작업이며 이번에 원격 데이터 서버를 게시하지 않았습니다.

## 3주 차 검증 (2026-11-19)

- `flutter test`: 18개 통과. 원격 다운로드·캐시 저장, 새 컨트롤러의 오프라인 복원, 잘못된 원격 데이터의 캐시 보호, 손상 캐시·HTTP 오류·시간 초과 시 번들 대체, 저장소 오류, 재시도 복구와 중복 요청 방지, 화면의 시작 제한·재시도 및 전체 경기 흐름을 검사합니다. 대체 데이터 안내의 360·768·1280 폭과 밝은·어두운 테마에서 레이아웃 오류가 없는지도 위젯 테스트로 검사합니다.
- `flutter analyze`: 지적 없음. `flutter build web`: 성공(Wasm dry run 포함).
- 엔진 v2.0.0: 38개 검사 통과. `outputs/engine_2_0_0_validation_report.json` 참조.
- 테스트에서 원격 장애는 HTTP 모의 응답으로 재현합니다. 실제 운영 호스트·Android 기기의 통신 및 저장 동작은 별도 배포·기기 검증 대상입니다.
