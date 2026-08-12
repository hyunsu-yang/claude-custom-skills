---
name: strategy-improvement
description: stockapp 전략 개선 워크플로우. 로그 분석 → 백테스트 → 파라미터 조정 → application.yml 반영 → 문서화. Use when "전략 개선", "파라미터 튜닝", "진입 조건 수정", "strategy improvement", "수익 개선", "거래 0건", "진입이 없어" 등을 언급할 때.
---

# stockapp 전략 개선 워크플로우

로그 분석 → 백테스트 → 파라미터 조정 → 적용 → 검증 순서로 진행한다.

---

## 1. 현황 진단 (Backtest First)

### CRITICAL: 반드시 로그 먼저

전략을 바꾸기 전에 **오늘 로그의 skip 사유 분포**를 확인한다.

```bash
# CYCLE 이벤트에서 skip 사유 추출
grep "CYCLE" backend/logs/stockapp.log | grep "$(date +%Y-%m-%d)" | grep -v "사이클 완료"

# 에러 패턴 확인
grep "Retries exhausted" backend/logs/stockapp.log | grep "$(date +%Y-%m-%d)" | wc -l
grep "evaluate failed" backend/logs/stockapp.log | grep "$(date +%Y-%m-%d)" | tail -5
```

### 1-1. Skip 사유 해석

| Skip 사유 | 의미 | 조치 |
|-----------|------|------|
| `신고가미달` 압도적 | longHighCheckEnabled=true이거나 필터 너무 강함 | longHighCheckEnabled 확인, 또는 기간 줄이기 |
| `양봉미달` 압도적 | 장 후반 하락·횡보장 → 5분봉이 음봉 多 | priceMoveMinPct 완화 또는 시간대 필터 고려 |
| `거래량부족` 多 | volumeBurstMultiplier 너무 높음 | 1.5→1.2 완화 |
| `호가없음` 多 | 장 시작·종료 후 호가 데이터 없음 | 시간대 필터로 해당 구간 제외 |
| `진입조건미달` (집계 없이) | 구형 로그 포맷 (재시작 전) | 재시작 후 로그 확인 |
| `에러 N건` | API rate limit 또는 모의투자 서버 불안정 | 에러 내용 확인, retry 간격 조정 |

### 1-2. 핵심 파라미터 현황 확인

```bash
grep -A 20 "^trading:" backend/src/main/resources/application.yml
```

---

## 2. 백테스트로 파라미터 후보 검증

`strategy-backtest` 스킬 참고하여 과거 데이터로 후보 조합 검증.

```bash
# 현재 파라미터 baseline 저장
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --save-baseline before_change

# 후보 파라미터 스윕
python backend/scripts/backtest/simulate.py \
  --data-dir backend/scripts/backtest/data/ \
  --from 20260401 --to 20260430 \
  --sweep \
  --volume-burst 1.0,1.5,2.0 \
  --price-move 0.2,0.5,1.0 \
  --compare-baseline before_change
```

**Go/No-Go 기준:**

| 판단 | 조건 |
|------|------|
| **적용** | Expectancy 개선 + Signals >= 15/월 + WinRate > 50% |
| **보류** | Signals < 10 (샘플 부족) |
| **기각** | Expectancy 악화 OR WinRate < 45% |

---

## 3. 전략 분기 설계 (옵션 C — 시간대별 전략)

장중 모멘텀과 종가배팅을 시간대별로 분리할 때 사용.

### 3-1. 침착해 종가배팅 전략 (15:10~15:25)

침착해 원칙에 맞는 조건 — 이 시간대에만 적용:

| 조건 | 파라미터 | 권장값 |
|------|---------|--------|
| 신고가 돌파 필수 | `longHighCheckEnabled` | `true` |
| 거래량 폭증 | `volumeBurstMultiplier` | 2.0~3.0 |
| 강한 양봉 | `priceMoveMinPct` | 1.0 |
| 호가 imbalance | `orderbookImbalanceMin` | 2.0 |
| 진입 시간 | `entryAllowedFromHour/Minute` | 15:10 |

### 3-2. 장중 모멘텀 전략 (09:30~14:30 예시)

신고가 불필요, 거래량+방향성 중심:

| 조건 | 파라미터 | 권장 시작값 |
|------|---------|------------|
| 신고가 불필요 | `longHighCheckEnabled` | `false` |
| 거래량 moderate | `volumeBurstMultiplier` | 1.5 |
| 약한 양봉도 허용 | `priceMoveMinPct` | 0.3 |
| 호가 완화 | `orderbookImbalanceMin` | 1.3 |

> **현재 미구현**: 시간대별 전략 분기는 `EntryStrategy` 인터페이스 분리가 필요. 구현 전에 백테스트로 각 전략 유효성 먼저 확인.

---

## 4. 파라미터 변경 적용

### 4-1. application.yml 수정

```yaml
trading:
  longHighCheckEnabled: false     # 장중 모멘텀: false / 종가배팅: true
  volumeBurstMultiplier: 1.5      # 완화: 1.2~1.5 / 강화: 2.0~3.0
  priceMoveMinPct: 0.3            # 완화: 0.2~0.5 / 강화: 1.0
  orderbookImbalanceMin: 1.5      # 완화: 1.3~1.5 / 강화: 2.0
  entryAllowedFromHour: 0         # 0=비활성화 / 13=13:00 이후만
  entryAllowedFromMinute: 0
```

### 4-2. 재시작

```bash
./scripts/restart.sh
```

### 4-3. 즉시 검증 (다음 사이클 로그)

```bash
# 다음 CYCLE 이벤트 실시간 확인
tail -f backend/logs/stockapp.log | grep "CYCLE"
```

변경 후 skip 사유 분포가 기대한 방향으로 바뀌었는지 확인.

---

## 5. 에러 대응

### Retries exhausted 빈발 시

```bash
# 에러 발생 종목 패턴 확인
grep "evaluate failed" backend/logs/stockapp.log | grep "$(date +%Y-%m-%d)" | \
  sed 's/.*for //; s/:.*//' | sort | uniq -c | sort -rn | head -10
```

모의투자 API rate limit 가능성: `cycleDeadlineSec` 늘리거나 유니버스 축소.

```yaml
trading:
  cycleDeadlineSec: 300      # 240 → 300
  universeKospiTopN: 20      # 30 → 20
  universeKosdaqTopN: 20
```

---

## 6. 문서화

파라미터 변경 후 `docs/TRADING_STRATEGY.md` 업데이트:

```markdown
## 변경 이력

| 날짜 | 변경 파라미터 | 변경 전 | 변경 후 | 근거 |
|------|-------------|---------|---------|------|
| YYYY-MM-DD | volumeBurstMultiplier | 2.0 | 1.5 | 백테스트 WinRate +9% |
```

---

## 7. 전략 개선 흐름 요약

```
로그 분석 (skip 사유 분포)
  → 문제 파라미터 식별
  → 백테스트로 후보 파라미터 검증 (strategy-backtest 스킬)
  → Go/No-Go 판단
  → application.yml 수정
  → restart
  → 다음 사이클 로그로 변화 확인
  → docs/TRADING_STRATEGY.md 업데이트
```
