CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -lm
BIN     = bin
SRC     = src
RESULTS = results

SEQ_SRC = $(SRC)/mandelbrot_seq.c
OMP_SRC = $(SRC)/mandelbrot_omp.c
SEQ_BIN = $(BIN)/mandelbrot_seq
OMP_BIN = $(BIN)/mandelbrot_omp

# ── macOS / Linux OpenMP + pthread detection ───────────────────────────────────
UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    GCC14 := $(shell command -v gcc-14 2>/dev/null)
    GCC13 := $(shell command -v gcc-13 2>/dev/null)
    ifneq ($(GCC14),)
        OMP_CC      = gcc-14
        OMP_FLAGS   = -fopenmp
        PTHREAD_FLAGS =
    else ifneq ($(GCC13),)
        OMP_CC      = gcc-13
        OMP_FLAGS   = -fopenmp
        PTHREAD_FLAGS =
    else
        LIBOMP_ARM  := /opt/homebrew/opt/libomp
        LIBOMP_X86  := /usr/local/opt/libomp
        LIBOMP_PATH := $(shell [ -d $(LIBOMP_ARM) ] && echo $(LIBOMP_ARM) || echo $(LIBOMP_X86))
        OMP_CC      = clang
        OMP_FLAGS   = -Xpreprocessor -fopenmp \
                      -I$(LIBOMP_PATH)/include \
                      -L$(LIBOMP_PATH)/lib \
                      -lomp
        PTHREAD_FLAGS =
    endif
else
    OMP_CC        = gcc
    OMP_FLAGS     = -fopenmp
    PTHREAD_FLAGS = -lpthread
endif

.PHONY: all seq omp benchmark clean help

all: $(BIN) $(RESULTS) seq omp

$(BIN):
	mkdir -p $(BIN)

$(RESULTS):
	mkdir -p $(RESULTS)

seq: $(BIN) $(RESULTS)
	$(CC) $(CFLAGS) -o $(SEQ_BIN) $(SEQ_SRC)
	@echo "✔  Sequential binary: $(SEQ_BIN)"

omp: $(BIN) $(RESULTS)
	$(OMP_CC) $(CFLAGS) $(OMP_FLAGS) $(PTHREAD_FLAGS) -o $(OMP_BIN) $(OMP_SRC)
	@echo "✔  Parallel binary:   $(OMP_BIN)"

benchmark: all
	@chmod +x scripts/benchmark.sh
	@scripts/benchmark.sh $(SEQ_BIN) $(OMP_BIN)

clean:
	rm -rf $(BIN)
	find $(RESULTS) -name "*.png" ! -name "seahorse.png" ! -name "vortex.png" \
	     -delete 2>/dev/null; true
	@echo "✔  Cleaned"

help:
	@echo ""
	@echo "  make           — build both binaries"
	@echo "  make seq       — build sequential only"
	@echo "  make omp       — build parallel only"
	@echo "  make benchmark — compile and run full speedup benchmark"
	@echo "  make clean     — remove binaries and generated images"
	@echo ""
