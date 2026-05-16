#!/usr/bin/env python3
"""
scripts/gen_table.py
Generate light-themed speedup table and Amdahl's Law chart PNGs.

Input:  results/benchmark_times.txt  (written by benchmark.sh)
Output: results/speedup_table.png    (1800 x 500 px)
        results/speedup_chart.png    (1400 x 700 px)

Usage:  python3 scripts/gen_table.py
"""

import os
import sys

# ── Palette (light mode) ──────────────────────────────────────────────────────
BG       = '#ffffff'
HDR_BG   = '#f97316'   # orange header
HDR_FG   = '#ffffff'
ROW_ODD  = '#ffffff'
ROW_EVN  = '#f9f9f9'
FG       = '#111111'
ORANGE   = '#f97316'
DARK_OR  = '#c05a10'
BORDER   = '#dddddd'
GRAY_DIM = '#cccccc'

# ── Placeholder timing data ───────────────────────────────────────────────────
PLACEHOLDER = {
    'SEQ_seahorse': 12.450, 'SEQ_vortex':  9.820,
    'T1_seahorse':  12.380, 'T1_vortex':   9.760,
    'T2_seahorse':   6.310, 'T2_vortex':   4.990,
    'T4_seahorse':   3.190, 'T4_vortex':   2.520,
    'T8_seahorse':   1.650, 'T8_vortex':   1.310,
}


def load_times(path):
    if not os.path.exists(path):
        return None
    data = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if '=' not in line:
                continue
            k, _, v = line.partition('=')
            try:
                data[k.strip()] = float(v.strip())
            except ValueError:
                pass
    return data if data else None


def amdahl(p, n):
    """Theoretical speedup per Amdahl's Law given parallel fraction p and N threads."""
    return 1.0 / ((1.0 - p) + p / n)


def generate_table(rows, is_placeholder):
    """Render speedup_table.png (1800 x 500 px)."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches

    # 1800x500 at dpi=150 → figsize=(12, 3.333)
    fig = plt.figure(figsize=(12, 10/3), dpi=150, facecolor=BG)
    ax  = fig.add_axes([0, 0, 1, 1])
    ax.set_facecolor(BG)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')

    ax.text(0.5, 0.94,
            'OpenMP Speedup Analysis — Seahorse Valley & Vortex',
            ha='center', va='center', color=FG,
            fontsize=13, fontweight='bold', family='DejaVu Sans')

    if is_placeholder:
        ax.text(0.5, 0.875,
                '(placeholder values — run  make benchmark  to populate with real data)',
                ha='center', va='center', color='#999999',
                fontsize=8, fontstyle='italic', family='DejaVu Sans')

    # ── Table geometry ────────────────────────────────────────────────────────
    MARGIN   = 0.04
    TBL_W    = 1.0 - 2 * MARGIN
    TBL_TOP  = 0.84 if is_placeholder else 0.86
    HDR_H    = 0.130
    ROW_H    = 0.100

    CW = [0.155, 0.205, 0.210, 0.210, 0.220]
    col_x = [MARGIN]
    for w in CW[:-1]:
        col_x.append(col_x[-1] + w * TBL_W)

    col_labels = ['Threads', 'Seahorse\nTime (s)', 'Seahorse\nSpeedup',
                  'Vortex\nTime (s)', 'Vortex\nSpeedup']

    def add_cell(x, y, w, h, bg, text, color, size, weight):
        rect = mpatches.Rectangle((x, y), w, h,
                                   linewidth=0, facecolor=bg, clip_on=False)
        ax.add_patch(rect)
        ax.text(x + w/2, y + h/2, text,
                ha='center', va='center', color=color,
                fontsize=size, fontweight=weight,
                family='DejaVu Sans', linespacing=1.4, clip_on=False)

    # Header
    for label, cx, cw in zip(col_labels, col_x, CW):
        add_cell(cx, TBL_TOP - HDR_H, cw * TBL_W, HDR_H,
                 HDR_BG, label, HDR_FG, 9, 'bold')

    # Find best speedup values for bold orange highlight
    sh_sp_vals = [r[2] for r in rows[1:]]
    vx_sp_vals = [r[4] for r in rows[1:]]
    best_sh = max(sh_sp_vals) if sh_sp_vals else 0
    best_vx = max(vx_sp_vals) if vx_sp_vals else 0

    # Data rows
    for ri, (lbl, sh_t, sh_sp, vx_t, vx_sp) in enumerate(rows):
        y  = TBL_TOP - HDR_H - (ri + 1) * ROW_H
        bg = ROW_ODD if ri % 2 == 0 else ROW_EVN
        is_seq = (ri == 0)

        sh_col = ORANGE if (not is_seq and sh_sp == best_sh) else FG
        vx_col = ORANGE if (not is_seq and vx_sp == best_vx) else FG
        sh_wt  = 'bold'  if (not is_seq and sh_sp == best_sh) else 'normal'
        vx_wt  = 'bold'  if (not is_seq and vx_sp == best_vx) else 'normal'

        sp_sh = '1.00x' if is_seq else f'{sh_sp:.2f}x'
        sp_vx = '1.00x' if is_seq else f'{vx_sp:.2f}x'

        cells = [
            (lbl,           FG,     'bold'),
            (f'{sh_t:.3f}', FG,     'normal'),
            (sp_sh,         sh_col, sh_wt),
            (f'{vx_t:.3f}', FG,     'normal'),
            (sp_vx,         vx_col, vx_wt),
        ]
        for (txt, fc, fw), cx, cw in zip(cells, col_x, CW):
            add_cell(cx, y, cw * TBL_W, ROW_H, bg, txt, fc, 10, fw)

    # Grid lines
    tbl_h   = HDR_H + len(rows) * ROW_H
    tbl_btm = TBL_TOP - tbl_h
    sep_y   = TBL_TOP - HDR_H
    ax.plot([MARGIN, MARGIN + TBL_W], [sep_y, sep_y],
            color=BORDER, linewidth=0.9, clip_on=False)
    for cx in col_x[1:]:
        ax.plot([cx, cx], [tbl_btm, TBL_TOP],
                color=BORDER, linewidth=0.5, clip_on=False)
    border = mpatches.Rectangle(
        (MARGIN, tbl_btm), TBL_W, tbl_h,
        linewidth=1, edgecolor=BORDER, facecolor='none', clip_on=False)
    ax.add_patch(border)

    out = os.path.join('results', 'speedup_table.png')
    os.makedirs('results', exist_ok=True)
    fig.savefig(out, dpi=150, facecolor=BG, edgecolor='none')
    plt.close(fig)
    print(f'  ✔  results/speedup_table.png')


def generate_chart(rows):
    """Render speedup_chart.png (1400 x 700 px)."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    # X axis: Seq, 1, 2, 4, 8 threads
    # rows[0] = Sequential (speedup = 1.0)
    # rows[1..4] = 1, 2, 4, 8 threads
    x_pos    = [0, 1, 2, 3, 4]
    x_labels = ['Seq', '1', '2', '4', '8']
    # actual thread counts for Amdahl mapping
    x_threads = [1, 1, 2, 4, 8]

    actual_sh = [1.0] + [r[2] for r in rows[1:]]
    actual_vx = [1.0] + [r[4] for r in rows[1:]]

    # Amdahl curve P=0.98, evaluated at each x position's thread count
    p = 0.98
    amdahl_pts = [amdahl(p, n) for n in x_threads]

    # 1400x700 at dpi=150 → figsize=(9.333, 4.667)
    fig, ax = plt.subplots(figsize=(28/3, 14/3), dpi=150, facecolor=BG)
    ax.set_facecolor(BG)
    fig.patch.set_facecolor(BG)

    # Amdahl curve (dashed gray)
    ax.plot(x_pos, amdahl_pts, color=GRAY_DIM, linewidth=1.5,
            linestyle='--', label="Amdahl's Law (P=0.98)", zorder=1)

    # Seahorse actual (solid orange)
    ax.plot(x_pos, actual_sh, color=ORANGE, linewidth=2.2,
            marker='o', markersize=7, label='Seahorse Valley', zorder=3)

    # Vortex actual (solid dark orange)
    ax.plot(x_pos, actual_vx, color=DARK_OR, linewidth=2.2,
            marker='s', markersize=7, label='Vortex', zorder=3)

    ax.set_xlim(-0.3, 4.3)
    ax.set_ylim(0, max(9, max(actual_sh + actual_vx) * 1.2))
    ax.set_xticks(x_pos)
    ax.set_xticklabels(x_labels, color=FG)
    ax.tick_params(colors=FG, which='both')
    ax.spines['bottom'].set_color(BORDER)
    ax.spines['left'].set_color(BORDER)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.set_xlabel('Threads', color=FG, fontsize=11)
    ax.set_ylabel('Speedup', color=FG, fontsize=11)
    ax.set_title("OpenMP Speedup vs Amdahl's Law (P=0.98)",
                 color=FG, fontsize=13, fontweight='bold', pad=14)
    ax.grid(axis='y', color=BORDER, linewidth=0.6, linestyle='-')
    ax.legend(facecolor=BG, edgecolor=BORDER, labelcolor=FG,
              fontsize=9.5, framealpha=1, loc='upper left')

    # Annotate seahorse speedup values
    for xp, sp in zip(x_pos, actual_sh):
        ax.annotate(f'{sp:.2f}x', xy=(xp, sp), xytext=(4, 7),
                    textcoords='offset points', color=ORANGE,
                    fontsize=8, fontweight='bold')

    plt.tight_layout(pad=1.5)
    out = os.path.join('results', 'speedup_chart.png')
    os.makedirs('results', exist_ok=True)
    fig.savefig(out, dpi=150, facecolor=BG, edgecolor='none')
    plt.close(fig)
    print(f'  ✔  results/speedup_chart.png')


def main():
    try:
        import matplotlib
        matplotlib.use('Agg')
    except ImportError:
        print('Error: matplotlib not installed. Run: pip3 install matplotlib',
              file=sys.stderr)
        sys.exit(1)

    times_path    = os.path.join('results', 'benchmark_times.txt')
    raw           = load_times(times_path)
    is_placeholder = (raw is None)
    data          = raw if raw is not None else PLACEHOLDER

    seq_sh = data.get('SEQ_seahorse', PLACEHOLDER['SEQ_seahorse'])
    seq_vx = data.get('SEQ_vortex',   PLACEHOLDER['SEQ_vortex'])

    rows = [('Sequential', seq_sh, 1.0, seq_vx, 1.0)]
    for t in (1, 2, 4, 8):
        sh = data.get(f'T{t}_seahorse', PLACEHOLDER[f'T{t}_seahorse'])
        vx = data.get(f'T{t}_vortex',  PLACEHOLDER[f'T{t}_vortex'])
        rows.append((str(t), sh, seq_sh / sh, vx, seq_vx / vx))

    generate_table(rows, is_placeholder)
    generate_chart(rows)


if __name__ == '__main__':
    main()
