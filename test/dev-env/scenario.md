# dev-env 시나리오 / scenario — maeknote (flutter-app)

| id | 목적 / purpose | 명령 / command | 기대 / expected | 우선 |
|----|----------------|----------------|-----------------|------|
| ENV-01 | 툴체인 | `make preflight` | 필수 SDK 확인 | P0 |
| ENV-02 | 의존성 | `make setup` | 성공 | P0 |
| ENV-03 | local 플레이버 실행 | `make local-all` | 시뮬레이터/에뮬레이터에 앱 표시 | P0 |
| ENV-04 | 테스트 | `make test` | exit 0 | P0 |
| ENV-05 | prod 플레이버 빌드 | `make prod-build` | 미서명 릴리스 빌드 성공 | P1 |
