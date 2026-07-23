---
name: README
description: lms 이미지 CUDA 11 런타임 노출 오버레이 — libcudart.so.11.0 미해석(엔진 로드 실패) 해결
date: 2026-07-23
---

# 개요

`6.lms_MultiLLM_run` 반입 실패(`libcudart.so.11.0: cannot open shared object file`)의
**이미지 측 해결**. prj55#Issue9 가 지목한 "CUDA 11 런타임 부재"의 실제 정체는 *부재*가
아니라 *경로 미노출*이었다.

# 근본 원인 (fg1 에서 하드 증거로 확정, 2026-07-23)

`lms:latest`/`lms:small` 이미지 내부를 직접 확인한 결과:

| 확인 | 결과 |
| :--- | :--- |
| `libcudart.so.11.0` 존재? | ✅ 있음 — `/home/lms/.lmstudio/extensions/backends/vendor/linux-llama-cuda-vendor-v1/` (LM Studio 번들) |
| CUDA 백엔드 존재? | ✅ `llama.cpp-linux-x86_64-nvidia-cuda-avx2-2.23.1/libggml-cuda.so` (565MB) |
| `ldconfig -p` 에 cudart? | ❌ **없음** — vendor 디렉토리가 링커 검색 경로에 미등록 |

수정 전후 `ldd libggml-cuda.so`:

```
[수정 전]  libcudart.so.11.0 => not found        ← 엔진 로드 실패의 직접 원인
           libcublas.so.11   => not found
           libcuda.so.1      => not found

[수정 후]  libcudart.so.11.0 => .../vendor/linux-llama-cuda-vendor-v1/libcudart.so.11.0  ✅
           libcublas.so.11   => (해석됨)
           libcuda.so.1      => not found        ← 드라이버, --gpus 로 런타임 주입 (정상)
```

→ **호스트에 CUDA 11 을 설치할 필요가 없다.** 컨테이너는 호스트 ldconfig 를 상속하지
않고, nvidia-container-toolkit 은 드라이버(libcuda.so.1)만 주입하며 libcudart 는 주입하지
않는다. 필요한 CUDA 11 런타임은 이미 이미지 안에 있으므로, ldconfig 등록만으로 해결된다.

# 수정 내용

`Dockerfile.cuda11fix` — 베이스 이미지에 얇은 레이어 하나 추가:

1. vendor 디렉토리(libcudart.so.11* 위치)를 `/etc/ld.so.conf.d/lms-cuda11.conf` 에 등록
2. `ldconfig` 갱신
3. 빌드 시 `ldconfig -p | grep libcudart.so.11` 자체 검증 (실패 시 빌드 실패 = fail-loud)

USER root 로 수행(ldconfig 는 root 필요). entrypoint 는 런타임에 lms(비-root)로 돌아
ldconfig 를 못 하므로, 이미지 빌드 레이어에서 처리하는 것이 유일한 정공법이다.

# 사용

```bash
# 빌드 (얇은 레이어 — 빠름, 베이스 재빌드/재다운로드 없음)
./build_cuda11fix.sh                 # lms:small → lms:small-cuda11fix
./build_cuda11fix.sh lms:latest      # lms:latest → lms:latest-cuda11fix

# step4 에서 교체 이미지 사용
cd ../step4.cc_gw_lms2
LMS_IMAGE=lms:small-cuda11fix ./run.sh
```

빌드된 이미지는 v2 `entrypoint.lms.sh` 의 CUDA 프리플라이트(`ldconfig -p | grep
libcudart.so.11`)를 통과하므로 `LMS_REQUIRE_CUDA=1` 기본에서 정상 기동한다.

# 영구화(선택)

이 오버레이 대신 베이스 이미지에 영구 반영하려면, lms 베이스를 빌드하는
`Dockerfile.lms`(install.sh 설치 직후, USER root 구간)에 아래를 추가:

```dockerfile
USER root
RUN set -eux; \
    lib="$(find /home/lms/.lmstudio/extensions/backends/vendor -name 'libcudart.so.11*' -print -quit)"; \
    dir="$(dirname "$lib")"; \
    echo "$dir" > /etc/ld.so.conf.d/lms-cuda11.conf; \
    ldconfig
USER lms
```

# 검증 상태 (2026-07-23)

* ✅ 근본 원인 확정 — `lms:latest` throwaway 컨테이너에서 `ldd`/`ldconfig` 로 확인
* ✅ 수정 로직 검증 — ldconfig 등록 후 `libcudart.so.11.0`/`libcublas.so.11` 해석 성공
* ✅ **실제 오버레이 빌드 완료** — `lms:small-cuda11fix` 빌드(sha256:f5626d45…). 빌드 아티팩트
  내부 `ldd libggml-cuda.so` 로 `libcudart.so.11.0`·`libcublas.so.11`·`libcublasLt.so.11`
  전부 해석 확인(드라이버 `libcuda.so.1` 만 미해석 — `--gpus` 런타임 주입, 정상)
* ⏸️ step4 GPU 기동 통합 테스트 — fg1 GPU 가 라이브 lms(13GB/16GB)로 점유 중이라 게이트.
  서비스 여유 window 에 `cd ../step4.cc_gw_lms2 && LMS_IMAGE=lms:small-cuda11fix ./run.sh`
