# 1st — Epic 1 기반 (셸·DB·테마·데스크톱 타깃·CI)

| id | 목적 | 입력 | 기대 | 우선 |
|----|------|------|------|------|
| E1-01 | 스키마 마이그레이션 | 빈 DB 열기 | user_version = 최신, 9개 테이블 존재 | P0 |
| E1-02 | FTS5 전문검색 | 세그먼트 insert/delete | trigram MATCH 1건 → 삭제 후 0건 | P0 |
| E1-03 | 설정 기본값·저장 | cloud.enabled | 기본 false, set 후 재조회 true | P0 |
| E1-04 | 아이콘 탭 전환 (좁은 화면) | 라이브러리→노트→모델 탭 | 본문 교체 | P0 |
| E1-05 | EQ/출력 토글 | 제어줄 토글 | 본문이 패널로 대체, 재토글 시 복귀 | P0 |
| E1-06 | 넓은 화면 확장 패널 | 1200px | 노트 패널 우측 동시 표시, 노트 탭 숨김 | P1 |
| E1-07 | 데스크톱 빌드·기동 | `flutter build macos` + 실행 8초 | 빌드 성공, 프로세스 유지, maeknote.db 생성 | P0 |
| E1-08 | Make 타깃 | `make help` | macos/windows/linux/prod-build-desktop 표시 | P1 |
