# COMPLIANCE — 정보통신·SaaS (ICT / SaaS) (KSIC J)

> 자동 생성 (wds-scaffold). 근거: domains/ict-saas.yaml. 규제는 변하므로 references 로 재확인.
> MaekNote 는 **서버 없는 온디바이스 앱**(PRD §3)이다. 서버·멀티테넌트 전제 항목은 "해당 없음(N/A)" 으로 표시하고 근거를 남긴다.

## 분류
| 체계 | 코드 |
|---|---|
| KSIC | J (58, 59, 60, 61, 62, 63) |
| ISIC / NACE | J / J |
| NAICS | 51 |

## 한국 규제 (1순위)
| 규제 | 시행 | 영향 | MaekNote 적용 |
|---|---|---|---|
| 정보통신망법 | — | 네트워크·정보보호 의무(§47=ISMS 근거), 침해사고 신고 | 모델 다운로드·클라우드 옵션 통신 구간 TLS, 무결성 검증 |
| 개인정보보호법(PIPA) | — | PII 동의·최소화·유출통지(§32-2) | 녹음·전사에 제3자 발언 포함 가능 → 기본 온디바이스 처리, 클라우드 옵션 ON 시 외부 전송 고지·동의 |
| ISMS-P | — | 대형 ICT 서비스 의무, 접근로그·변경관리·암호화 증적 | 가정: 서버 없는 MVP 는 의무 대상 아님. 서버·동기화 도입 시 재검토 |
| CSAP(클라우드) | 2025 온라인 발급 | 공공/정부 클라우드 판매 시 인증 | N/A (SaaS 미제공). 공공기관 판매 시 재검토 |

## 국제 기준
- SOC 2 Type II (US SaaS, 6~12개월 통제)
- ISO/IEC 27001 (SOC2와 40~85% 통제 중첩)
- GDPR (EU 고객/테넌트) — EU 사용자 배포 시 클라우드 옵션 전송 고지 적용

## 데이터 등급
| 데이터 | 등급 | 비고 |
|---|---|---|
| 테넌트 데이터 | 민감 | N/A — 멀티테넌트 서버 없음 |
| 고객 PII | 민감 | PIPA/GDPR. 녹음·전사·요약을 이 등급으로 취급(제3자 발언 포함) |
| 인증/아이덴티티(RBAC) | 규제대상 | 계정 없음(PRD Out of Scope). 클라우드 API 키를 이 등급으로 취급 → OS 보안 저장소 보관. **local/prod 리허설 포함 비운영 환경에 실데이터 반입 금지** |
| 감사로그/텔레메트리 | 내부 | v0.3 텔레메트리 없음. 외부 전송 기록은 실행 중 메모리에만 보관(설정 > 저장공간·개인정보) |

## 인프라 패턴
- 멀티테넌트 격리(RLS/스키마/DB-per-tenant) — N/A (서버 없음)
- 관측성(OTel 콜렉터→티어드 스토리지) — N/A (v0.3 원격 로그·크래시 리포트 없음)
- 피처플래그, API 게이트웨이, 수평 오토스케일, 시크릿 관리 — 시크릿 관리만 적용(사용자 API 키, 서명 키)
- 표준 CI/CD — 적용
- stack_overrides(Next.js·NestJS·PostgreSQL·Redis) — **선택 스택과 다름**: flutter-app + 온디바이스 SQLite(sqlite3 직접 사용, FTS5). 근거: PRD 상 백엔드 없음. 서버 기능 도입 시 오버라이드 재적용
- 추가(앱 특화): 모델 배포처(CDN/허브) + 모델 manifest SHA256 검증

## 개발환경 특수 요구
- 테넌트 격리 테스트 — N/A
- 표준 CI/CD(lint/type/test/build/deploy) — 적용 (5개 OS 빌드 매트릭스로 확장 필요)
- 텔레메트리 보관/삭제 검증 — 옵트인 통계 도입 시 적용
- OpenAPI 계약 테스트 — N/A (자체 API 없음). 클라우드 제공자 연동은 모의(mock) 계약 테스트로 대체
- SOC2/ISO 통제 증적 자동화 — 기업 판매 시 재검토

## 추가 시험
| 시험 | 위치 | 적용 |
|---|---|---|
| 크로스테넌트 데이터 누출 차단(RLS) | — | N/A |
| OpenAPI 계약 적합성 | test/impl | 클라우드 제공자 mock 계약으로 대체 |
| 감사로그 보관기간 경과 삭제 증명 | test/impl | 옵트인 통계 도입 시 |
| 클라우드 OFF 시 오디오·텍스트 외부 전송 0건 (PRD AC6) | test/impl/4th·6th·7th·8th | PASS (전송 관문 기록 0건) |
| 모델 파일 해시 위변조 차단 | test/impl/3rd | PASS |

## 구현 상태 (2026-11-02)
- 클라우드 요약 사용 시 동의 대화상자로 외부 전송·제3자 개인정보 포함 가능성 고지 (설정 > 클라우드).
- API 키: OS 보안 저장소에만 저장, settings DB 미기록 (test/impl/7th E7-09).
- 클라우드 전송은 단일 관문(`GuardedClient`)을 거치며, 옵션 OFF 시 요청 자체를 차단.
- 확인 필요: AI 기본법(생성형 AI 결과물 표시) 적용 여부 — 도메인 데이터에 없는 항목, 요약 결과에 "AI 생성" 표기 검토.

## 출처
- https://isms-p.or.kr/sysm/intro/selectSysmCertDetail.do (ISMS-P)
- https://isms.kisa.or.kr/main/csap/notice/ (CSAP 2025)
- https://secureframe.com/blog/soc-2-vs-iso-27001
- https://oneuptime.com/blog/post/2026-02-06-telemetry-retention-soc2-iso27001/view
- https://www.ideadope.com/roadmaps/how-to-build-multi-tenant-saas-2025
