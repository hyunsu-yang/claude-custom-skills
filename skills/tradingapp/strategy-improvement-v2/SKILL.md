---
name: strategy-improvement-v2
description: V2/V3/V4 engine strategy improvement workflow using simulate-v2.mjs. Use when the user asks to improve V2/V3/V4 strategy, tune parameters, or mentions "V2 전략 개선", "V3 전략 개선", "V4 전략 개선", "V2 파라미터 튜닝", "V2 백테스트". For V1 (adaptive engine with presets), use the strategy-improvement skill instead.
---

# V2/V3 Engine Strategy Improvement Workflow

V2/V3 엔진 전용 전략 개선 워크플로. V1(adaptive engine + presets)과 완전히 분리된 체계.

> **V3 호환성**: V3 엔진은 V2의 entry.js, exit.js, indicators.js를 그대로 재사용합니다.
> `simulate-v2.mjs` 백테스트는 V3의 핵심 전략 로직을 검증하는 데 유효합니다.
> V3 고유 기능(실시간 Exit Monitor, Order Flow, 캔들 경계 평가)은 백테스트에서 시뮬레이션되지 않으나,
> 진입/매도 전략 파라미터 튜닝은 V2 백테스트로 충분합니다.
>
> **V4 ML Pipeline**: V4는 V3에 Flow Alpha 시그널 + Feature Snapshot + Triple Barrier 라벨링을 추가합니다.
> Flow Alpha(flowAlpha.js)는 실시간 체결 스트림 기반이므로 백테스트에서 시뮬레이션되지 않습니다.
> Feature Snapshot은 진입 시 자동 기록되며, 매도 시 tripleBarrier로 라벨링됩니다.
> ML 학습 데이터 축적 상태: `ls backend/data/feature-snapshots-*.json | wc -l`

## V2 vs V1 핵심 차이

| | V1 (simulate.mjs) | V2 (simulate-v2.mjs) |
|--|---|---|
| 전략 선택 | 프리셋별 파라미터 셋 (scalping, dayTrading 등) | auto 모드: 종목별 condition → 전략 라우팅 |
| 레짐 | 종목별 5-state (strong_trend_up 등) | 2-tier: Global BTC regime + Per-symbol condition |
| 진입 전략 | adaptive (단일 통합) | MR, TF, MB 3종 독립 |
| 매도 전략 | riskManager (SL/TP/trailing/early cut) | 전략별 전용 exit (ATR SL + MR BB/TF dead cross/MB EMA) |
| 필터 | volatility, no-trade-zone | downtrend filter, falling knife guard, global gate, **filter profiles (v9.3)** |
| 백테스트 | `scripts/simulate.mjs --preset X --compare` | `scripts/simulate-v2.mjs --compare` |

## 1. Backtest First — Cross-Market x Cross-Strategy

### CRITICAL: Period Consistency Rule

**모든 백테스트는 동일한 `--from`, `--to` 사용 필수.**

- 기간을 처음 한 번 결정 → 전체 세션에서 재사용
- 실거래 비교 시 `trade-history-YYYYMMDD.json`의 실제 거래 타임스탬프를 커버해야 함
- Before/After 비교 (`--save-baseline` / `--compare-baseline`)는 반드시 동일 기간
- Upbit API 제한: 5분봉 기준 약 3일치가 최대 (200개 × 5 = 1000분 × batch)

### 1-1. Multi-Market Strategy Comparison (필수)

```bash
FROM="2026-04-07 00:00"
TO="2026-04-09 17:00"

# 4전략 비교 (auto, meanReversion, trendFollowing, momentumBreakout)
node scripts/simulate-v2.mjs --market KRW-BTC --from "$FROM" --to "$TO" --candle 5 --compare
node scripts/simulate-v2.mjs --market KRW-ETH --from "$FROM" --to "$TO" --candle 5 --compare
node scripts/simulate-v2.mjs --market KRW-XRP --from "$FROM" --to "$TO" --candle 5 --compare
```

### 1-2. Build Performance Matrix

```
              | auto     | MR       | TF       | MB
  KRW-BTC     | WR / PnL | WR / PnL | WR / PnL | WR / PnL
  KRW-ETH     |          |          |          |
  KRW-XRP     |          |          |          |
```

### 1-3. Auto Mode Strategy Breakdown

`--compare` 모드 실행 시 auto의 전략별 내부 분포도 함께 출력됨:

```
--- Auto Mode Strategy Breakdown ---
  MeanReversion   | 8 trades | WR 62.5% | PnL +450 KRW
  TrendFollowing  | 4 trades | WR 25.0% | PnL -200 KRW
  MomentumBrkout  | 1 trades | WR 0.0%  | PnL -50 KRW
```

이 분포를 기준으로 어떤 전략이 문제인지 식별.

## 2. Data-Driven Strategy Analysis

### 2-1. 진입 분석 포인트

| 관점 | 확인 방법 | 판단 기준 |
|------|----------|----------|
| 약한 추세 진입 | TF의 EMA gap 분포 | 프로파일별 임계값 확인 (tf_strong 0.1%, tf_moderate 0.2%) |
| 과매수 진입 | TF의 BB position | 프로파일별 BB ceiling (tf_strong 85, tf_moderate 80) |
| 프로파일 선택 오류 | 프로파일 breakdown vs PnL | 특정 프로파일 집중 손실 → 선택 조건 검토 |
| 잘못된 조건 라우팅 | condition vs 실제 가격 움직임 | trending_up인데 하락 → condition 탐지 지연 |
| 글로벌 레짐 게이트 | skippedReasons.globalGate | crisis/bear에서 차단 정상 여부 |
| downtrend 과차단 | skippedReasons.downtrend | 좋은 진입 기회까지 차단하는지 |
| falling knife | skippedReasons.fallingKnife | MR + ranging downward bias 차단 |
| V3 주문 흐름 차단 | entryHint "매도세 우위" | buyRatio < 0.2 → 진입 차단 (V3만, v9.4 완화) |
| V3 Flow Alpha 부스트 | alpha boost 로그 | tfiAlpha > 0.3 && vwapSpread > 0 → +0.1 boost (V3/V4만) |
| VPIN 독성 게이트 | "VPIN 높음" 진입 힌트 | isHighToxicity → 진입 차단 (V3만) |

### 2-2. 매도 분석 포인트

| 관점 | 확인 방법 | 판단 기준 |
|------|----------|----------|
| ATR SL 조기 퇴장 | exit reason에 "ATR stop-loss" 비율 | 전체 매도의 50% 이상이면 진입 문제 |
| TF dead cross 타이밍 | 보유 기간 + PnL | 보유 < 5bars + 손실 → 진입이 약했음 |
| MR BB exit 효과 | BB > 85에서 매도 후 가격 추이 | 매도 후 계속 상승 → 임계값 높이기 |
| MR RSI exit | RSI > 70에서 매도 | 매도 후 계속 상승 → 임계값 높이기 |
| V3 Exit Monitor 조기 탈출 | EXIT-MONITOR 로그 빈도 | ATR SL 틱 레벨 → 더 빈번한 SL hit 가능 |
| V3 매도세 조기 탈출 | ORDER-FLOW sell pressure | buyRatio ≤ 0.35 + PnL < -1% → 조기 탈출 (V3만) |
| Feature Snapshot 라벨 | FEATURE-SNAPSHOT 로그 | profit/loss/time/early_exit 분포 확인 |

### 2-3. 실거래 데이터 분석

```bash
# 오늘 거래 내역 분석
cat backend/data/trade-history-20260409.json | node -e "
const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
// ... strategy/condition/globalRegime/exitReason별 그룹핑
"
```

실거래 로그에서 직접 확인하는 것이 가장 정확 — 백테스트와 실거래 간 구조적 차이 존재.

## 3. Key V2 Parameters

### 필터 프로파일 시스템 (v9.3)

진입 파라미터는 **필터 프로파일**에 의해 동적으로 결정됨. 프로파일은 지표 강도(ADX, BB position, RVOL)에 따라 자동 선택되고, 해당 프로파일의 필터만 적용.

**TF 프로파일** (우선순위: tf_volume > tf_strong > tf_moderate):

| Profile | 선택 조건 | emaGap | tfVolume | tfBBCeiling | tfADX | tfDIRatio |
|---------|----------|--------|----------|-------------|-------|-----------|
| tf_strong | ADX > 35 | 0.1% | 0.8x | 85 | 25 | 1.2 |
| tf_moderate | 기본 | 0.2% | 1.0x | 80 | 25 | 1.2 |
| tf_volume | RVOL > 2.0 | 0.1% | 0.8x | 80 | 20 | 1.0 |

**MR 프로파일** (우선순위: mr_uptrend > mr_deep > mr_standard):

| Profile | 선택 조건 | bbThreshold | rsiThreshold | bullishCandle | minVol | minBBBW | bbFloor |
|---------|----------|-------------|-------------|---------------|--------|---------|---------|
| mr_deep | BB < 5 | 5 | 35 | false | 0.2x | 0.003 | -20 |
| mr_standard | 기본 | 15 | 35 | true | 0.4x | 0.005 | -20 |
| mr_uptrend | trending_up | 45 | 40 | true | 0.3x | 0.005 | -10 |

> **프로파일 튜닝**: `engineV2.params.filterProfiles`에 오버라이드 저장 가능 (API: PUT `/api/config/filter-profiles`). 백테스트에서는 entry.js의 DEFAULT_FILTER_PROFILES가 직접 사용됨.

### 진입 파라미터 (entry.js) — 프로파일 미적용 시 기본값

| Parameter | 위치 | 기본값 | 효과 |
|-----------|------|--------|------|
| `bbThreshold` | MR entry | 15 (v9.2) | 낮을수록 BB 하단 가까이에서만 진입 |
| `rsiThreshold` | MR entry | 35 | 낮을수록 과매도 상태에서만 진입 |
| `emaGapThreshold` | TF entry | 0.2 (v9.3 tf_moderate) | 높을수록 강한 추세에서만 TF 진입 |
| `tfBBCeiling` | TF entry | 80 (v9.3) | TF 과매수 진입 방지 |

### 매도 파라미터 (exit.js)

| Parameter | 위치 | 기본값 | 효과 |
|-----------|------|--------|------|
| ATR SL multiplier (TF) | TF exit | 3.0 (crisis: 1.0) | TF 전용 넓은 손절 (v6.3) |
| ATR SL multiplier (MR/MB) | MR/MB exit | 2.0 (crisis: 1.0) | MR/MB 기본 손절 |
| `bbExitThreshold` | MR exit | 85 | BB position 기반 MR 익절 |
| `rsiExitThreshold` | MR exit | 70 | RSI 기반 MR 익절 |
| `tfBBExitThreshold` | TF exit | 90 | BB position 기반 TF 수익 실현 (v6.3) |
| EMA dead cross | TF exit | EMA10 < EMA20 | TF 추세 반전 퇴장 |
| Price < EMA20 | MB exit | - | MB 지지선 이탈 퇴장 |

### Surge Exit (exit.js, core.js) — v6.4

| Parameter | 위치 | 기본값 | 효과 |
|-----------|------|--------|------|
| ATR SL multiplier (surge) | exit.js | 4.0 (crisis: 1.5) | 일반 2-3x보다 넓은 손절 |
| `surgeMinHoldBars` | exit.js | 12 | 60min@5min 최소 보유 |
| `surgeBBExitThreshold` | exit.js | 95 | 극단적 과매수 수익 실현 |
| `surgeGraduationBars` | exit.js | 60 | 5h 후 일반 exit 전환 |
| Volume dry-up | exit.js | 0.5x | 볼륨 반감 + 손실 → 모멘텀 소진 |
| Recovery PnL floor | exit.js | -3% | -3% 이내 + EMA10 위 → hold |

### TF Guards (core.js, exit.js) — v6.1

| Parameter | 위치 | 기본값 | 효과 |
|-----------|------|--------|------|
| `tfGuards.minHoldBars` | exit.js | 6 | Dead cross 최소 보유 bars (ATR SL 유지) |
| `tfGuards.consecutiveLossCooldown` | core.js | 2 | 같은 종목 TF 연속 손실 N회 → 진입 차단 |
| `tfGuards.consecutiveLossCooldownBars` | core.js | 60 | 연속 손실 후 쿨다운 bars |

### Confidence Sizing (core.js) — v6.1

| Parameter | 위치 | 기본값 | 효과 |
|-----------|------|--------|------|
| `confidenceSizing.enabled` | core.js | true | 품질 기반 사이징 활성화 |
| `confidenceSizing.maxMultiplier` | core.js | 1.5 | 최대 배수 cap |
| MR strong | core.js | bbPos<0, RSI<25 | 극과매도 → 1.5x |
| TF strong | core.js | ADX>40, DI ratio>2.0 | 강한 추세 → 1.5x |
| MB strong | core.js | volumeRatio>3.0 | 강한 돌파 → 1.5x |

### 글로벌 레짐 게이트 (marketRegime.js)

| Regime | allowBuy | allowMR | positionSize |
|--------|----------|---------|-------------|
| bull | true | true | 1.5x |
| neutral | true | true | 1.0x |
| bear | true | **false** | 0.5x |
| crisis | **false** | false | 0x |

### 백테스트 파라미터 오버라이드

```bash
# MR 파라미터 튜닝
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --bb-threshold 10 --rsi-threshold 30

# 쿨다운 조정
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --cooldown 300000

# 가상 포지션 금액 변경
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --amount 100000
```

## 4. Baseline A/B Comparison

### 4-1. Save Baseline (변경 전 - 필수)

```bash
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --save-baseline v5.20-pre
```

### 4-1.5. Impact Analysis (변경 전 - 필수)

파라미터 변경 전에 영향 범위를 확인한다. **변경할 파라미터마다 실행**:

```bash
# 변경할 파라미터의 blast radius 확인
node scripts/impact-analysis.mjs --param <paramName>

# 예시
node scripts/impact-analysis.mjs --param mrMinVolumeRatio
node scripts/impact-analysis.mjs --param tfBBCeiling
node scripts/impact-analysis.mjs --param calcVolumeRatio

# 전체 파라미터 목록
node scripts/impact-analysis.mjs --list

# 전체 불변 관계 상태
node scripts/impact-analysis.mjs --all
```

출력에서 확인할 사항:
- **의존성**: 이 파라미터가 의존하는 인프라(calcVolumeRatio 등)가 함께 바뀌는지
- **불변 관계**: 변경 후에도 프로파일 간 관계(deep <= standard <= uptrend)가 유지되는지
- **영향 프로파일**: 어떤 프로파일이 영향받는지 → 해당 프로파일 백테스트 필수

> ⚠ `calcVolumeRatio` 방법론 변경 시: 모든 RVOL 임계값(mrMinVolumeRatio, tfVolumeThreshold) 재보정 필수.
> impact-analysis.mjs --param calcVolumeRatio 로 영향 범위를 먼저 파악할 것.

### 4-2. Implement Changes

V2/V3 변경 대상 파일:

| File | What to Update |
|------|---------------|
| `backend/src/engine-v2/entry.js` | 진입 전략 (MR/TF/MB) 파라미터, 필터, **필터 프로파일 정의** (DEFAULT_FILTER_PROFILES) |
| `backend/src/engine-v2/exit.js` | 매도 전략, ATR SL 멀티플라이어 |
| `backend/src/engine-v2/core.js` | V2 전략 라우팅, 게이트 로직, 쿨다운 |
| `backend/src/engine-v3/core.js` | V3 전략 라우팅 (V2 core.js와 동일 전략, 이벤트 기반 스케줄링) |
| `backend/src/engine-v3/exitMonitor.js` | V3 실시간 ATR/트레일링 스탑 (틱 레벨) |
| `backend/src/engine-v3/orderFlow.js` | V3 주문 흐름 분석 (매수세/매도세, 5분 윈도우) |
| `backend/src/engine-v3/flowAlpha.js` | Flow Alpha 시그널 (TFI Z-Score, VWAP Spread, Intensity Accel) |
| `backend/src/engine-v3/featureSnapshot.js` | ML 학습용 피처 스냅샷 (진입 시 25+ 필드 기록) |
| `backend/src/engine-v3/tripleBarrier.js` | Triple Barrier 라벨링 (ATR×2 기반 profit/loss/time 배리어) |
| `backend/src/strategy/marketRegime.js` | 글로벌 레짐 분류, 게이트 테이블 |
| `backend/src/strategy/regimeDetector.js` | Per-symbol condition 탐지 |
| `backend/src/engine-v2/symbolPipeline.js` | Downtrend filter, accumulation |

> Note: `simulate-v2.mjs`는 entry.js, exit.js 등을 직접 import하므로 별도 동기화 불필요.
> V3 고유 모듈(exitMonitor, orderFlow, realtimeCandles)은 백테스트에서 시뮬레이션되지 않으나,
> 진입/매도 전략 파라미터 변경은 V2/V3 모두에 즉시 반영됨.

### 4-3. Verify (변경 후 - 필수)

```bash
# 1. 불변 관계 테스트 먼저 (프로파일 간 관계 깨짐 감지)
cd backend && npx vitest run src/engine-v2/__tests__/invariants.test.js

# 2. 전체 테스트
cd backend && npx vitest run src/engine-v2/__tests__/
cd backend && npx vitest run src/engine-v3/__tests__/

# 3. 불변 관계 전체 상태 확인
node scripts/impact-analysis.mjs --all

# 4. Baseline 비교
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --compare-baseline v5.20-pre
node scripts/simulate-v2.mjs --market KRW-ETH --from "..." --to "..." --compare
```

> 불변 관계 테스트(invariants.test.js)가 실패하면 프로파일 간 구조적 관계가 깨진 것.
> 의도된 변경이 아니라면 파라미터를 재조정할 것.

### 4-4. Go/No-Go Decision

- **Deploy**: 다수 종목에서 개선, 핵심 종목(BTC, ETH) 악화 없음
- **Rollback**: BTC/ETH에서 유의미한 악화
- **Partial**: 특정 전략만 개선 → 해당 전략 조건부 적용

## 5. Sensitivity Analysis

### EMA gap threshold 튜닝 (TF 전용)

```bash
for threshold in 0.1 0.2 0.3 0.5 0.7; do
  echo "=== emaGap >= $threshold ==="
  node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --strategy trendFollowing
done
```

> Note: `emaGapThreshold`는 현재 CLI 파라미터로 노출되지 않음 — `params.emaGapThreshold`를 스크립트에서 직접 전달하거나, entry.js의 기본값을 변경 후 비교.

### MR 파라미터 튜닝

```bash
# BB threshold 민감도
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --bb-threshold 3 --strategy meanReversion
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --bb-threshold 5 --strategy meanReversion
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --bb-threshold 10 --strategy meanReversion

# RSI threshold 민감도
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --rsi-threshold 30 --strategy meanReversion
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --rsi-threshold 35 --strategy meanReversion
node scripts/simulate-v2.mjs --market KRW-BTC --from "..." --to "..." --rsi-threshold 40 --strategy meanReversion
```

## 6. Live vs Backtest Comparison

### 구조적 차이

| 항목 | V2 실거래 | V3 실거래 | 백테스트 (simulate-v2.mjs) |
|------|----------|----------|--------------------------|
| BTC 레짐 | 매 틱(10초) 4h API 조회 | 캔들 마감 시 조회 | 4h 완성 캔들 이진 탐색 |
| 종목 캔들 | 실시간 API (미완성 포함) | Trade WS 실시간 빌드 | 완성된 5분봉만 사용 |
| 손절 반응 | 10초 폴링 | **매 틱 실시간** (<1초) | 캔들 마감 시 |
| 주문 흐름 | 없음 | **매수세/매도세 분석** | 없음 |
| Flow Alpha | 없음 | **TFI/VWAP/Accel 연속 시그널** | 없음 |
| Feature Snapshot | 없음 | **진입 시 25+ 피처 자동 기록** | 없음 |
| Triple Barrier 라벨링 | 없음 | **매도 시 ATR 기반 자동 라벨링** | 없음 |
| Surge 감지 | surgeDetector 연동 | surgeDetector 연동 | Surge bypass 없음 |
| 쿨다운 | 실시간 밀리초 기반 | 실시간 밀리초 기반 | 틱 UTC 밀리초 기반 |
| 포지션 관리 | position/index.js | position/index.js | 로컬 변수 |
| 24h 변화율 | ticker API | ticker API | 캔들 기반 계산 |

**핵심:** 백테스트는 relative comparison (before vs after)에 신뢰성 높음, absolute PnL은 실거래와 차이 있음.
V3의 실시간 Exit Monitor와 Order Flow는 백테스트에서 재현되지 않으므로, 실거래 성과가 백테스트보다 개선될 수 있음.

### 실거래 데이터 확인

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
ls -la backend/data/feature-snapshots-*.json 2>/dev/null | wc -l
node -e "const fs=require('fs'); const files=fs.readdirSync('backend/data').filter(f=>f.startsWith('feature-snapshots-')); let total=0; files.forEach(f=>{const d=JSON.parse(fs.readFileSync('backend/data/'+f));total+=d.length}); console.log('Total snapshots:',total,'files:',files.length)"
```

## 7. Documentation Update (Mandatory)

변경 후 `strategy-docs` 스킬 실행:
- `plan_doc/strategy_reference/CURRENT_STRATEGY.md` 업데이트
- `plan_doc/{N}_strategy_update_{version}_{YYYYMMDD}.md` 변경 로그 작성
- 버전 인크리먼트 (v{major}.{minor})
