---
name: system-check
description: stockapp 자동매매 시스템 전체 상태 점검. 서버·세션·사이클·포지션·재료배치·에러를 종합 진단하고 구조화 리포트 출력. Use when "시스템 점검", "상태 점검", "상태 확인", "헬스 체크", "오늘 어때", "거래 현황", "재료 배치", "재료 확인" 등을 언급할 때.
---

# stockapp 시스템 상태 점검

전체 자동매매 시스템을 종합 점검하여 구조화된 리포트를 출력한다.

---

## 데이터 수집

2-Phase로 수집한다. 각 Phase 내 명령은 **최대한 병렬 실행**한다.

### Phase 1 — API + Config + 재료배치 (병렬)

```bash
# 1-1. 자동매매 상태 (올바른 경로: /api/trading/state)
curl -s http://localhost:8090/api/trading/state

# 1-2. 포지션
curl -s http://localhost:8090/api/positions

# 1-3. 잔고
curl -s http://localhost:8090/api/balance

# 1-4. 오늘 거래 내역 (날짜 포맷: YYYYMMDD BASIC_ISO_DATE)
curl -s "http://localhost:8090/api/trades?date=$(date +%Y%m%d)"

# 1-5. 미체결 주문
curl -s http://localhost:8090/api/orders/pending

# 1-6. application.yml 핵심 파라미터 확인
grep -A 30 "^trading:" backend/src/main/resources/application.yml

# 1-7. 재료 배치 프로세스 실행 여부
ps aux | grep "material_signal.*main.py" | grep -v grep

# 1-8. 재료 신호 DB 현황 (오늘 + 최근 24h 배치 주기별)
psql -U stockapp -d stockapp -c "
SELECT
  DATE_TRUNC('hour', captured_at AT TIME ZONE 'Asia/Seoul') AS hour_kst,
  COUNT(*) AS cnt,
  MAX(material_grade) AS max_grade
FROM material_signals
WHERE captured_at > NOW() - INTERVAL '24 hours'
GROUP BY 1 ORDER BY 1 DESC LIMIT 12;
"

# 1-9. 재료 등급 분포 (최근 24h)
psql -U stockapp -d stockapp -c "
SELECT material_grade, supply_signal, COUNT(*) AS cnt
FROM material_signals
WHERE captured_at > NOW() - INTERVAL '24 hours'
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;
"

# 1-10. 최신 Grade 4+ 종목 (최근 24h, 상위 10개)
psql -U stockapp -d stockapp -c "
SELECT symbol_code, MAX(material_grade) AS max_grade, COUNT(*) AS cnt,
  MAX(captured_at AT TIME ZONE 'Asia/Seoul') AS latest_kst
FROM material_signals
WHERE captured_at > NOW() - INTERVAL '24 hours' AND material_grade >= 4
GROUP BY 1 ORDER BY 2 DESC, 3 DESC LIMIT 10;
"
```

### Phase 2 — 로그 분석 (병렬)

로그 파일: `backend/logs/stockapp.log` (오늘 날짜)

```bash
TODAY=$(date +%Y-%m-%d)

# 2-1. 세션 시작/종료 이력
grep "\[Session\]" backend/logs/stockapp.log | grep "$TODAY"

# 2-2. CYCLE 이벤트 (skip 사유 분포 포함)
grep "CYCLE" backend/logs/stockapp.log | grep "$TODAY" | grep -v "사이클 완료" | tail -20

# 2-3. 진입 신호 발생 여부
grep "진입신호\|ENTRY\|EntrySignal" backend/logs/stockapp.log | grep "$TODAY"

# 2-4. GUARD 이벤트 (Circuit Breaker, Shock Exit)
grep "GUARD" backend/logs/stockapp.log | grep "$TODAY"

# 2-5. 에러 건수 + 최근 내용
grep "ERROR" backend/logs/stockapp.log | grep "$TODAY" | wc -l
grep "ERROR" backend/logs/stockapp.log | grep "$TODAY" | tail -5

# 2-6. Retries exhausted 패턴
grep "Retries exhausted" backend/logs/stockapp.log | grep "$TODAY" | wc -l

# 2-7. 최근 사이클 skip 사유 집계 (마지막 10사이클)
grep "CYCLE" backend/logs/stockapp.log | grep "$TODAY" | grep -v "사이클 완료" | tail -10
```

---

## 리포트 출력

### 섹션 1: 서버 상태

| 항목 | 소스 | 내용 |
|------|------|------|
| 구동 여부 | API 응답 성공/실패 | 구동 중 / 미구동 |
| 자동매매 활성 | `enabled` 필드 | ON / OFF |
| 마지막 사이클 | 로그 `[Candle] eval done` | KST 시각 |

API 실패 시 `ps aux | grep stockapp | grep -v grep`으로 프로세스 확인.

### 섹션 2: Config 요약

application.yml에서:

| 항목 | 키 |
|------|-----|
| 모드 | `ebest.mode` (mock/real) |
| 진입 금액 | `entryAmountWon` |
| 최대 동시 포지션 | `maxConcurrentPositions` |
| 신고가 필터 | `longHighCheckEnabled` |
| 거래량 배수 | `volumeBurstMultiplier` |
| 양봉 최소 % | `priceMoveMinPct` |
| 호가 최소 비율 | `orderbookImbalanceMin` |
| 시간대 필터 | `entryAllowedFromHour:Minute` (0:0=비활성) |
| 외국인수급 필터 | `foreignFlowMinPct` (0=비활성) |
| Circuit Breaker | `dailyLossLimitWon` |
| Shock Exit | `shockExitPct` |

### 섹션 3: 세션 현황

로그의 `[Session]` 이벤트에서:
- 오늘 세션 시작 시각
- 재시작 횟수 (mid-session restart 건수)
- 현재 유니버스 종목 수

### 섹션 4: 사이클 skip 사유 분포

최근 10사이클 CYCLE 이벤트에서 skip 사유 집계:

| Skip 사유 | 건수 | 비율 | 판단 |
|-----------|------|------|------|
| 신고가미달 | N | N% | longHighCheckEnabled 확인 |
| 양봉미달 | N | N% | 장세 불량 또는 조건 강함 |
| 거래량부족 | N | N% | volumeBurstMultiplier 확인 |
| 호가없음 | N | N% | WS 연결 또는 시간대 확인 |
| 시간대필터 | N | N% | 정상 (entryAllowedFrom 설정) |
| 비활성화 | N | N% | enabled=false 상태 |
| 최대보유 | N | N% | 포지션 한도 도달 |

### 섹션 5: 오픈 포지션

API positions 응답으로 테이블. 없으면 "현재 보유 포지션 없음".

있을 경우:

| 종목 | 진입가 | 현재가 | PnL | 보유시간 | HWM |
|------|--------|--------|-----|---------|-----|

`positionCountWarnAt` 임계 초과 시 경고 표시.

### 섹션 6: 오늘 거래

trades API 응답 파싱:
1. **라운드트립 테이블**: BUY→SELL 짝 매칭, 종목/시각/PnL
2. **합계**: 총 거래수, 총 PnL, 승/패

거래 없으면 "오늘 거래 없음 — skip 사유 확인 필요".

### 섹션 7: GUARD 이벤트

Circuit Breaker, Shock Exit 발동 여부:
- `circuit breaker 발동` 이력
- `shock exit` 발동 종목/가격

없으면 "GUARD 이벤트 없음".

### 섹션 8: 재료 배치 현황

#### 8-1. 배치 프로세스 상태

`ps aux | grep material_signal` 결과:
- 프로세스 존재 → `구동 중 (PID NNN, 시작: HH:MM)`
- 없으면 → `⚠ 배치 미실행` (수동 시작 필요)

배치 설정: `BATCH_INTERVAL_MINUTES` (기본 30분), `backend/scripts/material_signal_batch/config.py` 참조.

#### 8-2. 오늘 재료 신호 수집 현황

DB `material_signals` 테이블 기반:

| 시간대(KST) | 수집 건수 | 최고 등급 | 판단 |
|------------|---------|---------|------|
| HH:00 | N | N | 정상/이상 |

30분 간격 기준: 연속 2개 시간대 이상 수집 없으면 배치 장애 의심.

#### 8-3. 등급 분포 (최근 24h)

| Grade | 설명 | 건수 | 수급신호 |
|-------|------|------|---------|
| 5 | 최상위 재료 | N | - |
| 4 | 강한 재료 | N | - |
| 3 | 보통 재료 | N | - |
| 2 | 약한 재료 | N | - |
| 1 | 미미한 재료 | N | - |

Grade 3+ 비율 = (Grade3+4+5) / 전체 × 100%. 정상 범위: 30~60%.

#### 8-4. 주목 종목 (Grade 4+ 최근 24h)

| 종목코드 | 최고등급 | 건수 | 최신 수집 |
|---------|---------|------|---------|

유니버스에 포함된 종목 중 Grade 4+ 존재 시 → 진입 조건 충족 가능성 언급.

#### 8-5. 배치 건강 판단

수집 공백 자체는 오탐 원인이 될 수 있음 — 기사 공백 구간(새벽 2~8시, 장 중 뉴스 없는 시간)은 정상적으로 insert가 0건일 수 있음.
**프로세스 생존 여부**가 핵심 지표고, 수집 건수는 참고값으로만 사용한다.

| 상태 | 조건 |
|------|------|
| 정상 | 프로세스 구동 중 + 오늘 수집 이력 있음 (시간 무관) |
| 주의 | 프로세스 구동 중 + 오늘 수집 0건 (기사 없거나 분류기 오류 가능) |
| 장애 | 프로세스 미실행 |

수집 0건 + 프로세스 정상 → ON CONFLICT skip(중복 기사) 또는 크롤러 기사 없음으로 **정상 동작 가능**. 판단 보류하고 "기사 공백 가능성" 메모만 표시.

### 섹션 9: 에러/경고

| 유형 | 건수 |
|------|------|
| ERROR | N |
| Retries exhausted | N |

최근 ERROR 5건 표시 (timestamp + 내용 요약).

Retries exhausted 빈발(사이클당 5건+) 시:
> ⚠ API rate limit 또는 모의투자 서버 불안정 가능성. `cycleDeadlineSec` 늘리기 또는 유니버스 축소 권장.

### 섹션 10: 종합 판단

전 섹션 결과를 종합하여 4단계 판정:

| 판정 | 조건 |
|------|------|
| **CRITICAL** | 서버 미구동 OR Circuit Breaker 발동(enabled=false) |
| **WARNING** | 사이클당 에러 5건+ OR 전체 skip 사유 1종 >90% OR 배치 프로세스 미실행 |
| **CAUTION** | 오늘 거래 0건 + 진입 조건 미달 多 |
| **OK** | 위 조건 해당 없음 |

판정 후 핵심 발견사항 bullet point + 권장 조치.

---

## 출력 템플릿

```
## 시스템 상태 점검 — {YYYY-MM-DD}

### 1. 서버 상태
- Backend: {구동 중 / 미구동} | 자동매매: {ON / OFF}
- 마지막 사이클: {HH:MM KST}

### 2. Config 요약
| 항목 | 값 |
| ebest.mode | mock / real |
| 신고가 필터 | true / false |
| 거래량 배수 | N.N |
| 양봉 최소 % | N.N |
| 진입 허용 시간 | HH:MM 이후 / 비활성 |
| 재료+수급 점수 | N (0=비활성) |

### 3. 세션 현황
- 시작: {HH:MM} | 재시작: {N}회 | 유니버스: {N}종목

### 4. Skip 사유 분포 (최근 10사이클)
| 사유 | 건수 | 비율 |

### 5. 오픈 포지션 ({N}개)
{포지션 테이블 or "없음"}

### 6. 오늘 거래 ({N}건)
{라운드트립 or "없음"}
총 PnL: {+/-N}원

### 7. GUARD 이벤트
{이력 or "없음"}

### 8. 재료 배치 현황
- 프로세스: {구동 중 (PID NNN) / 미실행 ⚠}
- 오늘 수집: {N}건 | 최신: {HH:MM KST} | 배치 상태: {정상/지연/장애}
- Grade 분포: 5={N} 4={N} 3={N} 2={N} 1={N}
- Grade 4+ 주목 종목: {종목코드(등급)} ...

### 9. 에러/경고
ERROR: {N}건 | Retries: {N}건
{최근 에러 요약}

### 10. 종합: {OK / CAUTION / WARNING / CRITICAL}
- {발견사항 1}
- {권장 조치}
```

---

## 엣지 케이스

| 상황 | 처리 |
|------|------|
| API 실패 (서버 미구동) | CRITICAL + 로그 기반 정보만 출력 |
| 오늘 로그 없음 | "서버 금일 미구동" — 섹션 4, 7, 8, 9 skip |
| 사이클 완료 로그만 있음 (구형 포맷) | "재시작 전 구형 포맷 — skip 사유 없음. 재시작 후 로그 필요" |
| 거래 0건 + CAUTION | strategy-improvement 스킬 실행 권장 |
| Retries 건수 > 사이클 × 5 | API rate limit WARN + 유니버스 축소 권장 |
| 재료 배치 프로세스 미실행 | `cd backend/scripts/material_signal_batch && python main.py &` 실행 안내 |
| DB에 오늘 재료 없음 + 프로세스 실행 중 | `/api/universe` 응답 여부 확인 (배치가 종목 목록 조회 실패 가능) |
| Grade 4+ 종목이 유니버스에 있으나 진입 없음 | `supplyMaterialMinScore` 설정값 확인 (0=비활성화면 재료 조건 무관) |

## API 경로 정오표 (스킬 사용 시 주의)

| 잘못된 경로 | 올바른 경로 |
|------------|------------|
| `/api/auto-trading/state` | `/api/trading/state` |
| `/api/trades?from=YYYY-MM-DD` | `/api/trades?date=YYYYMMDD` (BASIC_ISO_DATE) |
