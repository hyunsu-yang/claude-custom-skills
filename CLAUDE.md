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

## 사용법

Claude Code 세션에서 `/<skill-name>` 으로 호출 (예: `/system-check`, `/architecture-refactor`)
