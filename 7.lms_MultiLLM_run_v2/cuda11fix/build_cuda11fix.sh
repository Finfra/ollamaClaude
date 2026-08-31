#!/bin/bash
# build_cuda11fix.sh — CUDA 11 런타임 노출 오버레이 이미지 빌드 + 검증
#
# 얇은 레이어만 추가하므로 빠르다(베이스 24.7GB 재빌드 없음, 재다운로드 없음).
# 라이브 GPU 서비스·호스트 CUDA 무영향(빌드 시 GPU 미사용).
#
# 사용:
#   ./build_cuda11fix.sh                  # lms:small → lms:small-cuda11fix
#   ./build_cuda11fix.sh lms:latest       # lms:latest → lms:latest-cuda11fix
#   ./build_cuda11fix.sh lms:small lms:small   # 같은 태그로 덮어쓰기(제자리 교체)
#
# 빌드 후 step4 에서 사용:
#   cd ../step4.cc_gw_lms2 && LMS_IMAGE=lms:small-cuda11fix ./run.sh
set -euo pipefail

BASE="${1:-lms:small}"
OUT="${2:-${BASE}-cuda11fix}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== CUDA 11 런타임 노출 오버레이 빌드 ==="
echo "  BASE: $BASE"
echo "  OUT:  $OUT"

# 0) 베이스 존재 확인
docker image inspect "$BASE" >/dev/null 2>&1 \
  || { echo "❌ 베이스 이미지 없음: $BASE (docker images 확인)" >&2; exit 1; }

# 1) 빌드 (Dockerfile 내부에서 ldconfig 등록 성공을 자체 검증 — 실패 시 빌드 실패)
docker build --build-arg BASE="$BASE" \
  -f "$SCRIPT_DIR/Dockerfile.cuda11fix" -t "$OUT" "$SCRIPT_DIR"

# 2) 결과 검증 (throwaway, GPU 미사용)
echo "=== 검증: $OUT 안에서 libcudart.so.11 해석 ==="
if docker run --rm --user root --entrypoint sh "$OUT" -c 'ldconfig -p | grep -i "libcudart.so.11"'; then
  echo "✅ ldconfig 에 libcudart.so.11 등록 확인"
else
  echo "❌ 검증 실패 — libcudart.so.11 미등록" >&2
  exit 1
fi

echo
echo "=== libggml-cuda.so 동적 링크 확인 (드라이버 libcuda.so.1 은 --gpus 런타임 주입) ==="
docker run --rm --user root --entrypoint sh "$OUT" -c '
  so=$(find /home/lms/.lmstudio/extensions/backends -name libggml-cuda.so | head -1)
  ldd "$so" 2>/dev/null | grep -iE "cudart|cublas|libcuda" || true
' 2>/dev/null | grep -v 'not a symbolic link' || true

echo
echo "완료: $OUT"
echo "다음: cd ../step4.cc_gw_lms2 && LMS_IMAGE=$OUT ./run.sh"
