---
name: strategy-backtest-v2
description: V2/V3/V4 engine backtest execution guide using simulate-v2.mjs. Use when the user asks to run V2/V3/V4 backtest, compare strategies, or mentions "V2 백테스트", "V3 백테스트", "V4 백테스트", "simulate-v2". For V1 (adaptive engine with presets), use the strategy-backtest skill instead.
---

# V2/V3 Engine Backtest Guide

V2/V3 엔진 전용 백테스트 가이드. V1(`simulate.mjs` + presets)과 완전히 분리된 체계.

> **V3 호환성**: V3 엔진은 V2의 entry.js, exit.js, indicators.js를 그대로 재사용합니다.
> `simulate-v2.mjs` 백테스트는 V3의 핵심 전략 로직을 검증하는 데 유효합니다.
> V3 고유 기능(실시간 Exit Monitor, Order Flow, 캔들 경계 평가)은 백테스트에서 시뮬레이션되지 않으나,
> 진입/매도 전략 파라미터 튜닝은 V2 백테스트로 충분합니다.
>
> **V4 ML Pipeline**: V4에서 추가된 Flow Alpha(flowAlpha.js), Feature Snapshot(featureSnapshot.js),
> Triple Barrier(tripleBarrier.js)는 실시간 체결 스트림 기반이므로 백테스트에서 시뮬레이션되지 않습니다.
> 백테스트는 진입/매도 전략 파라미터 검증에 집중하며, ML 학습 데이터는 실거래에서 자동 축적됩니다.

## V2 vs V1 백테스트 핵심 차이

| | V1 (simulate.mjs) | V2 (simulate-v2.mjs) |
|--|---|---|
| 전략 선택 | 프리셋별 파라미터 셋 | auto: condition → 전략 라우팅 |
| 레짐 | 종목별 5-state | Global BTC 4h + Per-symbol condition |
| 비교 모드 | `--compare` (7개 프리셋) | `--compare` (4전략: auto/MR/TF/MB) |
| 캔들 단위 | `--candle 3` (기본 3분) | `--candle 5` (기본 5분) |
| 매도 | riskManager (SL/TP/trailing/early cut) | 전략별 전용 exit + ATR SL |
| BTC 레짐 | 없음 | BTC 4h 캔들 이진 탐색 정렬 |
| 필터 | volatility, no-trade-zone | downtrend filter, falling knife guard, global gate, filter profiles (v9.3) |

---

## 1. 단일 종목 백테스트

### 1-1. 실행

```bash
# auto 모드 (기본) — condition 기반 전략 라우팅
node scripts/simulate-v2.mjs --market KRW-BTC --from "2026-04-07 00:00" --to "2026-04-09 17:00" --candle 5

# 고정 전략
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --strategy meanReversion
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --strategy trendFollowing

# 상세 로그
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --verbose
```

### 1-2. CLI 파라미터

```
--market KRW-BTC              단일 종목 (필수, --markets 대체)
--markets KRW-BTC,KRW-ETH     다중 종목
--from "2026-04-07 00:00"     시작시간 KST (필수)
--to "2026-04-09 17:00"       종료시간 KST (기본: now)
--candle 5                    종목 캔들 단위 (기본: 5)
--btc-candle 240              BTC 글로벌 레짐 캔들 단위 (기본: 240 = 4시간)
--strategy auto               auto|meanReversion|trendFollowing|momentumBreakout (기본: auto)
--compare                     4전략 비교 테이블
--verbose                     틱별 상세 로그
--save-baseline <name>        결과 JSON 저장
--compare-baseline <name>     저장된 baseline과 비교
--cooldown 600000             쿨다운 ms (기본: 600000)
--fee 0.0005                  수수료율 (기본: 0.05%)
--amount 50000                가상 포지션 KRW (기본: 50000)
--bb-threshold 5              MR BB 진입 임계값
--rsi-threshold 35            MR RSI 진입 임계값
--no-cache                    캐시 비활성화
```

### 1-3. Upbit API 제한

- 5분봉: 약 3일치가 최대 (200개 × batch)
- `--from`/`--to` 기간이 길면 배치 fetch 자동 분할
- BTC 4h 캔들: 80개 = 약 13.3일

---

## 2. 출력 포맷

### 2-1. 단일 실행 결과

```
═══ V2 Backtest: KRW-BTC [auto] ═══
Period: 2026-04-07 00:00 ~ 2026-04-09 17:00 (5min candles)
BTC Regime: 240min candles, cooldown: 10min

--- Round Trips ---
  #1 [WIN ] 04-07 09:15 → 04-07 10:30 | MR  | ranging  | neutral | +0.45% (+225) | 15 bars
  #2 [LOSS] 04-07 11:00 → 04-07 11:20 | TF  | trend_up | bull    | -0.68% (-340) | 4 bars

--- Performance ---
  Trades: 12 (Win: 8, Loss: 4)  WinRate: 66.7%
  PnL: +1,250 KRW  Expectancy: +104 KRW/trade
  MaxDD: -850 KRW  Fees: 600 KRW  AvgHold: 8.3 bars

--- Strategy Breakdown (auto) ---
  Strategy        | Trades | WinRate | PnL(KRW) | E[x]
  MeanReversion   |      5 |   60.0% |     +450 |  +90
  TrendFollowing  |      4 |   75.0% |     +650 | +163
  MomentumBrkout  |      3 |   66.7% |     +150 |  +50

--- Filter Profile Breakdown ---
  Profile         | Trades | WinRate | PnL(KRW) | E[x]
  tf_moderate     |      3 |   66.7% |     +400 | +133
  tf_strong       |      1 |  100.0% |     +250 | +250
  mr_standard     |      4 |   50.0% |     +100 |  +25
  mr_deep         |      2 |  100.0% |     +350 | +175
  mr_uptrend      |      2 |   50.0% |     +150 |  +75

--- Skipped Ticks Breakdown ---
  cooldown: 45 | globalGate: 12 | trendingDown: 30 | downtrend: 8 | fallingKnife: 3
```

### 2-2. Compare 모드 (`--compare`)

```
--- V2 Strategy Comparison: KRW-BTC ---
  Strategy          | Trades | WinRate | PnL(KRW) | E[x]  | AvgHold | MaxDD
  auto              |     12 |   66.7% |   +1,250 |  +104 |     8.3 |  -850
  meanReversion     |      8 |   50.0% |     +300 |   +38 |     6.1 | -1,200
  trendFollowing    |      6 |   83.3% |   +1,100 |  +183 |    12.5 |  -300
  momentumBreakout  |      2 |   50.0% |     -100 |   -50 |     4.0 |  -500
  * Best: trendFollowing (PnL +1,100, WR 83.3%)
```

### 2-3. Multi-Market (`--markets`)

```
--- Multi-Market Summary [auto] ---
  Market   | Trades | WinRate | PnL(KRW)
  KRW-BTC  |     12 |   66.7% |   +1,250
  KRW-ETH  |      8 |   50.0% |     -200
  TOTAL    |     20 |   60.0% |   +1,050
```

---

## 3. 결과 해석 가이드

### 3-1. Strategy Breakdown 분석

auto 모드의 Strategy Breakdown에서:

| 패턴 | 의미 | 조치 |
|------|------|------|
| MR 높은 WR + 높은 PnL | MR 조건이 잘 맞는 시장 | 유지 |
| TF 낮은 WR + 많은 거래 | 약한 추세에 과진입 | emaGapThreshold 상향 |
| TF 높은 WR + 적은 거래 | 필터가 정확 | 유지 |
| MB 0 거래 | 돌파 조건 미충족 | 정상 (MB는 드물게 발생) |
| auto > 개별 최고 전략 | 라우팅이 정확 | 이상적 상태 |
| auto < 개별 최고 전략 | 라우팅 오류 가능 | condition 탐지 검토 |

### 3-1-1. Filter Profile Breakdown 분석 (v9.3)

auto 모드의 Filter Profile Breakdown에서 프로파일별 성과를 분석:

| 패턴 | 의미 | 조치 |
|------|------|------|
| mr_deep 높은 WR | 극과매도 진입이 효과적 | 유지 — BB<5 필터 완화가 정확 |
| mr_deep 낮은 WR | 과매도 반등 실패 多 | bbThreshold 더 낮추기 (3 이하) |
| mr_uptrend 높은 WR | 상승 풀백 진입이 효과적 | BB 임계값 확대 검토 (45→50) |
| mr_uptrend 낮은 WR | 풀백이 반등 아닌 추세 전환 | BB 임계값 축소 (45→35) |
| tf_strong 0 거래 | ADX>35 구간 없음 | 정상 (강한 추세는 드물게 발생) |
| tf_volume 높은 WR | 거래량 기반 추세 확인이 정확 | RVOL 임계값 유지 (2.0) |
| tf_moderate 낮은 WR | 기본 TF 필터로 부족 | emaGap/ADX 임계값 상향 검토 |
| 특정 프로파일만 거래 | 시장이 단일 상태 고정 | 기간 내 시장 상황 확인 |

### 3-2. Skipped Ticks 분석

| Skip 사유 | 높을 때 의미 | 조치 |
|-----------|-------------|------|
| cooldown 높음 | 빈번한 매매 후 대기 | 정상 (과매매 방지) |
| globalGate 높음 | BTC 약세 구간 多 | gate 조건 검토 |
| trendingDown 높음 | 하락 추세 종목 多 | 기간 내 시장 상황 확인 |
| downtrend 높음 | downtrend filter 활발 | 과차단 여부 verbose로 확인 |
| fallingKnife 높음 | ranging 내 하향 편향 多 | 정상 (falling knife 보호) |

### 3-3. 핵심 지표 해석

| 지표 | 좋은 값 | 나쁜 신호 |
|------|---------|----------|
| WR (승률) | > 50% | < 40% → 진입 조건 검토 |
| E[x] (기대값) | > 0 | < 0 → 전략 전체 문제 |
| AvgHold | 5-20 bars | < 3 → 너무 빨리 퇴장 (SL 문제) |
| MaxDD | < amount의 30% | > 50% → 리스크 관리 검토 |

---

## 4. Baseline A/B 비교

### 4-1. 변경 전 저장

```bash
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --save-baseline v6.0.1-pre
```

저장 경로: `scripts/baselines/v2_v6.0.1-pre.json`

### 4-2. 변경 후 비교

```bash
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --compare-baseline v6.0.1-pre
```

### 4-3. 비교 출력

```
═══ Baseline Comparison: v6.0.1-pre ═══
              | Baseline     | Current      | Delta
  Trades      |           12 |           10 | -2
  WinRate     |        50.0% |        60.0% | +10.0%p
  PnL(KRW)    |         +300 |         +800 | +500
  Expectancy  |          +25 |          +80 | +55
  MaxDD       |         -850 |         -500 | +350 (개선)
```

---

## 5. Live vs Backtest 구조적 차이

### 5-1. V2/V3 엔진 특유의 차이

| 항목 | V2 실거래 | V3 실거래 | 백테스트 (simulate-v2.mjs) |
|------|----------|----------|--------------------------|
| BTC 레짐 | 매 틱(10초) 4h API 조회 | 캔들 마감 시 조회 | 4h 완성 캔들 이진 탐색 |
| 종목 캔들 | 실시간 API (미완성 포함) | Trade WS로 실시간 빌드 | 완성된 5분봉만 사용 |
| 손절 반응 | 10초 폴링 | **매 틱 실시간** (<1초) | 캔들 마감 시 |
| 트레일링 스탑 | 10초마다 갱신 | **매 틱마다 고점 추적** | 캔들 마감 시 |
| 주문 흐름 | 없음 | **매수세/매도세 분석** | 없음 |
| Flow Alpha | 없음 | **TFI/VWAP/Accel 연속 시그널** | 없음 |
| Feature Snapshot | 없음 | **진입 시 25+ 피처 자동 기록** | 없음 |
| Triple Barrier 라벨링 | 없음 | **매도 시 ATR 기반 자동 라벨링** | 없음 |
| Surge 감지 | surgeDetector 연동 | surgeDetector 연동 | Surge bypass 없음 |
| 쿨다운 | 실시간 밀리초 기반 | 실시간 밀리초 기반 | 틱 UTC 밀리초 기반 |
| 포지션 관리 | position/index.js | position/index.js | 로컬 변수 |
| 24h 변화율 | ticker API | ticker API | 캔들 기반 계산 |

> **V3 백테스트 갭**: V3의 실시간 Exit Monitor(틱 레벨 스탑)와 Order Flow(매수세 차단/부스트)는
> 백테스트에서 시뮬레이션되지 않습니다. 실거래에서는 V3가 V2보다 더 빠르게 손절하고,
> 매도세 우위 시 진입을 차단하므로 실거래 성과가 백테스트보다 개선될 수 있습니다.

### 5-2. 백테스트 신뢰도

| 비교 방법 | 유효성 | 이유 |
|-----------|--------|------|
| 백테스트 PnL vs 실거래 PnL (절대값) | **무효** | 구조적 차이로 조건 불동 |
| 백테스트(before) vs 백테스트(after) | **유효** | 동일 시뮬레이터, 상대 비교 |
| 실거래(before) vs 실거래(after) | **가장 정확** | 동일 엔진, 실시간 데이터 |

**핵심:** 백테스트는 relative comparison (before vs after)에 신뢰성 높음, absolute PnL은 실거래와 차이 있음.

### 5-3. 실거래 데이터로 직접 검증

```bash
# V2 진입 시그널 로그
grep 'ENGINE-V2.*Entry signal' backend/logs/auto-YYYYMMDD.log

# V3 진입 시그널 로그
grep 'ENGINE-V3.*Entry signal' backend/logs/auto-YYYYMMDD.log

# V2/V3 글로벌 레짐
grep 'global regime\|globalRegime' backend/logs/auto-YYYYMMDD.log

# V2/V3 condition skip
grep 'condition=trending_down' backend/logs/auto-YYYYMMDD.log

# V2/V3 downtrend blocks
grep 'blocked by downtrend filter' backend/logs/auto-YYYYMMDD.log

# V2/V3 falling knife
grep 'falling knife guard' backend/logs/auto-YYYYMMDD.log

# V3 전용: Exit Monitor (실시간 스탑)
grep 'EXIT-MONITOR' backend/logs/auto-YYYYMMDD.log

# V3 전용: Order Flow (매수세/매도세)
grep 'ORDER-FLOW' backend/logs/auto-YYYYMMDD.log

# V3 전용: Trade WebSocket
grep 'WS-TRADE' backend/logs/auto-YYYYMMDD.log

# V4 전용: Flow Alpha 부스트
grep 'alpha boost' backend/logs/auto-YYYYMMDD.log

# V4 전용: Feature Snapshot 라벨링
grep 'FEATURE-SNAPSHOT' backend/logs/auto-YYYYMMDD.log

# V4: ML 학습 데이터 축적 현황
node -e "const fs=require('fs'); const files=fs.readdirSync('backend/data').filter(f=>f.startsWith('feature-snapshots-')); let total=0; files.forEach(f=>{const d=JSON.parse(fs.readFileSync('backend/data/'+f));total+=d.length}); console.log('Total snapshots:',total,'files:',files.length)"

# V4: 과거 데이터 백필 (trade-history → feature-snapshots)
node scripts/backfill-snapshots.mjs --dry-run

# 거래 내역 분석
cat backend/data/trade-history-YYYYMMDD.json | node -e "
  const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  const trades = data.filter(t => t.meta?.engine === 'v2' || t.meta?.engine === 'v3');
  // strategy/condition/globalRegime/exitReason별 그룹핑
"
```

---

## 6. Period Consistency Rule

**모든 백테스트는 동일한 `--from`, `--to` 사용 필수.**

- 기간을 처음 한 번 결정 → 전체 세션에서 재사용
- 실거래 비교 시 `trade-history-YYYYMMDD.json`의 실제 거래 타임스탬프를 커버해야 함
- Before/After 비교 (`--save-baseline` / `--compare-baseline`)는 반드시 동일 기간
- Upbit API 제한: 5분봉 기준 약 3일치가 최대

---

## 7. 파라미터 오버라이드 예시

```bash
# MR 파라미터 튜닝
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --bb-threshold 10 --rsi-threshold 30

# 쿨다운 조정
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --cooldown 300000

# 가상 포지션 금액 변경
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --amount 100000

# 고정 전략으로 파라미터 테스트
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --strategy meanReversion --bb-threshold 3
```
