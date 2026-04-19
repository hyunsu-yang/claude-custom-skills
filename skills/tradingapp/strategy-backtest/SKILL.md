---
name: strategy-backtest
description: Backtest execution, output formatting, live vs backtest comparison, and structural gap documentation. Use when the user asks to run backtests, calculate expected profit for a market/period, compare live vs backtest results, or mentions "백테스트", "시뮬레이션", "예상 수익", or "실거래 비교".
---

# Strategy Backtest Guide

## 1. Single-Market Profit Simulation (종목별 예상 수익 계산)

When the user asks to calculate expected profit for a specific market and period, **always** present results in the following format.

### 1-1. Run Simulation

```powershell
# Verbose simulation with the market's assigned preset (check trading.json symbolPresets)
node scripts/simulate.mjs --market KRW-XXX --from "YYYY-MM-DD HH:mm" --to "YYYY-MM-DD HH:mm" --candle 3 --preset <assigned_preset> --verbose

# Also run --compare to show all presets side by side
node scripts/simulate.mjs --market KRW-XXX --from "YYYY-MM-DD HH:mm" --to "YYYY-MM-DD HH:mm" --candle 3 --compare
```

### 1-2. Output: Summary Table (총 성과 요약)

| 항목 | 값 |
|------|-----|
| 총 수익률 | +X.XX% |
| 총 수익 | +X,XXX KRW |
| 거래 수 | N건 (W승 L패) |
| 승률 | XX.XX% |
| 최대 낙폭 | -X.XX% |
| 수수료 합계 | XXX KRW |
| 최종 잔고 | X,XXX,XXX KRW |

### 1-3. Output: Chronological Detail Table (시간 흐름 순 상세 테이블)

Build a table from the verbose tick log with **every trade event and regime change**:

| # | 시간 | 가격 | 레짐 | ADX | 이벤트 | 시그널 강도 | 비중(mult) | 수익률 | 수익(KRW) | 누적 수익 |
|---|------|------|------|-----|--------|------------|-----------|--------|----------|-----------|

Rules:
- Include **every buy/sell** as numbered round-trip pairs (#1 buy, #1 sell, #2 buy, #2 sell, ...)
- Include **every regime change** between trades (as separate rows without trade number)
- Include notable non-trade periods (e.g., "NoTrade regime", "Uptrend but no position — missed opportunity")
- Show cumulative PnL in the last column

### 1-4. Output: Price Flow vs Position Chart (가격 흐름 vs 포지션 보유 구간)

Draw an ASCII chart showing:
- Y-axis: price levels (key prices only)
- X-axis: time
- `┃` vertical bars for position-held periods
- `★` for notable price peaks/troughs reached without a position
- Buy/sell annotations with trade number

```
가격  9.72 ·                              ★ 고점 (포지션 없음)
      9.0  ·                           ╱ ╲
      8.0  ·                        ╱     ╲
      7.63 ·            ┃  ┃ ┃   ┃╱         ╲  ← #6 매도
      7.0  ·     ┃      ┃  ┃ ┃   ┃            ╲
      6.92 ·     ┃      ┃  ┃ ┃   ┃← #6 매수     ╲
      ...
```

### 1-5. Output: Preset Comparison Table (프리셋별 비교)

From the `--compare` output:

| Preset | Return | PnL(KRW) | Trades | WinRate |
|--------|--------|----------|--------|---------|

### 1-6. Output: Live Trading vs Backtest Comparison Table (실거래 vs 백테스트 비교)

When the user asks to compare live (paper) trading results against backtest, **always** build this table from `trade-history.json` logs and the backtest output:

| 항목 | 실거래 | 백테스트 |
|------|--------|---------|
| **종목** | KRW-XXX | KRW-XXX |
| **프리셋** | (from symbolPresets) | (--preset used) |
| **분봉** | (candleUnit from config) | (--candle used) |
| **기간** | (actual trade timestamps, KST) | (--from / --to, KST) |
| **데이터 소스** | 실시간 API (N초 간격 폴링, 미완성 캔들 포함) | 완성된 N분봉 종가만 사용 |
| **매수 시각** | (from trade-history.json) | (from backtest log) |
| **매수가** | (calculated: priceKrw / volume) | (from backtest log) |
| **레짐 (매수 시)** | (from trade meta.regime) | (from backtest log) |
| **매수 사유** | (from trade reason) | (from backtest log) |
| **비중 (amountMult)** | (from trade meta.amountMultiplier) | (from backtest log) |
| **부분 매도** | (if partial_tp exists) | (from backtest log) |
| **최종 매도** | (from trade-history.json) | (from backtest log) |
| **매도 사유** | (from trade meta.exitReason) | (from backtest log) |
| **총 수익** | +X,XXX KRW (+X.X%) | +X,XXX KRW (+X.X%) |
| **보유 시간** | Xm | Xm (N ticks) |

Rules:
- **Period**: backtest `--from`/`--to` MUST match the live trade timestamps (KST). Convert UTC timestamps from `trade-history.json` to KST (+9h).
- **Preset**: MUST match the live trading preset from `trading.json > symbolPresets`.
- **Candle unit**: MUST match `trading.json > autoTrading.candleUnit`.
- When significant discrepancies exist (e.g., different regime detection, different sell timing), add a **"괴리 원인 분석"** section explaining:
  1. Data resolution difference (live engine polls every N seconds with incomplete candles vs backtest uses completed candles only)
  2. Regime detection divergence and its impact on strategy dispatch
  3. Sell timing difference and missed profit/loss

### 1-7. Output: Key Insights (핵심 인사이트)

Summarize:
1. Which trade(s) drove most of the profit
2. Missed opportunities (price moved significantly while no position held)
3. Regime transitions and their impact on trading
4. Auto-preset assignment implications (which preset would be auto-assigned based on daily regime)

## 2. Known Limitation: Live vs Backtest Structural Gap

### 2-1. Root Cause

The live engine and the backtest simulator process candle data differently:

| Aspect | Live Engine | Backtest (default) | Backtest (`--subtick`) | Backtest (`--hybrid`) |
|--------|------------|-------------------|----------------------|----------------------|
| Polling interval | Every `intervalSeconds` (e.g., 10s) | Once per completed candle | Once per completed candle | Once per **1-min** candle |
| Candle state | Includes **incomplete (forming) candle** | Only **completed candles** | Completed + OHLC interpolation | Completed 1-min candles |
| Risk evaluation | Every poll (10s) with real-time price | At candle close only | **6 sub-ticks per candle** (OHLC) | Every 1-min + OHLC sub-ticks |
| Regime detection | Real-time (mid-candle changes possible) | At candle boundaries only | At candle boundaries only | **Every 1-min candle** |
| Strategy signals | Every poll | At candle close | At candle close | At **N-min candle** close |

This means for volatile or low-price assets, the live engine may detect `strong_trend_up` (ADX=52) while the backtest sees `Ranging` (ADX=16) at the same wall-clock time. This leads to different strategy dispatch and vastly different trade outcomes.

### 2-2. Mitigation Modes (choose based on need)

| Mode | Command | Best For | Accuracy vs Live |
|------|---------|----------|-----------------|
| **Default** | `--candle 3` | Quick iteration, parameter tuning | ★★☆☆☆ |
| **Subtick** | `--candle 3 --subtick` | SL/TP/trailing accuracy on volatile assets | ★★★☆☆ |
| **Hybrid** | `--candle 3 --hybrid` | **Closest to live engine** — 1-min regime + risk, N-min strategy | ★★★★☆ |
| 1-min candle | `--candle 1` | Higher resolution (but changes regime/strategy behavior) | ★★☆☆☆ (different strategy) |

**IMPORTANT**: `--candle 1` does NOT simply increase resolution — it changes the indicator window from 3-min to 1-min, producing different ADX/RSI/BB values and potentially different regimes and strategy signals. Only use when intentionally testing 1-min strategy behavior.

### 2-3. Practical Guidelines for Backtest Interpretation

1. **Always run `--hybrid` for live vs backtest comparison** — default mode can show completely different regimes and trade outcomes.
2. **Expect ~30-50% PnL gap** between hybrid backtest and live trading for low-price or high-volatility assets. This is the irreducible gap from incomplete-candle indicator calculation.
3. **Backtest is reliable for relative comparison** (A vs B preset, before vs after parameter change) even if absolute PnL differs from live.
4. **Do NOT change strategy parameters solely to match backtest to live results** — the gap is structural, not a parameter issue.
5. **Low-price coins (< 100 KRW)** have amplified gaps because 1 KRW price change = 1-10%+ move, and 3-min candle close may miss intra-candle spikes entirely.

### 2-4. Why 10-second or sub-minute backtesting is not feasible

- Upbit REST API minimum candle unit is **1 minute** — no 10s/30s candles available.
- Historical tick data is not provided by Upbit API (WebSocket is real-time only, no lookback).
- Even if tick data were collected, current strategy parameters (ADX period, EMA period, BB period) are **tuned for minute-scale candles** and would produce excessive noise on sub-minute data.
- Building a tick-data collection infrastructure is a separate project with significant storage and reliability requirements.

### 2-5. Correct Way to Evaluate Strategy Improvements

**CRITICAL: Do NOT judge strategy improvement success by comparing backtest absolute PnL against live trading absolute PnL.**

Due to the structural gap (2-1), the backtest operates under fundamentally different (and generally disadvantageous) conditions compared to the live engine. Even an identical strategy will produce lower absolute returns in backtest than in live trading, especially for low-price or high-volatility assets.

| Comparison Method | Validity | Reason |
|-------------------|----------|--------|
| Backtest PnL vs Live PnL (absolute) | **INVALID** | Structural gap makes conditions unequal — backtest will almost always underperform live |
| Backtest(before) vs Backtest(after) | **VALID** | Same simulator, same conditions — relative improvement is trustworthy |
| Live(before) vs Live(after) | **MOST ACCURATE** | Same engine, real-time data — definitive proof of improvement |

**Correct workflow for strategy improvement validation:**

1. Save baseline: `--save-baseline v{X}-pre` (before changes)
2. Implement strategy changes
3. Compare: `--compare-baseline v{X}-pre` (after changes, same period)
4. If backtest(after) > backtest(before) → strategy improvement is **valid**
5. Deploy to live and monitor live(after) vs live(before) for final confirmation

**Common misconception:** "If the improved strategy's backtest shows lower PnL than the old strategy's live results, the improvement failed." This is **wrong** — the backtest would have shown even lower PnL with the old strategy under the same backtest conditions. Always compare apples to apples (backtest vs backtest, or live vs live).

## 3. Period Consistency Rule

**All backtests in a single comparison session MUST use the exact same `--from` and `--to` values.**

- Decide `--from` and `--to` ONCE at the start, then reuse for every command.
- The period must cover the full range of interest — if Paper Trading results include trades up to today, the backtest `--to` must be >= the latest trade timestamp.
- When comparing against Paper Trading results, check `trade-history.json` for the actual trade timestamps and ensure the backtest period covers them.
- Before/After comparisons (`--save-baseline` / `--compare-baseline`) MUST use identical periods.
- NEVER truncate the period mid-way (e.g., ending at 08:00 when trades occurred at 09:00).
