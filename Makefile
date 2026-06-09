# Makefile — build the Faiss C++ library via CMake.
#
# A thin front-end over the CMake configure + build steps. Defaults to a
# CPU-only, C++-only Release build (libfaiss.a, no Python bindings or tests).
# On macOS it applies the Apple Clang OpenMP workaround using Homebrew's libomp,
# which INSTALL.md does not cover.
#
# Usage:
#   make                    # configure + build libfaiss
#   make clean              # remove the build directory
#   make GPU=ON             # enable the CUDA build
#   make PYTHON=ON          # build the Python bindings
#   make TESTING=ON         # build the tests (needs gflags)
#   make TARGET=swig        # build a specific CMake target
#   make JOBS=4             # override the parallel job count
#   make CMAKE_EXTRA="-DCMAKE_BUILD_TYPE=Debug"   # pass extra cmake args
#
# Variables combine, e.g.:  make GPU=ON PYTHON=ON JOBS=8

# --- configurable variables ------------------------------------------------
BUILD_DIR   ?= build
BUILD_TYPE  ?= Release
GPU         ?= OFF
PYTHON      ?= OFF
TESTING     ?= OFF
TARGET      ?= faiss
CMAKE_EXTRA ?=

# Default parallel jobs = CPU count (sysctl on macOS, nproc on Linux).
JOBS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# --- base cmake arguments --------------------------------------------------
CMAKE_ARGS = -B $(BUILD_DIR) . \
             -DFAISS_ENABLE_GPU=$(GPU) \
             -DFAISS_ENABLE_PYTHON=$(PYTHON) \
             -DBUILD_TESTING=$(TESTING) \
             -DCMAKE_BUILD_TYPE=$(BUILD_TYPE)

# --- macOS: Apple Clang has no built-in OpenMP; use Homebrew libomp --------
ifeq ($(shell uname -s),Darwin)
  LIBOMP_PREFIX ?= /opt/homebrew/opt/libomp
  CMAKE_ARGS += -DOpenMP_CXX_FLAGS="-Xclang -fopenmp -I$(LIBOMP_PREFIX)/include" \
                -DOpenMP_CXX_LIB_NAMES=omp \
                -DOpenMP_omp_LIBRARY="$(LIBOMP_PREFIX)/lib/libomp.dylib"
endif

# --- targets ---------------------------------------------------------------
.PHONY: all build configure clean help

all: build

# Always reconfigure: cmake is cheap when nothing changed, and this keeps the
# build honest when you flip GPU/PYTHON/TESTING between invocations.
configure:
	@command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake not found on PATH." >&2; exit 1; }
ifeq ($(shell uname -s),Darwin)
	@test -f "$(LIBOMP_PREFIX)/lib/libomp.dylib" || { \
	  echo "ERROR: libomp not found at $(LIBOMP_PREFIX)." >&2; \
	  echo "       Install it with: brew install libomp" >&2; \
	  echo "       Or set LIBOMP_PREFIX=<path>." >&2; exit 1; }
endif
	@echo ">> Configuring (GPU=$(GPU) PYTHON=$(PYTHON) TESTING=$(TESTING) TYPE=$(BUILD_TYPE))"
	cmake $(CMAKE_ARGS) $(CMAKE_EXTRA)

build: configure
	@echo ">> Building target '$(TARGET)' with -j$(JOBS)"
	$(MAKE) -C $(BUILD_DIR) -j$(JOBS) $(TARGET)
	@test -f "$(BUILD_DIR)/faiss/libfaiss.a" && ls -lh "$(BUILD_DIR)/faiss/libfaiss.a" || true

clean:
	@echo ">> Removing $(BUILD_DIR)/"
	rm -rf $(BUILD_DIR)

help:
	@echo "Targets: all (default), build, configure, clean, help"
	@echo "Vars:    GPU PYTHON TESTING TARGET JOBS BUILD_DIR BUILD_TYPE LIBOMP_PREFIX CMAKE_EXTRA"
	@echo "Example: make GPU=ON PYTHON=ON JOBS=8"
