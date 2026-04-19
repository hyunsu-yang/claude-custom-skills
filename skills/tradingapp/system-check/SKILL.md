---
name: system-check
description: 자동매매 시스템 전체 상태 점검 (V1/V2/V3 엔진 자동 감지). 서버, 엔진, 레짐, 포지션, 거래, 스캐너, 서지, 에러를 종합 진단하고 구조화 리포트 출력. Use when "시스템 점검", "상태 점검", "상태 확인", "시스템 체크", "헬스 체크", "system check", "health check".
---

# 시스템 상태 점검

전체 자동매매 시스템을 종합 점검하여 구조화된 리포트를 출력한다.
**엔진 버전(V1/V2/V3)을 자동 감지**하여 해당 엔진에 맞는 점검을 수행한다.

## 엔진별 아키텍처 차이

| | V1 (Classic) | V2 (MVTS) | V3 (Event-Driven) |
|--|---|---|---|
| 스케줄링 | 10초 setInterval | 10초 setInterval | 캔들 마감 타이머 + 틱 이벤트 |
| 로그 태그 | `ENGINE` | `ENGINE-V2` | `ENGINE-V3` |
| 손절 반응 | 10초 폴링 | 10초 폴링 | 매 틱 실시간 (<1초) |
| 주문 흐름 | 없음 | 없음 | 매수세/매도세 분석 |
| Flow Alpha | 없음 | 없음 | TFI/VWAP/Accel 연속 시그널 |
| ML Pipeline | 없음 | 없음 | Feature Snapshot + Triple Barrier 라벨링 |
| 추가 컴포넌트 | — | — | Exit Monitor, Order Flow, Flow Alpha, Trade WS, Candle Builder |

---

## 데이터 수집

2-Phase로 데이터를 수집한다. 각 Phase 내 명령은 **최대한 병렬 실행**한다.

### Phase 1 — API + 파일 (병렬)

서버가 구동 중이면 API로 실시간 상태를 조회한다. API 실패 시 서버 미구동으로 판단.

```bash
# 1-1. API 상태 조회
curl -s http://localhost:3001/api/auto/status

# 1-2. 오픈 포지션
curl -s http://localhost:3001/api/auto/positions

# 1-3. Config
cat backend/config/trading.json

# 1-4. 스캔 결과
cat backend/data/scan-results.json

# 1-5. 오늘 거래 내역 (YYYYMMDD는 오늘 날짜)
cat backend/data/trade-history-YYYYMMDD.json
```

**API status 응답 주요 필드:**
- `enabled`, `paperMode`, `intervalSeconds`
- `lastRunAt`, `pausedByError`, `consecutiveFailures`
- `totalTradesToday`, `todayPnlKrw`
- `paperBalanceKrw`, `paperInitialKrw` (paper mode)
- `globalRegime` → `{ regime, label, confidence }`
- `symbolConditions` → `{ "KRW-BTC": "trending_down", ... }`
- `entryHints` → `{ "KRW-BTC": "BB 높음", ... }` (V2/V3)
- `filterProfiles` → `{ "KRW-BTC": "mr_deep", ... }` (V2/V3, v9.3) — 종목별 활성 필터 프로파일
- `surgeDetection` → 서지 감지 상태
- `coinRanking` → 스캐너 랭킹

**V3 전용 필드 (engineV3):**
- `engineV3.started` — V3 엔진 구동 여부
- `engineV3.evaluationCount` — 캔들 마감 평가 횟수
- `engineV3.exitMonitor` — 실시간 스탑 모니터링 상태 (활성 포지션)
- `engineV3.orderFlows` — 종목별 주문 흐름 (`buyRatio`, `tradeCount`, `intensity`)

**V4 ML Pipeline 데이터:**
- `backend/data/feature-snapshots-YYYYMMDD.json` — 진입 시 자동 기록되는 ML 학습용 피처 스냅샷
- 매도 시 `tripleBarrier.labelFromExit()`로 자동 라벨링 (profit/loss/time/early_exit)

**API positions 응답:** 포지션 배열 (종목, 매수가, 현재가, PnL 등)

### Phase 2 — 로그 분석 (병렬, Phase 1 보완)

로그 파일: `backend/logs/auto-YYYYMMDD.log` (JSON lines)

**엔진 자동 감지**: Phase 1에서 config의 `engineVersion` 확인 후 해당 엔진 로그만 분석.

#### V1 엔진 로그

```bash
grep 'ENGINE ' backend/logs/auto-YYYYMMDD.log | tail -15
```

#### V2 엔진 로그

```bash
# 2-1. 진입 차단 사유별 카운트 (각각 병렬)
grep -c 'condition=trending_down' backend/logs/auto-YYYYMMDD.log
grep -c 'crash guard' backend/logs/auto-YYYYMMDD.log
grep -c 'falling knife guard' backend/logs/auto-YYYYMMDD.log
grep -c 'post-spike pullback' backend/logs/auto-YYYYMMDD.log
grep -c 'blocked by global regime' backend/logs/auto-YYYYMMDD.log

# 2-2. 최근 엔진 활동
grep 'ENGINE-V2' backend/logs/auto-YYYYMMDD.log | tail -15
```

#### V3 엔진 로그

```bash
# 3-1. 진입 차단 사유별 카운트 (V2와 동일 + V3 전용)
grep -c 'condition=trending_down' backend/logs/auto-YYYYMMDD.log
grep -c 'crash guard' backend/logs/auto-YYYYMMDD.log
grep -c 'falling knife guard' backend/logs/auto-YYYYMMDD.log
grep -c 'post-spike pullback' backend/logs/auto-YYYYMMDD.log
grep -c 'blocked by global regime' backend/logs/auto-YYYYMMDD.log
grep -c '매도세 우위' backend/logs/auto-YYYYMMDD.log
grep -c 'VPIN 높음' backend/logs/auto-YYYYMMDD.log

# 3-2. 최근 엔진 활동
grep 'ENGINE-V3' backend/logs/auto-YYYYMMDD.log | tail -15

# 3-3. V3 컴포넌트 상태
grep 'EXIT-MONITOR' backend/logs/auto-YYYYMMDD.log | tail -5
grep 'ORDER-FLOW' backend/logs/auto-YYYYMMDD.log | tail -5
grep 'WS-TRADE' backend/logs/auto-YYYYMMDD.log | tail -10
grep 'RT-CANDLES' backend/logs/auto-YYYYMMDD.log | tail -5

# 3-4. V4 Flow Alpha + ML Pipeline
grep 'alpha boost' backend/logs/auto-YYYYMMDD.log | tail -5
grep 'FEATURE-SNAPSHOT' backend/logs/auto-YYYYMMDD.log | tail -5
grep -c 'alpha boost' backend/logs/auto-YYYYMMDD.log
grep -c 'FEATURE-SNAPSHOT' backend/logs/auto-YYYYMMDD.log
```

#### 공통 로그 (모든 엔진)

```bash
# ERROR/WARN 카운트 + 최근 항목
grep -c '"level":"ERROR"' backend/logs/auto-YYYYMMDD.log
grep -c '"level":"WARN"' backend/logs/auto-YYYYMMDD.log
grep '"level":"ERROR"' backend/logs/auto-YYYYMMDD.log | tail -5
grep '"level":"WARN"' backend/logs/auto-YYYYMMDD.log | tail -5

# Surge 감지 이력
grep 'SURGE-DETECTOR.*Stage' backend/logs/auto-YYYYMMDD.log | tail -5

# Scanner 활동
grep 'SCAN-SCHEDULER' backend/logs/auto-YYYYMMDD.log | tail -5
```

---

## 리포트 출력

수집된 데이터를 아래 섹션으로 정리하여 **마크다운** 리포트를 출력한다.

### 섹션 1: 서버 상태

| 항목 | 소스 | 내용 |
|------|------|------|
| 구동 여부 | API 응답 성공/실패 | "구동 중" or "미구동" |
| Last tick | `lastRunAt` | KST 변환 |
| 상태 | `pausedByError` | 정상 / 에러 일시정지 |
| 연속 실패 | `consecutiveFailures` | 0이 아니면 표시 |

API 실패 시 `ps aux | grep 'node.*backend' | grep -v grep`로 프로세스 확인.

### 섹션 2: Config 요약

trading.json에서 추출:

| 항목 | 키 |
|------|-----|
| Engine | `engineVersion` (V1/V2/V3) + `engineV2.strategy` (V2/V3) |
| Mode | `paperMode` (true→paper, false→live) |
| 잔고 | `paperBalanceKrw` / `paperInitialKrw` (paper mode) |
| 매매 주기 | V1/V2: `intervalSeconds`초 / V3: 캔들 마감 기반 (이벤트) |
| 캔들 단위 | `candleUnit` |
| 종목 수 | `tradingSymbols.length` / `maxTradingSymbols` |
| 스캔 주기 | `autoScanInterval` |

**V3 추가 표시:**
| 항목 | 내용 |
|------|------|
| 평가 방식 | 캔들 마감 정렬 (5분 정각 + 1.5초 버퍼) |
| 스탑 평가 | 매 틱 실시간 (Exit Monitor) |
| 주문 흐름 | 1분 롤링 매수/매도 비율 |

### 섹션 3: Global Regime

API `globalRegime`에서:

| 레짐 | 매수 | MR | 사이즈 | 의미 |
|------|------|-----|--------|------|
| bull | O | O | 1.5x | BTC 강세, 적극 매매 |
| neutral | O | O | 1.0x | 기본 상태 |
| bear | O | X | 0.5x | MR 차단, 축소 운영 |
| crisis | X | X | 0x | 매수 전면 차단 |

현재 레짐 + confidence를 표시하고, 매매 영향을 한 줄로 설명한다.

### 섹션 4: 종목 Condition 분포

API `symbolConditions` 값을 집계:

| Condition | 수 | 비율 | 선택 전략 |
|-----------|---|------|----------|
| trending_up | N | N% | Trend Following |
| ranging | N | N% | Mean Reversion |
| trending_down | N | N% | (skip — 진입 불가) |

API 미사용 시 로그에서 최근 tick의 condition 분포를 추출한다.

### 섹션 5: 진입 차단 현황

Phase 2의 grep 카운트로 테이블 구성:

| 사유 | 오늘 건수 |
|------|----------|
| trending_down (no strategy) | N |
| 24h crash guard | N |
| falling knife guard | N |
| post-spike pullback guard | N |
| global regime gate | N |

**V3 추가 항목:**

| 사유 | 오늘 건수 |
|------|----------|
| 매도세 우위 (Order Flow 차단) | N |
| VPIN 높음 (정보거래 차단) | N |

### 섹션 5-1: Entry Hints (V2/V3)

API `entryHints`에서 종목별 현재 진입 차단 사유:

| 종목 | 힌트 |
|------|------|
| KRW-XXX | {차단 사유 or 빈 문자열(진입 가능)} |

빈 값인 종목 = 진입 조건 대기 중 (차단 없음).

### 섹션 5-2: Filter Profiles (V2/V3, v9.3)

API `filterProfiles`에서 종목별 활성 필터 프로파일:

| 종목 | 프로파일 | 설명 |
|------|---------|------|
| KRW-XXX | tf_strong / tf_moderate / tf_volume / mr_deep / mr_standard / mr_uptrend | 현재 적용 중인 프로파일 |

프로파일별 의미:
- `tf_strong` (ADX>35): 강한 추세 — emaGap/vol 완화
- `tf_moderate` (기본 TF): 전체 필터 적용
- `tf_volume` (RVOL>2): 거래량 기반 추세 — ADX/DI 완화
- `mr_deep` (BB<5): 극과매도 — 강세캔들/vol 면제
- `mr_standard` (기본 MR): 전체 확인 필터 적용
- `mr_uptrend` (trending_up): 상승 풀백 — BB/RSI 완화

### 섹션 6: 오픈 포지션

API positions 응답으로 테이블. 포지션이 없으면 "현재 오픈 포지션 없음".

있을 경우:

| 종목 | 매수가 | 현재가 | PnL | 보유시간 | 전략 |
|------|--------|--------|-----|---------|------|

**V3 추가**: 포지션이 있으면 `engineV3.exitMonitor`에서 해당 종목의 스탑 레벨 표시 (ATR 스탑, 트레일링 스탑).

### 섹션 7: 오늘 거래

trade-history JSON을 파싱하여:

1. **라운드트립 테이블**: bid→ask 짝 매칭, 종목/시간/전략/PnL
2. **전략별 breakdown**: 전략별 거래수, 승률, PnL 합계
3. **합계**: 총 거래수, 총 PnL, 승/패

거래 없으면 "오늘 거래 없음".

라운드트립 매칭:
```javascript
// trade-history에서 bid/ask를 순서대로 짝 맞춤
// bid의 meta.strategy, meta.globalRegime 참조
// PnL = (ask price × volume) - (bid price × volume)
```

### 섹션 8: Scanner 상태

scan-results.json에서:
- 마지막 스캔 시각 (`timestamp`)
- 스캔 봉 (`timeframe`)
- Top-10 종목 (market, score, regime)

로그에서 최근 SCAN-SCHEDULER 활동도 포함.

### 섹션 9: Surge Detector

API `surgeDetection`에서 활성 서지 여부.
로그에서 최근 Stage 1/2 감지 이력.

활성 서지가 없으면 "활성 서지 없음". 최근 감지 이력만 표시.

### 섹션 10: V3 컴포넌트 상태 (V3 전용)

> **V1/V2에서는 이 섹션 생략.**

V3 엔진은 4개 핵심 컴포넌트로 구성된다. 각각의 상태를 점검한다.

#### 10-1. Trade WebSocket

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| 연결 상태 | WS-TRADE 로그 | `Connected, subscribing to N markets` 최근 발생 |
| 재접속 빈도 | `Reconnecting` 카운트 | 시간당 2회 이하 |
| 구독 마켓 수 | `subscribing to N markets` | tradingSymbols 수와 일치 |

#### 10-2. Exit Monitor

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| 활성 포지션 | `engineV3.exitMonitor` | 오픈 포지션과 일치 |
| 매도 실행 | EXIT-MONITOR 로그 | SELL 이벤트가 포지션 매도와 매칭 |

#### 10-3. Order Flow

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| 데이터 수신 | `engineV3.orderFlows` | tradingSymbols 대부분에 데이터 존재 |
| trade 수 | 종목별 `tradeCount` | 0이 아닌 종목이 대다수 |
| buyRatio 범위 | 종목별 `buyRatio` | 0.0~1.0 범위, 대부분 0.3~0.7 |

Order Flow 요약 테이블:

| 종목 | buyRatio | tradeCount | intensity | 판단 |
|------|----------|------------|-----------|------|
| KRW-BTC | 0.67 | 60 | 1.24 | 매수세 우위 |
| KRW-XRP | 0.45 | 16 | 0.85 | 균형 |
| ... | | | | |

buyRatio 판단:
- `>= 0.65`: 강한 매수세 (conviction boost)
- `0.35~0.65`: 균형
- `< 0.35`: 강한 매도세 (진입 차단)

#### 10-4. Candle Builder

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| 캔들 마감 | RT-CANDLES 로그 | 5분 간격으로 `candleClose` 발생 |
| 에러 | RT-CANDLES ERROR | 없어야 함 |

#### 10-5. Flow Alpha (V4)

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| alpha boost 발생 | `alpha boost` 로그 | 진입 시 tfiAlpha>0.3 + vwapSpread>0일 때 부스트 |
| boost 빈도 | `grep -c 'alpha boost'` | 진입 시그널 대비 적절한 비율 (10-30%) |

#### 10-6. ML Pipeline (V4)

| 항목 | 확인 방법 | 정상 기준 |
|------|----------|----------|
| 스냅샷 기록 | FEATURE-SNAPSHOT 로그 | 매 진입 시 기록, 매 매도 시 라벨링 |
| 축적 현황 | `feature-snapshots-*.json` 파일 | 일별 파일 존재, 총 샘플 수 증가 |
| 라벨 분포 | 로그의 labelReason | profit/loss/time/early_exit 분포 확인 |

ML 데이터 축적 요약:
```bash
node -e "const fs=require('fs'); const files=fs.readdirSync('backend/data').filter(f=>f.startsWith('feature-snapshots-')); let total=0,labeled=0; files.forEach(f=>{const d=JSON.parse(fs.readFileSync('backend/data/'+f));total+=d.length;labeled+=d.filter(s=>s.label!=null).length}); console.log('Files:',files.length,'Total:',total,'Labeled:',labeled)"
```

### 섹션 11: 에러/경고

| 유형 | 건수 |
|------|------|
| ERROR | N |
| WARN | N |

최근 ERROR/WARN 항목 최대 5건씩 표시 (timestamp, category, message).

### 섹션 12: 종합 판단

전 섹션 결과를 종합하여 **4단계 판정**:

| 판정 | 조건 |
|------|------|
| **CRITICAL** | 서버 미구동 OR `pausedByError=true` OR crisis 레짐 |
| **WARNING** | trending_down >80% + 오늘 0 거래 OR ERROR 10건 이상 |
| **CAUTION** | bear 레짐 OR trending_down >50% OR 일일 PnL 대폭 마이너스 |
| **OK** | 위 조건 해당 없음 (정상 운영) |

**V3 추가 판정 기준:**

| 판정 | 조건 |
|------|------|
| **CRITICAL** | Trade WS 미연결 + Order Flow 데이터 없음 |
| **WARNING** | WS 재접속 빈번 (시간당 5회+) OR Order Flow 데이터 50% 미만 종목 |
| **CAUTION** | Exit Monitor 포지션 불일치 (오픈 포지션 있는데 exitMonitor 비어있음) |

판정 후 핵심 발견사항을 bullet point로 나열한다.

---

## 엣지 케이스

| 상황 | 처리 |
|------|------|
| API 실패 (서버 미구동) | "서버 미구동" CRITICAL + 파일/로그 기반 가용 정보만 점검 |
| 오늘 로그 파일 없음 | 섹션 5, 10, 11 skip + "오늘 로그 없음. 서버 금일 미구동 가능" |
| 거래 내역 파일 없음 | 섹션 7 "오늘 거래 없음" |
| scan-results.json 없음 | 섹션 8 "스캐너 미실행" |
| symbolConditions 비어있음 | "엔진 첫 평가 대기 중" |
| V3인데 engineV3 필드 없음 | "V3 엔진 초기화 중" |
| V3 WS-TRADE 로그 없음 | "Trade WebSocket 미연결" WARNING |

---

## 출력 템플릿

### V1/V2 템플릿

```
## 시스템 상태 점검 — {YYYY-MM-DD}

### 1. 서버 상태
- Backend: {구동 중 / 미구동} (last tick: {HH:MM KST})
- 상태: {정상 / 에러 일시정지 (consecutiveFailures: N)}

### 2. Config 요약
| 항목 | 값 |
|------|-----|
| Engine | {V1/V2} / strategy={auto} |
| Mode | {paper/live} (잔고: {N}원 / 초기: {N}원) |
| 매매 주기 | {N}초 / {N}분봉 |
| 종목 | {N}개 / 최대 {N}개 |

### 3. Global Regime: {regime}
{레짐별 매매 영향 한 줄 설명}

### 4. 종목 Condition 분포
| Condition | 수 | 비율 |
|-----------|---|------|

### 5. 진입 차단 현황
| 사유 | 건수 |
|------|------|

### 6. 오픈 포지션
{포지션 테이블 or "없음"}

### 7. 오늘 거래 ({N}건)
{라운드트립 테이블}
총 PnL: {+/-N}원

### 8. Scanner
마지막 스캔: {시각} ({timeframe}) | Top: {종목1}({점수}), {종목2}({점수}), ...

### 9. Surge Detector
{활성 서지 정보 or "활성 서지 없음"}

### 10. 에러/경고
ERROR: {N}건 | WARN: {N}건

### 11. 종합: {OK / CAUTION / WARNING / CRITICAL}
- {발견사항 1}
- ...
```

### V3 템플릿

```
## 시스템 상태 점검 — {YYYY-MM-DD}

### 1. 서버 상태
- Backend: {구동 중 / 미구동} (last evaluation: {HH:MM KST}, #{N})
- 상태: {정상 / 에러 일시정지}

### 2. Config 요약
| 항목 | 값 |
|------|-----|
| Engine | V3 (Event-Driven) / strategy={auto} |
| Mode | {paper/live} (잔고: {N}원 / 초기: {N}원) |
| 평가 주기 | 캔들 마감 기반 ({N}분봉 정각 + 1.5초 버퍼) |
| 스탑 평가 | 매 틱 실시간 (Exit Monitor) |
| 종목 | {N}개 / 최대 {N}개 |

### 3. Global Regime: {regime}
{레짐별 매매 영향 한 줄 설명}

### 4. 종목 Condition 분포
| Condition | 수 | 비율 |
|-----------|---|------|

### 5. 진입 차단 현황
| 사유 | 건수 |
|------|------|
| trending_down | {N} |
| crash guard | {N} |
| falling knife | {N} |
| post-spike pullback | {N} |
| global regime gate | {N} |
| 매도세 우위 (Order Flow) | {N} |

### 5-1. Entry Hints
| 종목 | 힌트 |
|------|------|

### 6. 오픈 포지션
{포지션 테이블 or "없음"}

### 7. 오늘 거래 ({N}건)
{라운드트립 테이블}
총 PnL: {+/-N}원

### 8. Scanner
마지막 스캔: {시각} ({timeframe}) | Top: {종목1}({점수}), ...

### 9. Surge Detector
{활성 서지 정보 or "활성 서지 없음"}

### 10. V3 컴포넌트 상태

#### Trade WebSocket
- 연결: {Connected / Disconnected} ({N}개 마켓 구독)
- 재접속: 오늘 {N}회

#### Exit Monitor
- 활성 포지션: {N}개
{스탑 레벨 테이블 (포지션이 있을 경우)}

#### Order Flow
| 종목 | buyRatio | trades | intensity | 판단 |
|------|----------|--------|-----------|------|
{상위 5개 종목}

#### Candle Builder
- 마지막 캔들 마감: {HH:MM KST}
- 상태: {정상 / 에러}

### 11. 에러/경고
ERROR: {N}건 | WARN: {N}건

### 12. 종합: {OK / CAUTION / WARNING / CRITICAL}
- {발견사항 1}
- ...
```
