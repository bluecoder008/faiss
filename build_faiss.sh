#!/usr/bin/env bash
#
# build_faiss.sh — automate building the Faiss C++ library from source.
#
# Defaults to a CPU-only, C++-only Release build (the library, no Python
# bindings or tests). On macOS it applies the Apple Clang OpenMP workaround
# using Homebrew's libomp, which INSTALL.md does not cover.
#
# Usage:
#   ./build_faiss.sh                 # build libfaiss
#   ./build_faiss.sh --clean         # remove build/ first, then build
#   ./build_faiss.sh --gpu           # enable GPU (CUDA) build
#   ./build_faiss.sh --python        # enable Python bindings
#   ./build_faiss.sh --testing       # enable tests (needs gflags)
#   ./build_faiss.sh --target swig    # build a specific make target
#   ./build_faiss.sh -j 4            # override parallel job count
#
# Extra args after `--` are passed straight to cmake, e.g.:
#   ./build_faiss.sh -- -DCMAKE_BUILD_TYPE=Debug
#
set -euo pipefail

# --- locate the repo (directory of this script) ---------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- defaults --------------------------------------------------------------
BUILD_DIR="build"
BUILD_TYPE="Release"
ENABLE_GPU="OFF"
ENABLE_PYTHON="OFF"
ENABLE_TESTING="OFF"
CLEAN=0
TARGET="faiss"
EXTRA_CMAKE=()

# Default parallel jobs = CPU count.
if command -v sysctl >/dev/null 2>&1; then
  JOBS="$(sysctl -n hw.ncpu)"
elif command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
else
  JOBS=4
fi

# --- parse arguments -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)    CLEAN=1; shift ;;
    --gpu)      ENABLE_GPU="ON"; shift ;;
    --python)   ENABLE_PYTHON="ON"; shift ;;
    --testing)  ENABLE_TESTING="ON"; shift ;;
    --target)   TARGET="$2"; shift 2 ;;
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    -j|--jobs)  JOBS="$2"; shift 2 ;;
    --)         shift; EXTRA_CMAKE+=("$@"); break ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1 ;;
  esac
done

# --- preflight checks ------------------------------------------------------
if ! command -v cmake >/dev/null 2>&1; then
  echo "ERROR: cmake not found on PATH." >&2
  exit 1
fi

CMAKE_ARGS=(
  -B "$BUILD_DIR" .
  -DFAISS_ENABLE_GPU="$ENABLE_GPU"
  -DFAISS_ENABLE_PYTHON="$ENABLE_PYTHON"
  -DBUILD_TESTING="$ENABLE_TESTING"
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
)

# --- macOS: Apple Clang has no built-in OpenMP; use Homebrew libomp --------
if [[ "$(uname -s)" == "Darwin" ]]; then
  LIBOMP_PREFIX="${LIBOMP_PREFIX:-/opt/homebrew/opt/libomp}"
  if [[ ! -f "$LIBOMP_PREFIX/lib/libomp.dylib" ]]; then
    echo "ERROR: libomp not found at $LIBOMP_PREFIX." >&2
    echo "       Install it with: brew install libomp" >&2
    echo "       Or set LIBOMP_PREFIX to its location." >&2
    exit 1
  fi
  CMAKE_ARGS+=(
    -DOpenMP_CXX_FLAGS="-Xclang -fopenmp -I${LIBOMP_PREFIX}/include"
    -DOpenMP_CXX_LIB_NAMES=omp
    -DOpenMP_omp_LIBRARY="${LIBOMP_PREFIX}/lib/libomp.dylib"
  )
fi

CMAKE_ARGS+=("${EXTRA_CMAKE[@]:-}")

# --- clean if requested (stale CMakeCache breaks reconfigure) --------------
if [[ "$CLEAN" -eq 1 ]]; then
  echo ">> Removing $BUILD_DIR/"
  rm -rf "$BUILD_DIR"
fi

# --- configure -------------------------------------------------------------
echo ">> Configuring (GPU=$ENABLE_GPU PYTHON=$ENABLE_PYTHON TESTING=$ENABLE_TESTING TYPE=$BUILD_TYPE)"
cmake "${CMAKE_ARGS[@]}"

# --- build -----------------------------------------------------------------
echo ">> Building target '$TARGET' with -j$JOBS"
make -C "$BUILD_DIR" -j"$JOBS" "$TARGET"

echo ">> Done. Artifact(s) under $BUILD_DIR/"
[[ -f "$BUILD_DIR/faiss/libfaiss.a" ]] && ls -lh "$BUILD_DIR/faiss/libfaiss.a"
