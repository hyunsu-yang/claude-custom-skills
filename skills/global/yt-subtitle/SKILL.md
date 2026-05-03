---
name: yt-subtitle
description: Use when user provides a YouTube URL and wants subtitles extracted, transcribed, summarized, or analyzed. Triggers on youtube.com/watch, youtu.be, youtube.com/shorts URLs.
---

# YouTube 자막 추출

## Overview
`yt-dlp`를 사용해 YouTube 자막(자동생성 포함)을 추출하고 텍스트로 변환한다.
브라우저 fetch로는 YouTube IP 검증 때문에 빈 응답이 반환되므로 반드시 CLI 도구를 사용해야 한다.

## 추출 명령

```bash
# 한국어 자동생성 자막 (가장 일반적)
yt-dlp --write-auto-sub --sub-lang ko --skip-download --sub-format json3 \
       -o "/tmp/yt_sub" "<URL>"

# 수동 자막이 있는 경우 (자동생성 없을 때 fallback)
yt-dlp --write-sub --sub-lang ko --skip-download --sub-format json3 \
       -o "/tmp/yt_sub" "<URL>"

# 어떤 자막이 있는지 먼저 확인
yt-dlp --list-subs "<URL>"
```

출력 파일: `/tmp/yt_sub.ko.json3`

## 파싱 (Python)

```python
import json

with open('/tmp/yt_sub.ko.json3') as f:
    data = json.load(f)

lines = []
for event in data.get('events', []):
    if 'segs' not in event:
        continue
    text = ''.join(s.get('utf8', '') for s in event['segs']).replace('\n', ' ').strip()
    if text:
        start = event['tStartMs'] / 1000
        lines.append(f'[{start:.1f}s] {text}')

print('\n'.join(lines))
```

## 언어 코드 참고

| 언어 | 코드 |
|------|------|
| 한국어 | `ko` |
| 영어 | `en` |
| 일본어 | `ja` |
| 중국어(간체) | `zh-Hans` |

## 포맷 옵션

| 포맷 | 용도 |
|------|------|
| `json3` | 타임스탬프 포함 파싱용 (권장) |
| `vtt` | 웹 표준 자막 파일 |
| `srt` | 범용 자막 파일 |

## 주의사항

- `yt-dlp` 미설치 시: `brew install yt-dlp`
- 자막 없는 영상: `--list-subs`로 먼저 확인
- 만료된 timedtext URL을 브라우저 fetch로 재사용하면 항상 빈 응답 — CLI만 사용
- Shorts, 일반 영상, 라이브 다시보기 모두 동일 명령으로 동작

## 워크플로우

1. URL에서 자막 추출 (`yt-dlp` 명령 실행)
2. json3 파싱해서 텍스트 정리
3. 사용자 요청에 따라 요약 / 핵심 포인트 / 전문 출력
