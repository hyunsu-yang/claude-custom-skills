# Arch Doc — 코드베이스 → 아키텍처 문서 (C4)

코드를 읽어서 아키텍처/설계 문서를 만든다. Simon Brown의 **C4 모델**(Context → Container
→ Component → Code) 기반, 출력은 Mermaid 다이어그램 + Markdown.

`$ARGUMENTS`로 대상 경로나 요청을 받는다. 없으면 현재 프로젝트를 대상으로 한다.

> 별칭: `/c4` — 같은 동작. 이름이 기억나는 쪽으로 호출.

## 실행 방법

`c4-model` 스킬을 사용한다 (`~/.claude/skills/c4-model/`). Skill 툴로 호출하거나,
아래 순서로 직접 진행한다.

### 1. 모드 판단

| 상황 | 참조 파일 |
|------|-----------|
| **기존 코드베이스 문서화** (대부분 이 경우) | `mode-document-code.md` |
| 신규 시스템 설계 (코드 없음) | `mode-design.md` |
| README/ADR/스펙 문서에서 추출 | `mode-document-prose.md` |
| 기존 다이어그램 리뷰/설명 | `mode-review.md` |
| 기존 C4 문서 갱신 | `mode-update.md` |

`$ARGUMENTS`에 경로가 있거나 "문서화/documentation" 계열이면 document-code.
불확실하면 사용자에게 묻는다.

해당 mode 파일을 `Read`로 로드한 뒤 그 절차를 따른다.

### 2. 시작 전 확인 (최대 3개)

1. **스코프** — 레포 전체 vs 특정 서브폴더 (모노레포면 필수 확인)
2. **레벨** — Context + Container가 기본. Component(레벨 3)는 요청 시에만
3. **출력 위치** — 기본 `docs/architecture/`. 파일명은 `c4-context.md`,
   `c4-container.md` 형태

`$ARGUMENTS`에서 이미 답이 나온 항목은 다시 묻지 않는다.

### 3. 스캔

**50파일 초과 또는 낯선 스택이면 `Agent` 툴 `subagent_type: Explore`로 위임한다.**
메인 컨텍스트를 사용자와의 대화용으로 비워두기 위함. 프롬프트는
`mode-document-code.md`의 인벤토리 프롬프트를 사용.

작은 레포는 `Glob`/`Grep`/`Read`로 직접.

읽을 것: README·ARCHITECTURE.md·docs/, docker-compose·k8s 매니페스트,
빌드 파일(package.json/pom.xml/build.gradle/pyproject.toml), Dockerfile·기동 스크립트,
마이그레이션·SQL 스키마, 메시징 설정, `.env.example`(**`.env` 아님 — 비밀정보 읽지 않음**),
외부 SDK/HTTP 클라이언트.

### 4. 발견 내용 먼저 제시

다이어그램을 그리기 전에 raw 목록으로 보여주고 확인받는다:

- 후보 Container (기술 스택 포함)
- 외부 의존성 (`System_Ext`)
- 식별된 플로우 (프로토콜 포함)
- **불확실한 플로우** / **모호한 점**

"이 구조가 맞나요? 빠진 게 있나요?" 확인 후 진행.

### 5. 초안 → 반복 → 확정

Context + Container를 선택한 형식으로 작성. `review-checklist.md` 적용 후 저장.

## 반드시 지킬 것

- **추론은 Assumptions 섹션으로 분리** — 코드에서 유추한 것(예: 마이그레이션 파일로
  PostgreSQL 판단)을 다이어그램에 몰래 넣지 않는다. 확인받지 못한 건 전부
  *Assumptions*에 적는다.
- **빈칸을 상상으로 채우지 않는다** — 모르는 건 사용자에게 묻거나 Assumptions로.
- **사용자 승인 전에 최종 파일을 쓰지 않는다.**
- Container에 기술 스택 명시 (C4 필수 규칙). 화살표 라벨은 "Uses"/"Calls" 같은
  무의미한 것 대신 의도를 서술.
- 한 다이어그램에 추상화 레벨 섞지 않기.

## 참고

- 스킬 전문: `~/.claude/skills/c4-model/SKILL.md`
- Mermaid C4 문법: `mermaid-c4-syntax.md`
- 작성 예시: `examples/01-context.example.md`, `examples/02-container.example.md`
- 출처/감사 기록: `PROVENANCE.md` (외부 유래 스킬)
