---
name: README
description: m2slide 폐쇄망(air-gap) 패치 — vendor 자산 + JS 런타임 동봉 자체완결 배포판
date: 2026-07-16
---

# 무엇인가

[m2slide](https://github.com/Finfra/m2slide)(마크다운 → Reveal.js 슬라이드 생성기)를 **인터넷이 전혀 없는 환경**에서도 그대로 빌드·실행할 수 있도록 만든 자체완결 패치입니다. `videoMaker/lib/m2slide` 원본 저장소에서 실행에 필요한 부분만 추려 담았습니다.

air-gap-claudeCode 컨테이너는 외부 네트워크가 없으므로, m2slide가 평소 CDN(jsdelivr, unpkg 등)에서 받아오는 reveal.js·markmap·d3·mermaid·katex 등 자산을 **컨테이너 안에서 새로 받을 방법이 없습니다**. 그래서 이 패치는 그 자산들을 전부 미리 내려받아(`lib/vendor/`) 함께 넣었고, 빌드 스크립트(`lib/*.js`)의 기본 동작 자체가 "CDN 대신 이 로컬 자산을 쓴다(`asset_mode: vendor`)"로 고정되어 있어 별도 설정 없이도 오프라인으로 동작합니다.

# 구성

```
m2slidePatch/
├── m2slide.sh              # 빌드 진입점 (./m2slide.sh <프로젝트명>)
├── _config.org.yml         # 전역 기본 설정값 문서
├── lib/                    # 빌드 로직 전체 (JS) + vendor 자산
│   ├── *.js                 # 마크다운 파싱·HTML 생성·설정 처리 등 핵심 로직
│   ├── vendor/               # reveal.js·markmap·d3·mermaid·katex 등 사전 다운로드 자산 (18종)
│   ├── dev-server/           # 로컬 미리보기 서버 (빌드 후 자동 기동, 포트 9877)
│   ├── kroki/                 # 다이어그램 SVG 캐시 (ditaa 등 — 이미 렌더링된 것만 포함)
│   ├── component-hooks/       # chart·map·katex 등 컴포넌트 디스패처
│   └── css/                   # 공통 기반 CSS
├── theme/                  # default, default_lec, default_dark, _shared 테마
├── data/
│   └── component-libraries.yml  # 컴포넌트(chart/map/katex 등) 인식용 카탈로그 (빌드 필수)
└── Projects/
    └── HelloOffline/        # 동작 확인용 최소 예제 (아래 "동작 확인" 참조)
```

원본 저장소의 `Projects/`(다른 프로젝트들), `data/`(나머지 authoring-pipeline 전용 자료), `docs/`, `_doc_arch/`, `graphify-out/` 등은 빌드 실행에 불필요해 제외했습니다. `HelloOffline` 예제만 남겨 즉시 검증할 수 있게 했습니다.

# 사용법

## 1. 동작 확인 (가장 먼저 할 것)

```bash
cd m2slidePatch
./m2slide.sh HelloOffline
```

`Projects/HelloOffline/slide/index.html`이 생성되면 성공입니다. 브라우저로 열어 슬라이드 2장 + 표지가 정상적으로 보이면 vendor 자산(폰트·reveal.js·markmap)이 전부 로컬에서 로드된 것입니다 — 인터넷 연결과 무관하게 동작합니다.

## 2. 새 프로젝트 만들기

```bash
mkdir -p Projects/MyDeck/markdown
cat > Projects/MyDeck/markdown/AGENDA.md <<'EOF'
---
title: MyDeck
type: ppt
---

## [1. 시작](./01-start.md)
EOF

cat > Projects/MyDeck/markdown/01-start.md <<'EOF'
## 첫 슬라이드

* 내용을 여기 작성
EOF

./m2slide.sh MyDeck
```

## 3. 배포 규칙 검사 (선택, 권장)

```bash
./m2slide.sh --lint-deployment MyDeck
```

`localhost` 하드코딩, 절대경로 등 배포 시 문제될 패턴이 있는지 자동 검사합니다.

# 왜 vendor 모드를 "켤" 필요가 없는가

원본 m2slide는 `_config.yml`의 `asset_mode` 키로 `vendor`(로컬 자산, 기본값)와 `cdn`(외부 웹 서빙용) 두 모드를 지원합니다. 이 패치의 `lib/config.js`에 하드코딩된 기본값이 이미 `vendor`이고, 프로젝트별 `_config.yml`에서 `asset_mode: cdn`으로 override하지 않는 한 항상 로컬 `lib/vendor/` 자산을 씁니다. 즉 **아무 설정도 안 해도 오프라인 모드**입니다. 혹시 나중에 프로젝트를 원본 저장소에서 복사해올 때 그 프로젝트의 `_config.yml`에 `asset_mode: cdn`이 적혀 있다면 그 줄만 지우면 됩니다.

`node lib/vendor/fetch-vendor.js`(자산을 인터넷에서 새로 받는 스크립트)는 이 패치에 포함하지 않았습니다 — 애초에 air-gap 안에서는 실행해도 실패하기 때문입니다. `lib/vendor/`에 이미 18종 자산(reveal.js·markmap-view·d3·mermaid·katex·chart.js·leaflet·react·model-viewer·p5·폰트류)이 전부 들어있으므로 다시 받을 필요가 없습니다.

# 제약 사항 (알아둘 것)

* **EPUB 생성(`--epub`)의 Mermaid 다이어그램 변환은 미지원**: `mmdc`(Mermaid CLI, 별도 npm 전역 설치)와 시스템 Chrome이 필요한데 둘 다 이 패치에 포함하지 않았습니다. HTML 슬라이드 생성에는 영향 없습니다.
* **PDF/PPTX 변환(`--pdf`, `--pptx`)도 미지원**: 각각 decktape·pandoc 외부 도구가 필요합니다.
* **ditaa 등 신규 다이어그램**: `` ```ditaa ``` `` 코드블록을 새로 추가하면 원래는 kroki.io에 렌더링을 요청하는데, 이 패치엔 그 요청을 할 인터넷이 없습니다. `lib/kroki/`에 이미 캐시된 다이어그램(기존 예제에 쓰인 것들)은 재사용되지만, 새 다이어그램은 그림이 안 나오고 에러 표시만 남습니다(빌드 자체는 안 멈춤). 새 다이어그램이 필요하면 인터넷 되는 곳에서 한 번 렌더링해 `lib/kroki/`에 캐시를 만든 뒤 이 패치에 반영하면 됩니다.
* Node.js가 필요합니다 (컨테이너에 이미 `node` v18 설치되어 있음 확인됨 — Claude Code 자체가 Node 기반이라 항상 존재).

# 검증 이력

이 패치를 만들면서 로컬(videoMaker/lib/m2slide 개발 머신)에서 다음을 확인했습니다.

* `HelloOffline` 빌드 성공, `data/component-libraries.yml` 누락 시 나던 경고 없음 (포함 완료)
* `./m2slide.sh --lint-deployment HelloOffline` → 배포 규칙 위반 0건
* 산출물 HTML/CSS 전체에서 `cdn.jsdelivr.net`·`unpkg.com`·`googleapis.com` 등 외부 참조 검색 → 0건
* `lib/vendor/` 18종 자산 전부 정상 크기로 포함됨
