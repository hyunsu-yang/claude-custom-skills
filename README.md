# Claude Custom Skills

Claude Code에서 사용하는 커스텀 스킬 모음.

## 구조

```
commands/              # ~/.claude/commands/ 에 설치 (슬래시 커맨드)
  arch-doc.md
  c4.md
skills/
  global/              # ~/.claude/skills/ 에 설치 (모든 프로젝트에서 사용)
    architecture-refactor/
    c4-model/
    yt-subtitle/
  tradingapp/          # 프로젝트 .claude/skills/ 에 설치 (해당 프로젝트에서만 사용)
    strategy-backtest/
    strategy-backtest-v2/
    strategy-docs/
    strategy-improvement/
    strategy-improvement-v2/
    system-check/
  stockapp/            # stockapp 프로젝트 전용
    strategy-backtest/
    strategy-improvement/
    system-check/
```

## 설치

```bash
# 전체 설치 (글로벌 스킬 + 커맨드)
bash install.sh

# 글로벌 스킬 + 커맨드
bash install.sh --global

# 슬래시 커맨드만
bash install.sh --commands

# 특정 프로젝트 스킬만
bash install.sh --project tradingapp /path/to/tradingapp
```

## 슬래시 커맨드

| 커맨드 | 설명 |
|--------|------|
| `/arch-doc` | 코드베이스 → 아키텍처 문서 (C4 + Mermaid). `c4-model` 스킬 진입점 |
| `/c4` | `/arch-doc` 별칭 — 기억나는 이름 아무거나 |

`~/.claude/commands/`에 이 레포가 관리하지 않는 실물 파일이 있으면 덮어쓰지 않고
경고 후 건너뛴다. 레포 관리로 편입하려면 `commands/`로 옮기고 재실행.

## 스킬 목록

### Global

| 스킬 | 설명 |
|------|------|
| `architecture-refactor` | 크로스 모듈 중복 탐지 + 단계별 리팩토링 (Scan → Report → Plan → Execute → Verify) |
| `c4-model` | 코드베이스/산문 → C4 아키텍처 문서 (Mermaid·Structurizr·PlantUML). 5개 모드 — 신규 설계 / 기존 레포 역문서화 / 리뷰 / 갱신. **외부 유래** → [PROVENANCE.md](skills/global/c4-model/PROVENANCE.md) |
| `yt-subtitle` | YouTube URL에서 자막 추출 및 요약 (`yt-dlp` 필요) |

### TradingApp

| 스킬 | 설명 |
|------|------|
| `strategy-backtest` | V1 백테스트 실행 가이드 |
| `strategy-backtest-v2` | V2/V3/V4 백테스트 실행 가이드 |
| `strategy-docs` | 전략 문서 라이프사이클 관리 |
| `strategy-improvement` | V1 데이터 기반 전략 개선 워크플로우 |
| `strategy-improvement-v2` | V2/V3/V4 전략 개선 워크플로우 |
| `system-check` | 자동매매 시스템 전체 상태 점검 |

### StockApp (한국 주식 자동매매)

| 스킬 | 설명 |
|------|------|
| `strategy-backtest` | eBest t8412 과거 5분봉 수집 + 조건별 진입 시뮬레이션 |
| `strategy-improvement` | 로그 분석 → 백테스트 → 파라미터 조정 → 적용 워크플로우 |
| `system-check` | 서버·세션·사이클·포지션·에러 종합 진단 리포트 |
