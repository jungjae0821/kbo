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

## 데이터와 글꼴

- `assets/data/season_dataset.json`은 `kbo_data/kbo_2026_138278/app/season_dataset.json`의 복사본입니다. 시즌 데이터를 다시 생성했다면 이 파일도 덮어써야 합니다.
- 앱 시작 시 이 JSON을 읽고 엔진의 `SeasonDataset.fromJson` 계약 검사를 통과해야 경기를 시작할 수 있습니다. 실패하면 홈에서 원인과 "다시 불러오기"를 보여줍니다. 원격 갱신·기기 캐시는 아직 없습니다(`DataController._readSource`만 바꾸면 붙일 수 있음).
- 글꼴은 경기도청 공식 배포본 경기천년체(`경기천년체_260917.zip`)의 TTF입니다. 바탕체 두 파일이 각 11~12MB라 APK가 커집니다.

## 지금 범위와 남은 일

- 예측 확정·채점(적중 +100, 무승부 0점·적중률 제외·연속 유지, 경기 ID당 1회)은 동작하지만 앱이 켜져 있는 동안만 보관합니다. 기기 내 JSON 저장과 중단 경기 복구는 4주 차입니다.
- 경기 seed는 예측 확정 시 무작위로 정하고, 결과 화면에 "경기 번호"로 표시합니다.
