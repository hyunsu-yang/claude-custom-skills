# Claude Custom Skills Repo

## Project Structure

```
skills/
  global/       → installed to ~/.claude/skills/ (all projects)
  tradingapp/   → installed to <project>/.claude/skills/ (project-specific)
  stockapp/     → installed to <project>/.claude/skills/ (project-specific)
```

## Install

```bash
bash install.sh                                      # 글로벌 스킬만 설치
bash install.sh --global                             # 위와 동일 (명시적 플래그)
bash install.sh --project tradingapp /path/to/proj  # 프로젝트 스킬 심볼릭 링크 설치
```

## 현재 스킬 목록

| 스코프 | 스킬 | 설명 |
|--------|------|------|
| global | `architecture-refactor` | 크로스 모듈 중복 탐지 + 단계별 리팩토링 |
| global | `c4-model` | 코드베이스 → C4 아키텍처 문서 (Mermaid). **외부 유래 (vendored)** |
| global | `yt-subtitle` | YouTube URL에서 자막 추출 및 요약 |
| tradingapp | `strategy-backtest` | V1 백테스트 실행 가이드 |
| tradingapp | `strategy-backtest-v2` | V2/V3/V4 백테스트 실행 가이드 |
| tradingapp | `strategy-docs` | 전략 문서 라이프사이클 관리 |
| tradingapp | `strategy-improvement` | V1 데이터 기반 전략 개선 워크플로우 |
| tradingapp | `strategy-improvement-v2` | V2/V3/V4 전략 개선 워크플로우 |
| tradingapp | `system-check` | 자동매매 시스템 전체 상태 점검 (V1/V2/V3 자동 감지) |

## Skill Authoring

- 각 스킬은 `skills/<scope>/<name>/SKILL.md` 폴더에 위치
- 필수 frontmatter: `name` (폴더명과 일치) + `description` (트리거 문구 포함)
- `disable-model-invocation: true` — 사용자 전용 호출 (부작용이 있는 스킬)
- `user-invocable: false` — Claude 전용 백그라운드 지식
- 스킬 추가 후 README.md 테이블 업데이트
- 새 프로젝트 스코프 추가 시: `skills/<scope>/` 폴더 생성

## Install Mechanism

`install.sh`는 복사가 아닌 심볼릭 링크 생성 — 설치된 경로가 아닌 `skills/` 소스 직접 편집

## 외부 스킬 vendoring 규칙

외부 레포 스킬을 쓸 때는 `/plugin install`(marketplace) 대신 이 레포로 **vendoring**한다.
marketplace는 검토 없는 자동 업데이트 경로를 열지만, vendoring하면 감사한 커밋에 고정되고
커스터마이징도 자유롭다.

절차:

1. **먼저 감사** — 클론해서 `SKILL.md`/참조 파일을 실제로 읽는다. 확인 항목:
   네트워크 호출(`curl`/`wget`/`fetch`), 훅 선언(`preToolUse`/`postToolUse`),
   MCP 서버 정의, 비밀정보 접근(`.env`/credential), 난독화(`base64`/`eval`/`exec`),
   `.md` 아닌 실행 파일. 하나라도 걸리면 이유를 납득할 때까지 설치하지 않는다.
2. `skills/<scope>/<name>/`에 필요한 부분만 복사 (플러그인 전용 `commands/`, `tests/`는 보통 제외)
   - **라이선스 전문을 `LICENSE.upstream`으로 함께 복사** — MIT/Apache 등 대부분이
     재배포 시 저작권 표시 + 라이선스 전문 포함을 요구하고, 이 레포는 공개 레포라
     재배포에 해당한다. 서브디렉토리만 복사하면 루트 LICENSE가 빠지니 주의.
3. **`PROVENANCE.md` 필수** — 출처 URL, 고정 커밋 SHA, 라이선스, vendor 일시,
   가져온/제외한 범위, 감사 결과, 업스트림 diff 명령
4. `bash install.sh --global` 로 심볼릭 링크
5. README + 위 스킬 목록 테이블에 **외부 유래** 표시

로컬 수정 시 `PROVENANCE.md`의 "## 로컬 수정"에 기록 — 업스트림 대비 diff 기준점 유지.
업스트림 갱신은 diff를 직접 읽고 판단해서 반영하며, 자동 pull 하지 않는다.

현재 vendored: `c4-model` ([PROVENANCE](skills/global/c4-model/PROVENANCE.md))

## 사용법

Claude Code 세션에서 `/<skill-name>` 으로 호출 (예: `/system-check`, `/architecture-refactor`)
