---
name: strategy-improvement
description: Data-driven strategy improvement workflow using simulation-first approach with cross-market backtest matrix. Use when the user asks to improve strategy, tune presets, optimize parameters, or mentions "전략 개선", "프리셋 튜닝". For backtest execution, output formatting, and live vs backtest comparison, see strategy-backtest skill.
---

# Strategy Improvement Workflow

When asked to improve strategy (전략 개선), follow this workflow in order.

## 1. Backtest First — Cross-Market x Cross-Preset Matrix

### CRITICAL: Period Consistency Rule

**All backtests in a single comparison session MUST use the exact same `--from` and `--to` values.**

- Decide `--from` and `--to` ONCE at the start, then reuse for every command.
- The period must cover the full range of interest — if Paper Trading results include trades up to today, the backtest `--to` must be >= the latest trade timestamp.
- When comparing against Paper Trading results, check `trade-history.json` for the actual trade timestamps and ensure the backtest period covers them.
- Before/After comparisons (`--save-baseline` / `--compare-baseline`) MUST use identical periods.
- NEVER truncate the period mid-way (e.g., ending at 08:00 when trades occurred at 09:00).

### 1-1. Multi-Market Preset Comparison (필수)

```powershell
# Decide period ONCE, reuse everywhere
$FROM = "YYYY-MM-DD HH:mm"
$TO   = "YYYY-MM-DD HH:mm"

node scripts/simulate.mjs --market KRW-BTC --from $FROM --to $TO --candle 15 --compare
node scripts/simulate.mjs --market KRW-ETH --from $FROM --to $TO --candle 15 --compare
node scripts/simulate.mjs --market KRW-XRP --from $FROM --to $TO --candle 15 --compare
```

### 1-2. Build Performance Matrix

```
              | scalping | dayTrading | midTrend | conservative | bullMarket | bearMarket | overnight
  KRW-BTC     |          |            |          |              |            |            |
  KRW-ETH     |          |            |          |              |            |            |
  KRW-XRP     |          |            |          |              |            |            |
```

### 1-3. Two-Axis Analysis

1. **Column analysis** — Does a change improve ALL presets for a specific market?
   - All improved → market-universal (good)
   - 1-2 improved → preset-specific (targeted)
   - Some hurt → trade-off, document it

2. **Row analysis** — Does a preset change improve ALL markets?
   - All improved → robust (deploy confidently)
   - 1-2 improved → market-condition-specific
   - Some hurt → risky, consider conditional logic

### 1-4. Multi-Candle Validation

For longer-timeframe presets (midTrend, bullMarket, overnight):

```powershell
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 3 --preset midTrend
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --preset midTrend
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 30 --preset midTrend
```

## 2. Data-Driven Strategy Points

Analyze backtest results for:
- **Round-trip PnL**: Which trades lost? Exit reason?
- **Win rate by regime**: Worst-performing regime?
- **Premature sells**: Trailing stops / strategy sells cutting profits short?
- **Missed buys**: Filters blocking good opportunities?
- **Max drawdown**: Risk management too loose/tight?
- **Regime change frequency**: Too many changes = candleUnit too short

### Key Parameters

| Parameter | Effect | Diagnosis |
|-----------|--------|-----------|
| `sellSensitivity` | Lower = higher sell thresholds = fewer premature sells | Check "Momentum exhaustion sell" RSI pct |
| `candleUnit` | Higher = fewer regime changes = more stable | Count regime changes |
| `trailingStopAtrMultiplier` | Higher = wider trailing stop = longer holds | Check "trailing-stop" exits |
| `profitProtectionPeakPercent` | Higher = later profit protection = longer holds | Check "profit-protection" exits |
| `profitProtectionDropRatio` | Lower = tighter exit from peak | Tune with profitProtectionPeakPercent |
| `hysteresisCount` | Higher = slower regime transitions | Count regime changes |

## 3. Baseline A/B Comparison

### 3-1. Save Baseline (변경 전 — 필수)

```powershell
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --compare --save-baseline v4.9-pre
```

### 3-2. Implement Changes

Modify presets in **two locations** (must stay in sync):

| File | What to Update |
|------|---------------|
| `backend/src/presets.js` | `PRESET_CONFIGS` — strategy + risk params + candleUnit |
| `frontend/src/presets/tradingPresets.js` | `TRADING_PRESETS` — full config including UI description |

> Note: `scripts/simulate.mjs` imports directly from `presets.js` and `position/riskManager.js` — no separate sync needed.

### 3-3. Verify (변경 후 — 필수)

```powershell
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --compare --compare-baseline v4.9-pre
node scripts/simulate.mjs --market KRW-ETH --from "..." --to "..." --candle 15 --compare
node scripts/simulate.mjs --market KRW-XRP --from "..." --to "..." --candle 15 --compare
```

### 3-4. Go/No-Go Decision

- **Deploy**: majority of cells improved, no cell > -0.3% regression
- **Rollback**: core market (BTC, ETH) shows significant regression
- **Partial deploy**: improvement is market-specific — make change conditional

## 4. Preset Classification Review

Current presets: `scalping`, `dayTrading`, `midTrend`, `conservative`, `bullMarket`, `bearMarket`, `overnight`

Identify:
- **Unnecessary**: overlap too much or never outperform others
- **Missing**: market conditions not covered
- **Underperforming**: consistently worst — tune or remove

## 5. Backtest Execution & Interpretation

> **Moved to separate skill**: All backtest-related content (simulation output format, live vs backtest comparison, structural gap, evaluation guidelines) is now in the **`strategy-backtest`** skill.
>
> Use `/strategy-backtest` when:
> - Running single-market profit simulations (종목별 예상 수익 계산)
> - Comparing live trading vs backtest results (실거래 vs 백테스트 비교)
> - Understanding backtest limitations and structural gaps
> - Evaluating whether a strategy improvement is valid

## 6. Sensitivity Analysis (Optional)

```powershell
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --preset midTrend --sellSens 1
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --preset midTrend --sellSens 2
node scripts/simulate.mjs --market KRW-BTC --from "..." --to "..." --candle 15 --preset midTrend --sellSens 3
```

Build a parameter sensitivity table to find the **optimal** value.

## 7. Documentation Update (Mandatory)

After changes, follow the `strategy-docs` skill:
- Update `plan_doc/strategy_reference/CURRENT_STRATEGY.md`
- Create numbered change log in `plan_doc/`
- Increment version (v{major}.{minor})
- Review and update `user_guide/` if user-facing settings changed
