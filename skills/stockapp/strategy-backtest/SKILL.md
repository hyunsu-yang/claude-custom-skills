---
name: strategy-backtest
description: stockapp 전략 백테스트 실행 가이드. eBest t8412 API로 과거 5분봉 수집 후 진입/청산 조건 조합별 시뮬레이션. Use when "백테스트", "backtest", "과거 데이터 시뮬", "조건 테스트", "진입 조건 검증" 등을 언급할 때.
---

# stockapp 전략 백테스트 가이드

eBest t8412 (분봉) API로 과거 데이터를 수집하고, `EntryEvaluator` 조건 조합별 진입 횟수·승률을 시뮬레이션한다.

> **주의**: 호가(orderbook) imbalance는 과거 재현 불가. 백테스트는 신고가·거래량·양봉 조건만 검증한다.
> 호가 필터 효과는 장중 dry-run(enabled=false 상태의 실시간 로그)으로 별도 검증한다.

---

## 1. 데이터 수집

### 1-1. t8412 날짜 범위 조회 (EbestRestClient)

현재 `fetchMinuteCandles`는 당일치만 가져온다. 과거 다일 수집은 `sdate`/`edate` 범위를 직접 지정한다.

```bash
# Python 스크립트로 과거 N일치 5분봉 수집
# backend/scripts/backtest/fetch_candles.py
python backend/scripts/backtest/fetch_candles.py \
  --symbols 005930,000660,035420 \
  --from 20260401 \
  --to   20260430 \
  --interval 5 \
  --out  backend/scripts/backtest/data/
```

출력: `data/{symbol}_{from}_{to}.csv` — 컬럼: `date,time,open,high,low,close,volume`

### 1-2. 유니버스 전체 수집

```bash
# KOSPI+KOSDAQ 거래대금 상위 60종목 자동 수집
python backend/scripts/backtest/fetch_candles.py \
  --universe top60 \
  --from 20260401 \
  --to   20260430 \
  --interval 5
```

---

## 2. 백테스트 실행

### 2-1. 단일 파라미터 조합

```bash
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --volume-burst 1.5 \
  --price-move 0.5 \
  --long-high-days 22 \
  --long-high-enabled true
```

### 2-2. 파라미터 스윕 (그리드 탐색)

```bash
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --sweep \
  --volume-burst 1.0,1.5,2.0,3.0 \
  --price-move  0.2,0.5,1.0 \
  --long-high-enabled true,false
```

### 2-3. 시간대별 분리 (종가배팅 vs 장중)

```bash
# 장중 모멘텀 구간만 (09:00~14:30)
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --time-from 0900 --time-to 1430 \
  --long-high-enabled false \
  --volume-burst 1.5 --price-move 0.3

# 종가배팅 구간만 (15:10~15:25)
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --time-from 1510 --time-to 1525 \
  --long-high-enabled true \
  --volume-burst 2.0 --price-move 1.0
```

---

## 3. 출력 포맷

### 3-1. 단일 실행

```
═══ Backtest: 005930 [2026-04-01 ~ 2026-04-30] ═══
Candle: 5min | Entry window: 09:00~15:25

--- Entry Signals ---
  #1  04-01 10:15 | vol_burst=2.3 move=1.2% | → +1.8% (held 4bars)
  #2  04-03 14:30 | vol_burst=1.8 move=0.6% | → -0.5% (held 2bars)

--- Performance ---
  Signals: 12 | Tradeable: 10 (qty>0)
  WinRate (next-bar close): 60.0%
  AvgGain: +0.9% | AvgLoss: -0.4%
  Expectancy: +0.38%/signal

--- Skip Breakdown ---
  신고가미달: 45 | 거래량부족: 8 | 양봉미달: 12 | 캔들부족: 3
```

### 3-2. 스윕 결과 (파라미터 비교 테이블)

```
--- Parameter Sweep Results ---
  vol_burst | price_move | Signals | WinRate | Expectancy | AvgHold
  1.0       | 0.2        |      87 |   52.1% |     +0.20% |     3.1
  1.5       | 0.5        |      34 |   61.8% |     +0.48% |     4.2  ← 추천
  2.0       | 1.0        |      11 |   63.6% |     +0.51% |     5.1
  3.0       | 1.0        |       4 |   75.0% |     +0.72% |     6.0  (샘플 너무 적음)
```

### 3-3. 시간대별 비교

```
--- Time Window Comparison ---
  Window      | Signals | WinRate | Expectancy | Note
  09:00~14:30 |      28 |   53.6% |     +0.22% | 장중 모멘텀
  15:10~15:25 |       6 |   66.7% |     +0.58% | 종가배팅 (샘플 적음)
  전체        |      34 |   55.9% |     +0.30% |
```

---

## 4. 결과 해석 가이드

| 지표 | 기준 | 해석 |
|------|------|------|
| Signals | > 20/월 | 샘플 충분 (< 10이면 노이즈) |
| WinRate | > 55% | 진입 조건 유효 |
| Expectancy | > 0% | 전략 수익성 있음 |
| AvgHold | 3~10 bars | 적정 (< 2: 노이즈, > 15: 오래 물림) |

### Skip Breakdown 분석

| Skip 사유 | 높을 때 의미 | 조치 |
|-----------|-------------|------|
| 신고가미달 多 | 신고가 필터가 너무 강함 | `longHighCheckEnabled=false` 또는 기간 줄이기 |
| 거래량부족 多 | volumeBurstMultiplier 너무 높음 | 1.5→1.2로 완화 |
| 양봉미달 多 | priceMoveMinPct 너무 높음 | 1.0→0.3으로 완화 |
| 호가없음 多 | 장 후반 호가 데이터 미수신 | 시간대 필터 확인 |

---

## 5. Baseline A/B 비교

### 5-1. 현재 파라미터 저장

```bash
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --volume-burst 1.2 --price-move 0.2 \
  --save-baseline current_yml
```

저장 경로: `backend/scripts/backtest/baselines/current_yml.json`

### 5-2. 변경 후 비교

```bash
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --volume-burst 1.5 --price-move 0.5 \
  --compare-baseline current_yml
```

출력:
```
═══ Baseline Comparison: current_yml ═══
              | Baseline  | Current   | Delta
  Signals     |        87 |        34 | -53
  WinRate     |     52.1% |     61.8% | +9.7%p
  Expectancy  |    +0.20% |    +0.48% | +0.28%p  ← 개선
```

---

## 6. Live vs Backtest 구조적 차이

| 항목 | 실거래 | 백테스트 |
|------|--------|---------|
| 호가 imbalance | 실시간 WebSocket | **재현 불가 — 제외** |
| 5분봉 | eBest t8412 (완성봉) | eBest t8412 동일 |
| 신고가 | LongHighCache (22일) | CSV에서 rolling max 계산 |
| 거래량 burst | 직전 12봉 평균 대비 | 동일 |
| VWAP 차단 | vwapBreakoutBlockPct | 동일 계산 가능 |
| 주문 체결 | 시장가 → 슬리피지 있음 | 다음봉 시가 체결 가정 |

**핵심**: 백테스트는 진입 조건 빈도·방향성 검증에 유효. 절대 PnL은 실거래와 차이 있음.

---

## 7. 백테스트 → 전략 개선 흐름

```
백테스트 실행
  → 파라미터 스윕으로 최적 조합 식별
  → application.yml 수정
  → 다음 영업일 장중 로그로 skip 사유 변화 확인
  → 필요시 strategy-improvement 스킬 실행
```
