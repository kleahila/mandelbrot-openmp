#!/usr/bin/env bash
# run.sh — Mandelbrot OpenMP Project Launcher
# Interactive menu: build, render, benchmark, table, clean, help.

set -uo pipefail

# ── ANSI colors ────────────────────────────────────────────────────────────────
OR='\033[38;5;214m'    # orange
GR='\033[0;32m'        # green
RD='\033[0;31m'        # red
BW='\033[1;37m'        # bold white
DIM='\033[2m'
NC='\033[0m'

# ── Paths ──────────────────────────────────────────────────────────────────────
SEQ_BIN="bin/mandelbrot_seq"
OMP_BIN="bin/mandelbrot_omp"
SEQ_SRC="src/mandelbrot_seq.c"
OMP_SRC="src/mandelbrot_omp.c"
THREAD_COUNTS=(1 2 4 8)

# ── Preset data (must match PRESETS[] in both .c files) ───────────────────────
PRESET_NAMES=("Seahorse Valley" "Vortex")
PRESET_LABELS=("seahorse" "vortex")
PRESET_CX=("-0.7453954" "-0.7269820")
PRESET_CY=("0.1125490"  "0.1889580")
PRESET_ZOOM=("0.00065"  "0.00030")
PRESET_ITER=("2000"     "2000")
NUM_PRESETS=2

THEME_NAMES=("Seahorse Classic (orange/blue)" "Inferno (purple/red/yellow)" "Ocean (navy/teal/gold)" "Monochrome (black/white)")
THEME_LABELS=("classic" "inferno" "ocean" "mono")
NUM_THEMES=4

# ── OpenMP compiler detection ──────────────────────────────────────────────────
detect_omp() {
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v gcc-14 &>/dev/null; then
            OMP_CC="gcc-14"; OMP_FLAGS="-fopenmp"; PTHREAD_FLAGS=""
        elif command -v gcc-13 &>/dev/null; then
            OMP_CC="gcc-13"; OMP_FLAGS="-fopenmp"; PTHREAD_FLAGS=""
        else
            local libomp="/opt/homebrew/opt/libomp"
            [[ -d "$libomp" ]] || libomp="/usr/local/opt/libomp"
            OMP_CC="clang"
            OMP_FLAGS="-Xpreprocessor -fopenmp -I${libomp}/include -L${libomp}/lib -lomp"
            PTHREAD_FLAGS=""
        fi
        OS_LABEL="macOS ($(uname -m))"
    else
        OMP_CC="gcc"; OMP_FLAGS="-fopenmp"; PTHREAD_FLAGS="-lpthread"
        OS_LABEL="Linux"
    fi
}

# ── Output helpers ─────────────────────────────────────────────────────────────
info()    { printf "${OR}  →  ${NC}%s\n" "$*"; }
success() { printf "${GR}  ✔  ${NC}%s\n" "$*"; }
error()   { printf "${RD}  ✘  ${NC}%s\n" "$*"; }
warn()    { printf "${OR}  !  ${NC}%s\n" "$*"; }
step()    { printf "${BW}  ▶  ${NC}%s\n" "$*"; }

header() {
    printf "\n${OR}╔══════════════════════════════════════╗${NC}\n"
    printf "${OR}║${NC}${BW}  %-36s${NC}${OR}║${NC}\n" "$1"
    printf "${OR}╚══════════════════════════════════════╝${NC}\n\n"
}

pause() {
    printf "\n${DIM}  Press Enter to return to menu...${NC}"
    read -r
}

require_bins() {
    if [[ ! -f "$SEQ_BIN" || ! -f "$OMP_BIN" ]]; then
        warn "Binaries not found — building first..."
        echo ""
        do_build || return 1
        echo ""
    fi
}

# ── Build ──────────────────────────────────────────────────────────────────────
do_build() {
    detect_omp
    mkdir -p bin results

    local CFLAGS="-O2 -Wall -Wextra -lm"

    info "OS detected : $OS_LABEL"
    info "OMP compiler: ${OMP_CC}  flags: ${OMP_FLAGS}"
    echo ""

    step "Compiling sequential binary..."
    # shellcheck disable=SC2086
    if gcc $CFLAGS -o "$SEQ_BIN" "$SEQ_SRC" 2>&1; then
        success "Sequential binary ready: $SEQ_BIN"
    else
        error "Sequential build failed."
        return 1
    fi

    echo ""
    step "Compiling parallel binary (${OMP_CC})..."
    # shellcheck disable=SC2086
    if $OMP_CC $CFLAGS $OMP_FLAGS $PTHREAD_FLAGS -o "$OMP_BIN" "$OMP_SRC" 2>&1; then
        success "Parallel binary ready: $OMP_BIN"
    else
        error "Parallel build failed."
        return 1
    fi
}

# ── Manual coordinate input ────────────────────────────────────────────────────
prompt_manual_coords() {
    MANUAL_RENDER=1
    local valid=0
    while [[ $valid -eq 0 ]]; do
        printf "    ${BW}Name (letters/digits/_):     ${NC}"; read -r MANUAL_NAME
        MANUAL_NAME="${MANUAL_NAME//[^a-zA-Z0-9_]/_}"
        [[ -z "$MANUAL_NAME" ]] && MANUAL_NAME="custom"

        printf "    ${BW}cx  [-2.5 to 1.0]:            ${NC}"; read -r MANUAL_CX
        if ! awk "BEGIN { v=$MANUAL_CX+0; exit (v>=-2.5 && v<=1.0) ? 0 : 1 }" 2>/dev/null; then
            error "cx must be in [-2.5, 1.0]"; continue
        fi
        printf "    ${BW}cy  [-1.25 to 1.25]:          ${NC}"; read -r MANUAL_CY
        if ! awk "BEGIN { v=$MANUAL_CY+0; exit (v>=-1.25 && v<=1.25) ? 0 : 1 }" 2>/dev/null; then
            error "cy must be in [-1.25, 1.25]"; continue
        fi
        printf "    ${BW}zoom (> 0, e.g. 0.001):       ${NC}"; read -r MANUAL_ZOOM
        if ! awk "BEGIN { v=$MANUAL_ZOOM+0; exit (v>0) ? 0 : 1 }" 2>/dev/null; then
            error "zoom must be > 0"; continue
        fi
        printf "    ${BW}max iterations [default 2000]: ${NC}"; read -r MANUAL_ITER
        [[ "$MANUAL_ITER" =~ ^[0-9]+$ ]] || MANUAL_ITER=2000

        valid=1
    done
}

# ── Preset submenu ─────────────────────────────────────────────────────────────
show_preset_list() {
    printf "  ${OR}┌─ Zoom Presets ──────────────────────────────────────────────┐${NC}\n"
    for i in "${!PRESET_NAMES[@]}"; do
        printf "  ${OR}│${NC} ${BW}%d. %-20s${NC}\n" "$((i+1))" "${PRESET_NAMES[$i]}"
        printf "  ${OR}│${NC}    cx=%-12s cy=%-12s zoom=%s  iter=%s\n" \
            "${PRESET_CX[$i]}" "${PRESET_CY[$i]}" "${PRESET_ZOOM[$i]}" "${PRESET_ITER[$i]}"
    done
    printf "  ${OR}│${NC} ${BW}6. Manual input${NC}\n"
    printf "  ${OR}└────────────────────────────────────────────────────────────┘${NC}\n"
}

choose_preset() {
    show_preset_list
    echo ""
    printf "  ${BW}Choice [1-${NUM_PRESETS} or 6]: ${NC}"
    read -r pchoice
    MANUAL_RENDER=0
    if [[ "$pchoice" == "6" ]]; then
        prompt_manual_coords
    elif [[ "$pchoice" =~ ^[1-5]$ ]]; then
        CHOSEN_PIDX=$((pchoice - 1))
    else
        error "Invalid — defaulting to Seahorse Valley."
        CHOSEN_PIDX=0
    fi
}

# ── Theme submenu ──────────────────────────────────────────────────────────────
choose_theme() {
    printf "  ${OR}┌─ Color Themes ──────────────────────┐${NC}\n"
    for i in "${!THEME_NAMES[@]}"; do
        printf "  ${OR}│${NC} ${BW}%d.${NC} %s\n" "$((i+1))" "${THEME_NAMES[$i]}"
    done
    printf "  ${OR}└─────────────────────────────────────┘${NC}\n\n"
    printf "  ${BW}Choice [1-${NUM_THEMES}, default 1]: ${NC}"
    read -r tchoice
    CHOSEN_THEME=0
    if [[ "$tchoice" =~ ^[1-4]$ ]]; then
        CHOSEN_THEME=$((tchoice - 1))
    fi
}

# ── Mode submenu ───────────────────────────────────────────────────────────────
choose_mode() {
    printf "  ${OR}┌─ Render Mode ───────────────────────┐${NC}\n"
    printf "  ${OR}│${NC} ${BW}1.${NC} Sequential\n"
    printf "  ${OR}│${NC} ${BW}2.${NC} Parallel — choose thread count\n"
    printf "  ${OR}└─────────────────────────────────────┘${NC}\n\n"
    printf "  ${BW}Choice [1-2, default 2]: ${NC}"
    read -r rchoice
    RENDER_MODE="omp"
    RENDER_THREADS=4
    if [[ "$rchoice" == "1" ]]; then
        RENDER_MODE="seq"
    else
        printf "  ${BW}Threads [1/2/4/8 or custom, default 4]: ${NC}"
        read -r tcount
        if [[ "$tcount" =~ ^[0-9]+$ ]] && [[ "$tcount" -ge 1 ]]; then
            RENDER_THREADS="$tcount"
        fi
    fi
}

# ── Render a single preset ─────────────────────────────────────────────────────
do_render_one() {
    local pidx="$1" theme="$2" mode="$3" threads="${4:-4}"
    local pname="${PRESET_LABELS[$pidx]}"
    local tname="${THEME_LABELS[$theme]}"

    echo ""
    if [[ "$mode" == "seq" ]]; then
        step "Rendering ${PRESET_NAMES[$pidx]} (sequential, theme: ${THEME_NAMES[$theme]})..."
        "$SEQ_BIN" "$pidx" --theme "$theme"
    else
        step "Rendering ${PRESET_NAMES[$pidx]} (${threads} threads, theme: ${THEME_NAMES[$theme]})..."
        "$OMP_BIN" "$threads" --preset "$pidx" --theme "$theme"
    fi
}

# ── Render manual custom coordinates ──────────────────────────────────────────
do_render_custom() {
    local theme="$1" mode="$2" threads="${3:-4}"
    echo ""
    if [[ "$mode" == "seq" ]]; then
        step "Rendering custom: $MANUAL_NAME (sequential, theme: ${THEME_NAMES[$theme]})..."
        "$SEQ_BIN" --cx "$MANUAL_CX" --cy "$MANUAL_CY" --zoom "$MANUAL_ZOOM" \
                   --maxiter "$MANUAL_ITER" --cname "$MANUAL_NAME" --theme "$theme"
    else
        step "Rendering custom: $MANUAL_NAME (${threads} threads, theme: ${THEME_NAMES[$theme]})..."
        "$OMP_BIN" "$threads" --cx "$MANUAL_CX" --cy "$MANUAL_CY" --zoom "$MANUAL_ZOOM" \
                   --maxiter "$MANUAL_ITER" --cname "$MANUAL_NAME" --theme "$theme"
    fi
}

# ── Benchmark ──────────────────────────────────────────────────────────────────
do_benchmark() {
    require_bins || return 1
    mkdir -p results

    info "Benchmarking seahorse and vortex across thread counts..."
    echo ""

    # Plain variables — compatible with bash 3.2
    local SEQ_SH="" SEQ_VX=""
    local PAR_SH_1="" PAR_VX_1="" PAR_SH_2="" PAR_VX_2=""
    local PAR_SH_4="" PAR_VX_4="" PAR_SH_8="" PAR_VX_8=""

    step "Running sequential baseline..."
    OUT=$("$SEQ_BIN" 0 2>/dev/null)
    SEQ_SH=$(echo "$OUT" | grep "^TIME_seahorse=" | cut -d= -f2)
    printf "     %-16s ${GR}%s s${NC}\n" "seahorse" "$SEQ_SH"

    OUT=$("$SEQ_BIN" 1 2>/dev/null)
    SEQ_VX=$(echo "$OUT" | grep "^TIME_vortex=" | cut -d= -f2)
    printf "     %-16s ${GR}%s s${NC}\n" "vortex" "$SEQ_VX"

    for T in "${THREAD_COUNTS[@]}"; do
        echo ""
        step "Running parallel  T=${T}..."
        OUT=$("$OMP_BIN" "$T" 2>/dev/null)
        SH=$(echo "$OUT" | grep "^TIME_seahorse=" | cut -d= -f2)
        VX=$(echo "$OUT" | grep "^TIME_vortex="   | cut -d= -f2)
        eval "PAR_SH_${T}='$SH'"
        eval "PAR_VX_${T}='$VX'"
        SP_SH=$(awk "BEGIN {printf \"%.2f\", $SEQ_SH / $SH}")
        SP_VX=$(awk "BEGIN {printf \"%.2f\", $SEQ_VX / $VX}")
        printf "     %-16s ${GR}%s s${NC}  (${OR}%sx${NC})\n" "seahorse" "$SH" "$SP_SH"
        printf "     %-16s ${GR}%s s${NC}  (${OR}%sx${NC})\n" "vortex"   "$VX" "$SP_VX"
    done

    local times_file="results/benchmark_times.txt"
    {
        printf "SEQ_seahorse=%s\n" "$SEQ_SH"
        printf "SEQ_vortex=%s\n"   "$SEQ_VX"
        for T in "${THREAD_COUNTS[@]}"; do
            eval "SH=\$PAR_SH_${T}"; eval "VX=\$PAR_VX_${T}"
            printf "T%s_seahorse=%s\n" "$T" "$SH"
            printf "T%s_vortex=%s\n"   "$T" "$VX"
        done
    } > "$times_file"

    echo ""
    success "Timing data saved to $times_file"
    echo ""

    # Print formatted table
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
    printf "  ${BW}└────────────┴─────────────┴──────────┴────────────┴──────────┘${NC}\n"
}

do_gen_table() {
    if ! command -v python3 &>/dev/null; then
        error "python3 not found."
        warn "Install: brew install python3 (macOS) or sudo apt install python3 python3-pip (Linux)"
        warn "Then:    pip3 install matplotlib"
        return 1
    fi
    step "Generating speedup table and chart..."
    if python3 scripts/gen_table.py; then
        success "results/speedup_table.png"
        success "results/speedup_chart.png"
    else
        error "gen_table.py failed — run: pip3 install matplotlib"
    fi
}

# ── Run everything ─────────────────────────────────────────────────────────────
do_all() {
    local steps=4
    echo ""
    printf "  ${OR}[1/${steps}]${NC} ${BW}Building...${NC}           "
    if do_build &>/dev/null; then
        printf "${GR}✔${NC}\n"
    else
        printf "${RD}✘${NC}\n"; error "Build failed."; return 1
    fi

    printf "  ${OR}[2/${steps}]${NC} ${BW}Rendering presets...${NC}  "
    local ok=1
    "$OMP_BIN" 8 --preset 0 &>/dev/null || ok=0
    "$OMP_BIN" 8 --preset 1 &>/dev/null || ok=0
    # Also render theme 0 seq for README gallery images
    "$SEQ_BIN" 0 &>/dev/null || ok=0
    "$SEQ_BIN" 1 &>/dev/null || ok=0
    [[ $ok -eq 1 ]] && printf "${GR}✔${NC}\n" || printf "${RD}✘${NC}\n"

    printf "  ${OR}[3/${steps}]${NC} ${BW}Benchmarking...${NC}       "
    if do_benchmark &>/dev/null; then printf "${GR}✔${NC}\n"; else printf "${RD}✘${NC}\n"; fi

    printf "  ${OR}[4/${steps}]${NC} ${BW}Generating outputs...${NC} "
    if do_gen_table &>/dev/null; then printf "${GR}✔${NC}\n"; else printf "${RD}✘${NC}\n"; fi

    echo ""
    printf "${GR}  ══ Done. All files in results/ ══${NC}\n\n"
}

# ── Menu actions ───────────────────────────────────────────────────────────────

action_build() {
    header "Build Project"
    do_build
    echo ""
    success "Build complete."
    pause
}

action_render() {
    header "Render Image"
    require_bins || { pause; return; }

    echo ""
    printf "  ${BW}Step 1 — Choose zoom preset${NC}\n\n"
    MANUAL_RENDER=0
    CHOSEN_PIDX=0
    CHOSEN_THEME=0
    choose_preset

    echo ""
    printf "  ${BW}Step 2 — Choose color theme${NC}\n\n"
    choose_theme

    echo ""
    printf "  ${BW}Step 3 — Choose render mode${NC}\n\n"
    choose_mode

    if [[ $MANUAL_RENDER -eq 1 ]]; then
        do_render_custom "$CHOSEN_THEME" "$RENDER_MODE" "$RENDER_THREADS"
    else
        do_render_one "$CHOSEN_PIDX" "$CHOSEN_THEME" "$RENDER_MODE" "$RENDER_THREADS"
    fi
    pause
}

action_benchmark() {
    header "Run Benchmark"
    do_benchmark
    pause
}

action_gen_table() {
    header "Generate Speedup Table + Chart"
    do_gen_table
    pause
}

action_all() {
    header "Run Everything"
    do_all
    pause
}

action_clean() {
    header "Clean"
    step "Removing binaries and generated images..."
    rm -rf bin 2>/dev/null || true
    find results -name "*.png" ! -name "seahorse.png" ! -name "vortex.png" \
         -delete 2>/dev/null || true
    echo ""
    success "Removed: bin/"
    success "Removed: results/*.png  (gallery images kept)"
    warn "results/benchmark_times.txt kept."
    pause
}

action_help() {
    header "Help"
    printf "  ${BW}MENU OPTIONS${NC}\n\n"

    printf "  ${OR}1) Build project${NC}\n"
    printf "     Compiles bin/mandelbrot_seq and bin/mandelbrot_omp.\n"
    printf "     Auto-detects gcc-14/gcc-13 or clang+libomp on macOS.\n\n"

    printf "  ${OR}2) Render image${NC}\n"
    printf "     Three-step submenu: choose zoom → color theme → mode.\n"
    printf "     Modes: Sequential or Parallel (choose thread count).\n"
    printf "     Manual input: enter custom cx/cy/zoom/name (validated).\n"
    printf "     Output: results/custom_<name>.png\n\n"

    printf "  ${OR}3) Run benchmark${NC}\n"
    printf "     Times seahorse + vortex at seq baseline and 1, 2, 4, 8 threads.\n"
    printf "     Saves results/benchmark_times.txt.\n"
    printf "     Prints formatted speedup table to terminal.\n\n"

    printf "  ${OR}4) Generate speedup table + chart${NC}\n"
    printf "     Runs scripts/gen_table.py (requires: pip3 install matplotlib).\n"
    printf "     Output: results/speedup_table.png, results/speedup_chart.png\n\n"

    printf "  ${OR}5) Run everything${NC}\n"
    printf "     Build → render seahorse + vortex (8 threads) → benchmark → table.\n\n"

    printf "  ${OR}6) Clean${NC}\n"
    printf "     Removes bin/ and results/*.png (keeps gallery + timing data).\n\n"

    printf "  ${OR}7) Help${NC}\n"
    printf "     This screen.\n\n"

    printf "  ${BW}HOW TO ADD A PRESET${NC}\n"
    printf "     Edit the PRESETS[] array in both src/mandelbrot_seq.c\n"
    printf "     and src/mandelbrot_omp.c, then add a matching entry to\n"
    printf "     PRESET_NAMES / PRESET_LABELS / PRESET_CX / PRESET_CY /\n"
    printf "     PRESET_ZOOM / PRESET_ITER arrays in run.sh.\n"
    printf "     Increment NUM_PRESETS in both .c files.\n\n"

    printf "  ${BW}HOW TO ADD A COLOR THEME${NC}\n"
    printf "     Add a 6-stop [R,G,B] palette row to THEMES[4][6][3] in\n"
    printf "     both .c files, add a name to THEME_NAMES[] and\n"
    printf "     THEME_DISPLAY[], and update THEME_NAMES in run.sh.\n\n"

    printf "  ${BW}INSTALL PYTHON3 (for speedup charts)${NC}\n"
    printf "     macOS:  brew install python3 && pip3 install matplotlib\n"
    printf "     Linux:  sudo apt install python3-pip && pip3 install matplotlib\n\n"

    printf "  ${BW}FULL FILE STRUCTURE${NC}\n"
    printf "     .\n"
    printf "     ├── src/mandelbrot_seq.c      Sequential renderer\n"
    printf "     ├── src/mandelbrot_omp.c      OpenMP parallel renderer\n"
    printf "     ├── src/png_writer.h          Zero-dependency PNG encoder\n"
    printf "     ├── scripts/benchmark.sh      Timing harness\n"
    printf "     ├── scripts/gen_table.py      Speedup table + chart\n"
    printf "     ├── results/                  Generated images + timing data\n"
    printf "     ├── run.sh                    This interactive launcher\n"
    printf "     ├── Makefile                  Traditional build system\n"
    printf "     ├── LICENSE                   MIT\n"
    printf "     ├── CONTRIBUTING.md\n"
    printf "     ├── .gitignore\n"
    printf "     └── README.md\n\n"

    printf "  ${BW}MANUAL BINARY USAGE${NC}\n"
    printf "     bin/mandelbrot_seq 0 --theme 2\n"
    printf "     bin/mandelbrot_omp 4 --preset 1 --theme 0\n"
    printf "     bin/mandelbrot_omp 8 --cx -0.745 --cy 0.112 --zoom 0.001 --cname myzoom\n\n"

    pause
}

# ── Main menu ──────────────────────────────────────────────────────────────────
show_menu() {
    clear
    printf "${OR}╔══════════════════════════════════════╗${NC}\n"
    printf "${OR}║${NC}${BW}  Mandelbrot OpenMP — Project Menu   ${NC}${OR}║${NC}\n"
    printf "${OR}╚══════════════════════════════════════╝${NC}\n"
    printf "  ${OR}1)${NC} Build project\n"
    printf "  ${OR}2)${NC} Render image\n"
    printf "  ${OR}3)${NC} Run benchmark\n"
    printf "  ${OR}4)${NC} Generate speedup table + chart\n"
    printf "  ${OR}5)${NC} Run everything\n"
    printf "  ${OR}6)${NC} Clean\n"
    printf "  ${OR}7)${NC} Help\n"
    printf "  ${OR}0)${NC} Exit\n"
    printf "${OR}══════════════════════════════════════${NC}\n"
    printf "${BW}Select option: ${NC}"
}

while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) action_build        ;;
        2) action_render       ;;
        3) action_benchmark    ;;
        4) action_gen_table    ;;
        5) action_all          ;;
        6) action_clean        ;;
        7) action_help         ;;
        0)
            printf "\n${OR}  Goodbye.${NC}\n\n"
            exit 0
            ;;
        *)
            printf "\n"
            error "Invalid option: '$choice'"
            sleep 1
            ;;
    esac
done
