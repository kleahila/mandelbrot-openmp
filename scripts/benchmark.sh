#!/usr/bin/env bash
# scripts/benchmark.sh
# Run sequential baseline then parallel (1, 2, 4, 8 threads) for seahorse and vortex.
# Prints a live table as results come in, saves results/benchmark_times.txt.
#
# Usage (direct):  bash scripts/benchmark.sh
# Usage (make):    make benchmark

set -euo pipefail

SEQ_BIN="${1:-bin/mandelbrot_seq}"
OMP_BIN="${2:-bin/mandelbrot_omp}"

# ── ANSI ──────────────────────────────────────────────────────────────────────
OR='\033[38;5;214m'; GR='\033[0;32m'; BW='\033[1;37m'; NC='\033[0m'

if [ ! -f "$SEQ_BIN" ] || [ ! -f "$OMP_BIN" ]; then
    echo "ERROR: Binaries not found. Run 'make' or './run.sh' option 1 first."
    exit 1
fi

mkdir -p results

BENCH_PRESETS=("seahorse:0" "vortex:1")
THREAD_COUNTS=(1 2 4 8)

# Plain variables — compatible with bash 3.2 (macOS default)
SEQ_SH="" ; SEQ_VX=""

# ── Sequential baseline ───────────────────────────────────────────────────────
printf "\n${OR}  ▶  Sequential baseline...${NC}\n"

OUT=$("$SEQ_BIN" 0 2>/dev/null)
SEQ_SH=$(echo "$OUT" | grep "^TIME_seahorse=" | cut -d= -f2)
printf "     %-16s %s s\n" "seahorse" "$SEQ_SH"

OUT=$("$SEQ_BIN" 1 2>/dev/null)
SEQ_VX=$(echo "$OUT" | grep "^TIME_vortex=" | cut -d= -f2)
printf "     %-16s %s s\n" "vortex" "$SEQ_VX"

# ── Parallel runs — one omp invocation per thread count ──────────────────────
PAR_SH_1="" ; PAR_VX_1=""
PAR_SH_2="" ; PAR_VX_2=""
PAR_SH_4="" ; PAR_VX_4=""
PAR_SH_8="" ; PAR_VX_8=""

for T in "${THREAD_COUNTS[@]}"; do
    printf "\n${OR}  ▶  Parallel  T=%-2s ...${NC}\n" "$T"
    OUT=$("$OMP_BIN" "$T" 2>/dev/null)
    SH=$(echo "$OUT" | grep "^TIME_seahorse=" | cut -d= -f2)
    VX=$(echo "$OUT" | grep "^TIME_vortex="   | cut -d= -f2)
    eval "PAR_SH_${T}=$SH"
    eval "PAR_VX_${T}=$VX"
    SP_SH=$(awk "BEGIN {printf \"%.2f\", $SEQ_SH / $SH}")
    SP_VX=$(awk "BEGIN {printf \"%.2f\", $SEQ_VX / $VX}")
    printf "     %-16s %s s  (${GR}%sx${NC})\n" "seahorse" "$SH" "$SP_SH"
    printf "     %-16s %s s  (${GR}%sx${NC})\n" "vortex"   "$VX" "$SP_VX"
done

# ── Save timing data ──────────────────────────────────────────────────────────
TIMES_FILE="results/benchmark_times.txt"
{
    printf "SEQ_seahorse=%s\n" "$SEQ_SH"
    printf "SEQ_vortex=%s\n"   "$SEQ_VX"
    for T in "${THREAD_COUNTS[@]}"; do
        eval "SH=\$PAR_SH_${T}"; eval "VX=\$PAR_VX_${T}"
        printf "T%s_seahorse=%s\n" "$T" "$SH"
        printf "T%s_vortex=%s\n"   "$T" "$VX"
    done
} > "$TIMES_FILE"

printf "\n${GR}  ✔  Timing data saved to %s${NC}\n" "$TIMES_FILE"

# ── Formatted summary table ───────────────────────────────────────────────────
printf "\n"
printf "  ${BW}┌────────────┬─────────────┬──────────┬────────────┬──────────┐${NC}\n"
printf "  ${BW}│  Threads   │ Seahorse(s) │ Speedup  │  Vortex(s) │ Speedup  │${NC}\n"
printf "  ${BW}├────────────┼─────────────┼──────────┼────────────┼──────────┤${NC}\n"
printf "  ${BW}│ Sequential │  %9.3f  │  1.00x   │  %8.3f  │  1.00x   │${NC}\n" \
       "$SEQ_SH" "$SEQ_VX"

for T in "${THREAD_COUNTS[@]}"; do
    eval "SH=\$PAR_SH_${T}"; eval "VX=\$PAR_VX_${T}"
    SP_SH=$(awk "BEGIN {printf \"%.2f\", $SEQ_SH / $SH}")
    SP_VX=$(awk "BEGIN {printf \"%.2f\", $SEQ_VX / $VX}")
    printf "  ${BW}│ %10s │  %9.3f  │ %6.2fx   │  %8.3f  │ %6.2fx   │${NC}\n" \
           "$T" "$SH" "$SP_SH" "$VX" "$SP_VX"
done
printf "  ${BW}└────────────┴─────────────┴──────────┴────────────┴──────────┘${NC}\n\n"

# ── Generate speedup table + chart PNGs ──────────────────────────────────────
if command -v python3 &>/dev/null; then
    python3 scripts/gen_table.py
fi

printf "\n"
