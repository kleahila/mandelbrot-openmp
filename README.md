# Parallel Mandelbrot Set Rendering using OpenMP

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Language: C](https://img.shields.io/badge/language-C-00599C.svg)](<https://en.wikipedia.org/wiki/C_(programming_language)>)

A university term project for **Parallel Programming** demonstrating how OpenMP row-level parallelism accelerates Mandelbrot Set rendering. The project renders five deep-zoom locations at 1920×1080, supports four runtime color themes, prints a live terminal progress bar with automatic snapshot saves, and generates a full Amdahl's Law speedup analysis with publication-quality PNG charts.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Project Structure](#project-structure)
- [Interactive Launcher](#interactive-launcher)
- [Build](#build)
- [Run](#run)
- [Color Themes](#color-themes)
- [Configuration](#configuration)
- [Gallery](#gallery)
- [Performance](#performance)
- [Implementation Notes](#implementation-notes)
- [Authors](#authors)
- [License](#license)

---

## Quick Start

```bash
git clone <repo-url>
cd Parallel_Programming_Term_Project
./run.sh        # interactive launcher
```

First time? Choose **option 5 (Run everything)** — it builds, renders seahorse + vortex, benchmarks all thread counts, and generates the speedup table and chart in one go.

---

## Requirements

| Tool                  | Purpose          | Notes                           |
| --------------------- | ---------------- | ------------------------------- |
| GCC or Clang          | Compile C source | With OpenMP support             |
| GNU Make              | Build system     | Optional — `./run.sh` preferred |
| Python 3 + matplotlib | Speedup charts   | `pip3 install matplotlib`       |

### macOS

```bash
brew install libomp        # Required for OpenMP with Apple Clang
# OR: brew install gcc     # GCC with built-in OpenMP
```

### Linux

```bash
sudo apt install build-essential   # GCC + OpenMP included
sudo apt install python3-pip
pip3 install matplotlib
```

---

## Project Structure

```
.
├── src/
│   ├── mandelbrot_seq.c     # Sequential renderer (progress bar + snapshots)
│   ├── mandelbrot_omp.c     # OpenMP parallel renderer (progress thread + snapshots)
│   └── png_writer.h         # Zero-dependency single-header PNG encoder
├── scripts/
│   ├── benchmark.sh         # Benchmark harness (seq + 1/2/4/8 threads)
│   └── gen_table.py         # Speedup table + Amdahl's Law chart generator
├── results/
│   └── .gitkeep
├── run.sh                   # Interactive launcher (recommended entry point)
├── Makefile
├── LICENSE
├── CONTRIBUTING.md
├── .gitignore
└── README.md
```

---

## Interactive Launcher

```bash
./run.sh
```

```
╔══════════════════════════════════════╗
║  Mandelbrot OpenMP — Project Menu   ║
╚══════════════════════════════════════╝
  1) Build project
  2) Render image
  3) Run benchmark
  4) Generate speedup table + chart
  5) Run everything
  6) Clean
  7) Help
  0) Exit
```

### Option 2 — Render Image

Three-step flow:

**Step 1 — Choose zoom:**
Pick from 5 preset deep-zoom locations, or enter custom coordinates (cx, cy, zoom, max_iter). Manual input is validated (cx ∈ [−2.5, 1.0], cy ∈ [−1.25, 1.25], zoom > 0).

**Step 2 — Choose theme:**
Four runtime color themes — no recompile needed.

**Step 3 — Choose mode:**
Sequential or Parallel. For parallel, choose thread count (preset options: 1/2/4/8 or any custom integer ≥ 1).

### Option 3 — Benchmark

Times seahorse and vortex presets at sequential baseline plus 1, 2, 4, and 8 threads. Prints a live speedup table as each result arrives, then saves `results/benchmark_times.txt`.

### Option 5 — Run Everything

```
[1/4] Building...            ✔
[2/4] Rendering presets...   ✔
[3/4] Benchmarking...        ✔
[4/4] Generating outputs...  ✔
══ Done. All files in results/ ══
```

---

## Build

```bash
make          # both binaries — auto-detects OpenMP compiler and flags
make seq      # sequential only
make omp      # parallel only
make clean    # remove bin/ and generated PNGs
```

---

## Run

### Sequential

```bash
bin/mandelbrot_seq               # render all 5 presets, theme 0
bin/mandelbrot_seq 0             # preset 0 (Seahorse Valley) only
bin/mandelbrot_seq 0 --theme 2   # Seahorse with Ocean theme
```

### Parallel

```bash
bin/mandelbrot_omp 4                         # 4 threads, all 5 presets
bin/mandelbrot_omp 4 --preset 0 --theme 2   # Seahorse, 4 threads, Ocean
bin/mandelbrot_omp 8 --theme 0              # 8 threads, all presets, Classic
```

### Custom Coordinates

```bash
bin/mandelbrot_seq --cx -1.748 --cy 0.0 --zoom 0.0004 --cname spiral --theme 1
bin/mandelbrot_omp 8 --cx -0.745 --cy 0.112 --zoom 0.0003 --cname deep --maxiter 4000
```

### Benchmark

```bash
make benchmark
# — or —
bash scripts/benchmark.sh
```

---

## Color Themes

Passed via `--theme N` at runtime — no recompile needed. All themes use log-scaled 6-stop palettes.

| N   | Name             | Palette stops                                              |
| --- | ---------------- | ---------------------------------------------------------- |
| 0   | Seahorse Classic | black → dark blue → cyan → white → orange → dark red       |
| 1   | Inferno          | black → dark purple → red → orange → bright yellow → white |
| 2   | Ocean            | black → navy → teal → cyan → white → pale gold             |
| 3   | Monochrome       | black → dark gray → mid gray → light gray → white → white  |

Output filenames include the theme name for themes 1–3 (e.g. `seahorse_4t_ocean.png`).

---

## Configuration

### Zoom Presets

| Index | Name            | cx         | cy         | zoom    | iter |
| ----- | --------------- | ---------- | ---------- | ------- | ---- |
| 0     | Seahorse Valley | −0.7453954 | 0.1125490  | 0.00065 | 2000 |
| 1     | Vortex          | −0.7269820 | 0.1889580  | 0.00030 | 2000 |
| 2     | Elephant Valley | 0.3750001  | 0.0000010  | 0.00120 | 2000 |
| 3     | Lightning       | −0.1592295 | −1.0317437 | 0.00060 | 3000 |
| 4     | Mini Mandelbrot | −1.7499645 | 0.0000000  | 0.00050 | 2000 |

To add a preset: edit `PRESETS[]` in both `src/mandelbrot_seq.c` and `src/mandelbrot_omp.c`, increment `NUM_PRESETS`, and add matching entries to the arrays in `run.sh`. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Resolution

Change `WIDTH` and `HEIGHT` at the top of both `.c` files. Default is 1920×1080.

---

## Gallery

> Run `./run.sh` → option 5 to generate gallery images.

![Seahorse Valley](results/seahorse.png)

![Vortex](results/vortex.png)

---

## Performance

`gen_table.py` generates two outputs from `results/benchmark_times.txt`:

**`results/speedup_table.png`** — light-mode table (orange header, alternating rows, best speedup values highlighted in bold orange).

**`results/speedup_chart.png`** — line chart comparing actual speedup (Seahorse Valley and Vortex) against Amdahl's Law theoretical curve (P=0.98).

### Amdahl's Law

```
Speedup(N) = 1 / ((1 - P) + P/N)     P ≈ 0.98
```

| Threads | Amdahl (P=0.98) |
| ------- | --------------- |
| 1       | 1.00×           |
| 2       | 1.96×           |
| 4       | 3.77×           |
| 8       | 6.90×           |

The Mandelbrot computation has no sequential bottleneck (each pixel is independent), so P≈0.98 is a conservative estimate; actual speedup often tracks closely with the theoretical curve.

---

## Implementation Notes

### Why `schedule(dynamic, 1)`

Mandelbrot rows near the boundary of the set take far longer than rows inside or outside it. Static scheduling would leave some threads idle while others finish the complex boundary rows. Dynamic scheduling with chunk size 1 assigns each row to whichever thread is free next, which nearly eliminates load imbalance and produces near-linear speedup.

### No False Sharing

Each OpenMP thread writes to a distinct row of the image buffer: thread T writes `image[py * WIDTH * 3 ... (py+1)*WIDTH*3 - 1]`. Since `WIDTH * 3 = 5760` bytes >> 64-byte cache line, adjacent rows do not share cache lines and there is no false sharing.

### Progress Bar (Sequential)

The sequential binary updates the progress bar every 5 rows using `\r` on stderr, leaving stdout clean for the machine-parseable `TIME_*=` lines consumed by `benchmark.sh`.

### Progress Thread (Parallel)

The parallel binary spawns a dedicated POSIX thread that wakes every 100 ms, reads the `volatile int rows_done` counter (incremented with `#pragma omp atomic` after each row), redraws the progress bar on stderr, and triggers automatic snapshot saves at each 10% milestone. The progress thread runs concurrently with the OpenMP worker pool without interfering with the work distribution.

### Snapshots

## Both binaries save partial PNG snapshots at every 10% milestone (10%, 20%, …, 100%) as `results/<preset>_snap_NN.png`. The image buffer is `memset` to zero before rendering, so unrendered rows appear black in early snapshots, creating an informative view of render progress.

## License

[MIT License](LICENSE) © 2026 Klea Hila
