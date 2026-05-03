# Claude Custom Skills

Claude Code에서 사용하는 커스텀 스킬 모음.

## 구조

```
skills/
  global/              # ~/.claude/skills/ 에 설치 (모든 프로젝트에서 사용)
    architecture-refactor/
    yt-subtitle/
  tradingapp/          # 프로젝트 .claude/skills/ 에 설치 (해당 프로젝트에서만 사용)
    strategy-backtest/
    strategy-backtest-v2/
    strategy-docs/
    strategy-improvement/
    strategy-improvement-v2/
    system-check/
```

## 설치

```bash
# 전체 설치
bash install.sh

# 글로벌 스킬만
bash install.sh --global

# 특정 프로젝트 스킬만
bash install.sh --project tradingapp /path/to/tradingapp
```

## 스킬 목록

### Global

| 스킬 | 설명 |
|------|------|
| `architecture-refactor` | 크로스 모듈 중복 탐지 + 단계별 리팩토링 (Scan → Report → Plan → Execute → Verify) |
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
