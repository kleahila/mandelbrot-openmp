# Contributing

Thank you for your interest in contributing to this Mandelbrot OpenMP renderer project!

## Clone and Build

```bash
git clone <repo-url>
cd Parallel_Programming_Term_Project
./run.sh          # interactive launcher (recommended)
# -- or --
make all          # traditional build
```

### Requirements

- GCC or Clang with OpenMP support
- GNU Make (optional)
- Python 3 + matplotlib (optional, for speedup charts):
  ```bash
  pip3 install matplotlib
  ```

---

## How to Add a New Zoom Preset

### 1. Edit `PRESETS[]` in both C files

Both `src/mandelbrot_seq.c` and `src/mandelbrot_omp.c` contain:

```c
typedef struct {
    const char *name;
    const char *display_name;
    double cx, cy, zoom;
    int max_iter;
} Preset;

static const Preset PRESETS[] = {
    {"seahorse", "Seahorse Valley", -0.7453954, 0.1125490, 0.00065, 2000},
    /* ... */
};
#define NUM_PRESETS 5
```

Append a new row in **both files** and increment `NUM_PRESETS`:

```c
{"spirals", "Spiral Galaxy", -0.7492000, 0.0834000, 0.00025, 2000},
```

### 2. Add matching entries to `run.sh`

Update the five preset arrays near the top of `run.sh`:

```bash
PRESET_NAMES=(...  "Spiral Galaxy")
PRESET_LABELS=(...  "spirals")
PRESET_CX=(...      "-0.7492000")
PRESET_CY=(...      "0.0834000")
PRESET_ZOOM=(...    "0.00025")
PRESET_ITER=(...    "2000")
NUM_PRESETS=6
```

### 3. Test

```bash
make all
bin/mandelbrot_seq 5          # renders new preset
bin/mandelbrot_omp 4 --preset 5
```

### Where to Find Coordinates

Use any online Mandelbrot explorer and record the center point (cx, cy) and the half-height of the view (zoom). Smaller zoom = deeper magnification.

---

## How to Add a New Color Theme

Both `.c` files share the same 4-theme structure:

```c
static const char *THEME_NAMES[]   = { "classic", "inferno", "ocean", "mono" };
static const char *THEME_DISPLAY[] = { "Seahorse Classic", "Inferno", "Ocean", "Monochrome" };

static const double THEMES[4][6][3] = {
    /* theme 0: Seahorse Classic */
    {{0.0,0.0,0.0}, {0.05,0.1,0.4}, {0.1,0.6,1.0},
     {1.0,1.0,1.0}, {1.0,0.5,0.0}, {0.6,0.0,0.0}},
    /* ... */
};
```

To add a new theme (e.g. Fire):

1. Change the array dimension `[4]` to `[5]` in both files.
2. Append your 6-stop `{R,G,B}` palette row (values 0.0–1.0).
3. Add `"fire"` to `THEME_NAMES[]` and `"Fire"` to `THEME_DISPLAY[]`.
4. Add `"Fire (red/yellow)"` to `THEME_NAMES` array in `run.sh`.
5. Update `NUM_THEMES=5` in `run.sh`.

---

## Code Style Notes

- **Indentation**: 4 spaces, no tabs
- **Line length**: ~100 characters maximum
- **Naming**: `snake_case` for functions and variables, `UPPER_CASE` for macros
- **Comments**: Only when the WHY is non-obvious — not the WHAT
- **No dead code**: Remove unused variables; fix all `-Wall -Wextra` warnings

### Example

```c
/* Dynamic scheduling balances load because boundary rows are computationally heavier. */
#pragma omp parallel for schedule(dynamic, 1)
for (int py = 0; py < HEIGHT; py++) {
    ...
    #pragma omp atomic
    ps.rows_done++;
}
```

---

## Testing Changes

```bash
# Build
make all

# Render to verify output visually
bin/mandelbrot_seq 0
open results/seahorse.png   # macOS
xdg-open results/seahorse.png   # Linux

# Run benchmark to measure performance impact
bash scripts/benchmark.sh

# Generate speedup charts
python3 scripts/gen_table.py
```

---

## Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-preset`
3. Edit only `src/`, `scripts/`, `run.sh` — do not commit generated `results/*.png`
4. Commit with a clear message:
   ```
   git commit -m "Add Spiral Galaxy preset at (-0.749, 0.083)"
   ```
5. Push and open a pull request

## Questions?

Run `./run.sh` → option 7 (Help) for in-terminal documentation, or check [README.md](README.md).
