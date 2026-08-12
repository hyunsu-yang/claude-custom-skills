# Provenance — c4-model

이 레포의 유일한 **외부 유래(vendored)** 스킬. 나머지는 전부 자작.

- **출처**: https://github.com/cheriftj/c4-model-skill
- **고정 커밋(vendor 기준점)**: `5b24dda00b38a402da59237a8b8685aaa588a07e` (2026-04-25)
- **라이선스**: MIT — Copyright (c) 2026 Cherif Toujeni (재배포 시 저작권 표시 유지)
- **vendor 일시**: 2026-08-13
- **가져온 범위**: upstream `skills/c4-model/` + 루트 `LICENSE` → `LICENSE.upstream`
- **제외**: upstream `commands/` (플러그인 전용 경로라 심볼릭 링크 설치에선 동작 안 함), `tests/`(`.sh`)

`LICENSE.upstream`은 MIT 재배포 조건(저작권 표시 + 라이선스 전문 포함) 충족을 위한
원본 전문 — 이 레포가 공개 레포이므로 필수. 수정하지 말 것.

## marketplace 대신 vendoring한 이유

`/plugin install`은 검토 없는 자동 업데이트 경로를 연다. 업스트림은 저자 1인이
이틀간(2026-04-24~25) 만든 10커밋 레포이고 이후 방치 상태 — 지금 커밋은 감사했지만
미래 커밋은 감사할 수 없다. vendoring하면 우리가 읽은 내용에 고정되고, 커스터마이징도
자유롭다.

## vendor 시점 감사 결과 (커밋 5b24dda)

전량 마크다운 1,291줄, 실행 코드 없음.

- 네트워크 호출 없음 — URL은 c4model.com / mermaid.js.org 인용 링크뿐
- 훅 선언 없음, MCP 서버 정의 없음 (연결된 Notion/Linear에 *출력*만 언급)
- 비밀정보 접근 없음 — `.env`가 아닌 `.env.example`만, "secrets masked" 명시
- 난독화(base64/eval/exec) 없음

**로컬 수정 시 이 파일에 "## 로컬 수정" 항목으로 기록** — 업스트림 대비 diff 기준점이 흐려지지 않게.

## 업스트림 변경 확인

```bash
git clone https://github.com/cheriftj/c4-model-skill /tmp/c4-upstream
diff -ru /tmp/c4-upstream/skills/c4-model skills/global/c4-model \
  --exclude=PROVENANCE.md
```

diff를 직접 읽고 판단한 뒤 반영. 자동 pull 하지 않는다.

## 사용법

`commands/`를 가져오지 않았으므로 `/c4m:code` 같은 슬래시 커맨드는 없다.
자연어로 트리거 (SKILL.md description에 프로액티브 트리거 포함):

> "C4로 코드베이스 문서화해줘" / "아키텍처 다이어그램 만들어줘"

모드 5종 (`SKILL.md` 하단 "Bundled references" 참고):

| 파일 | 용도 |
|------|------|
| `mode-document-code.md` | 기존 레포 역문서화 (50파일 초과 시 Explore 서브에이전트 위임) |
| `mode-design.md` | 신규 시스템 설계 (5단계 대화) |
| `mode-document-prose.md` | README/ADR/스펙에서 추출 |
| `mode-review.md` | 기존 다이어그램 비평 |
| `mode-update.md` | 기존 C4 갱신 |

## 슬래시 커맨드 (자체 작성)

upstream `commands/`는 가져오지 않고, 이 레포에서 직접 작성했다:

- `commands/arch-doc.md` → `/arch-doc` (주 진입점)
- `commands/c4.md` → `/c4` (별칭)

"C4"라는 용어를 잊어도 `/arch-doc`("아키텍처 문서")로 찾을 수 있게 하려는 의도.
upstream 래퍼와 달리 스킬 파일 경로를 `~/.claude/skills/c4-model/`로 맞추고,
Assumptions 분리·`.env` 미접근 등 지켜야 할 규칙을 커맨드 본문에 명시했다.
