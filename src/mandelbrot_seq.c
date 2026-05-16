/*
 * mandelbrot_seq.c — Deep Zoom Mandelbrot (Sequential)
 * CEN 330 - Parallel Programming Term Project
 *
 * Compile (Linux):  gcc -O2 -Wall -Wextra -o bin/mandelbrot_seq src/mandelbrot_seq.c -lm
 * Compile (macOS):  clang -O2 -Wall -Wextra -o bin/mandelbrot_seq src/mandelbrot_seq.c -lm
 *
 * Run:  bin/mandelbrot_seq [preset_index] [--theme N]
 *       bin/mandelbrot_seq --cx -0.745 --cy 0.112 --zoom 0.001 --cname myzoom [--theme N]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "png_writer.h"

#define WIDTH  1920
#define HEIGHT 1080

typedef struct {
    const char *name;
    const char *display_name;
    double cx, cy, zoom;
    int max_iter;
} Preset;

static const Preset PRESETS[] = {
    {"seahorse", "Seahorse Valley", -0.7453954,  0.1125490, 0.00065, 2000},
    {"vortex",   "Vortex",         -0.7269820,  0.1889580, 0.00030, 2000},
};
#define NUM_PRESETS 2

static const char *THEME_NAMES[]   = { "classic", "inferno", "ocean", "mono" };
static const char *THEME_DISPLAY[] = { "Seahorse Classic", "Inferno", "Ocean", "Monochrome" };

static const double THEMES[4][6][3] = {
    /* 0: Seahorse Classic — black -> dark blue -> cyan -> white -> orange -> dark red */
    {{0.0,  0.0, 0.0}, {0.05, 0.1,  0.4 }, {0.1,  0.6,  1.0 },
     {1.0,  1.0, 1.0}, {1.0,  0.5,  0.0 }, {0.6,  0.0,  0.0 }},
    /* 1: Inferno — black -> dark purple -> red -> orange -> bright yellow -> white */
    {{0.0,  0.0, 0.0}, {0.18, 0.0,  0.25}, {0.7,  0.05, 0.1 },
     {0.95, 0.35,0.0}, {0.98, 0.85, 0.05}, {1.0,  1.0,  1.0 }},
    /* 2: Ocean — black -> navy -> teal -> cyan -> white -> pale gold */
    {{0.0,  0.0, 0.0}, {0.0,  0.05, 0.35}, {0.0,  0.45, 0.45},
     {0.0,  0.85,0.95},{1.0,  1.0,  1.0 }, {1.0,  0.97, 0.75}},
    /* 3: Monochrome — black -> dark gray -> mid gray -> light gray -> white -> white */
    {{0.0,  0.0, 0.0}, {0.18, 0.18, 0.18}, {0.42, 0.42, 0.42},
     {0.68, 0.68,0.68},{0.92, 0.92, 0.92}, {1.0,  1.0,  1.0 }},
};

static void color_pixel(int iter, int max_iter, int theme,
                         unsigned char *r, unsigned char *g, unsigned char *b)
{
    if (iter == max_iter) { *r = *g = *b = 0; return; }
    double t      = log(1.0 + (double)iter) / log(1.0 + (double)max_iter);
    double scaled = t * 5.0;
    int    idx    = (int)scaled;
    double frac   = scaled - idx;
    if (idx >= 5) { idx = 4; frac = 1.0; }
    *r = (unsigned char)((THEMES[theme][idx][0] + frac*(THEMES[theme][idx+1][0]-THEMES[theme][idx][0])) * 255.0);
    *g = (unsigned char)((THEMES[theme][idx][1] + frac*(THEMES[theme][idx+1][1]-THEMES[theme][idx][1])) * 255.0);
    *b = (unsigned char)((THEMES[theme][idx][2] + frac*(THEMES[theme][idx+1][2]-THEMES[theme][idx][2])) * 255.0);
}

static int mandelbrot_iter(double cr, double ci, int max_iter)
{
    double zr = 0.0, zi = 0.0;
    for (int i = 0; i < max_iter; i++) {
        double zr2 = zr*zr, zi2 = zi*zi;
        if (zr2 + zi2 > 4.0) return i;
        zi = 2.0*zr*zi + ci;
        zr = zr2 - zi2 + cr;
    }
    return max_iter;
}

static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void draw_progress(int row, int total, double elapsed)
{
    int pct    = (row * 100) / total;
    int filled = pct / 5;
    double eta = (row > 0 && row < total) ? elapsed * (total - row) / (double)row : 0.0;
    fprintf(stderr, "\r  [");
    for (int i = 0; i < 20; i++)
        fputs(i < filled ? "\xe2\x96\x88" : "\xe2\x96\x91", stderr);
    fprintf(stderr, "] %3d%% | Row %4d/%-4d | Elapsed: %5.1fs | ETA: %5.1fs   ",
            pct, row, total, elapsed, eta);
    fflush(stderr);
}

static void save_snapshot(const char *preset_name, int pct, const unsigned char *image)
{
    char path[256];
    snprintf(path, sizeof(path), "results/%s_snap_%d.png", preset_name, pct);
    write_png(path, WIDTH, HEIGHT, image);
    fprintf(stderr, "\n  \xe2\x86\x92 Snapshot saved: %s\n", path);
}

static void make_outpath(char *buf, size_t sz, const char *name, int theme)
{
    if (theme == 0)
        snprintf(buf, sz, "results/%s.png", name);
    else
        snprintf(buf, sz, "results/%s_%s.png", name, THEME_NAMES[theme]);
}

static void render_one(const Preset *p, int theme, unsigned char *image)
{
    memset(image, 0, WIDTH * HEIGHT * 3);

    double aspect = (double)WIDTH / HEIGHT;
    double x_min  = p->cx - p->zoom * aspect;
    double x_max  = p->cx + p->zoom * aspect;
    double y_min  = p->cy - p->zoom;
    double y_max  = p->cy + p->zoom;

    double t_start    = now_sec();
    int    next_snap  = 10;

    for (int py = 0; py < HEIGHT; py++) {
        for (int px = 0; px < WIDTH; px++) {
            double cr = x_min + (x_max - x_min) * px / (double)WIDTH;
            double ci = y_min + (y_max - y_min) * py / (double)HEIGHT;
            unsigned char r, g, b;
            color_pixel(mandelbrot_iter(cr, ci, p->max_iter), p->max_iter, theme, &r, &g, &b);
            int base = (py * WIDTH + px) * 3;
            image[base] = r; image[base+1] = g; image[base+2] = b;
        }

        if (py % 5 == 4 || py == HEIGHT - 1)
            draw_progress(py + 1, HEIGHT, now_sec() - t_start);

        int pct = ((py + 1) * 100) / HEIGHT;
        while (next_snap <= pct && next_snap <= 100) {
            draw_progress(py + 1, HEIGHT, now_sec() - t_start);
            save_snapshot(p->name, next_snap, image);
            next_snap += 10;
        }
    }
    fprintf(stderr, "\n");

    double elapsed = now_sec() - t_start;

    char path[256];
    make_outpath(path, sizeof(path), p->name, theme);
    write_png(path, WIDTH, HEIGHT, image);

    printf("\n");
    printf("  Preset    : %s\n",   p->display_name);
    printf("  Threads   : 1 (sequential)\n");
    printf("  Time      : %.3fs\n", elapsed);
    printf("  Theme     : %s\n",   THEME_DISPLAY[theme]);
    printf("  Output    : %s\n",   path);
    printf("  Snapshots : results/%s_snap_10.png ... %s_snap_100.png\n\n",
           p->name, p->name);

    /* Machine-parseable line for benchmark.sh */
    printf("TIME_%s=%.6f\n", p->name, elapsed);
}

int main(int argc, char *argv[])
{
    int    preset_idx   = -1;  /* -1 = all */
    int    theme        = 0;
    int    use_custom   = 0;
    double custom_cx    = 0.0, custom_cy = 0.0, custom_zoom = 0.001;
    int    custom_iter  = 2000;
    char   custom_name[64] = "custom";

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--theme") == 0 && i+1 < argc) {
            theme = atoi(argv[++i]);
            if (theme < 0 || theme > 3) theme = 0;
        } else if (strcmp(argv[i], "--preset") == 0 && i+1 < argc) {
            int v = atoi(argv[++i]);
            if (v >= 0 && v < NUM_PRESETS) preset_idx = v;
        } else if (strcmp(argv[i], "--cx") == 0 && i+1 < argc) {
            custom_cx = atof(argv[++i]); use_custom = 1;
        } else if (strcmp(argv[i], "--cy") == 0 && i+1 < argc) {
            custom_cy = atof(argv[++i]); use_custom = 1;
        } else if (strcmp(argv[i], "--zoom") == 0 && i+1 < argc) {
            custom_zoom = atof(argv[++i]); use_custom = 1;
        } else if (strcmp(argv[i], "--maxiter") == 0 && i+1 < argc) {
            custom_iter = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--cname") == 0 && i+1 < argc) {
            strncpy(custom_name, argv[++i], sizeof(custom_name) - 1);
            custom_name[sizeof(custom_name)-1] = '\0';
        } else if (argv[i][0] != '-') {
            int v = atoi(argv[i]);
            if (v >= 0 && v < NUM_PRESETS) preset_idx = v;
        }
    }

    unsigned char *image = malloc(WIDTH * HEIGHT * 3);
    if (!image) { fprintf(stderr, "Out of memory\n"); return 1; }

    if (use_custom) {
        Preset cp;
        cp.name         = custom_name;
        cp.display_name = custom_name;
        cp.cx           = custom_cx;
        cp.cy           = custom_cy;
        cp.zoom         = custom_zoom;
        cp.max_iter     = custom_iter;

        char cpath[256];
        snprintf(cpath, sizeof(cpath), "results/custom_%s.png", custom_name);

        render_one(&cp, theme, image);

        /* Override output path for custom */
        (void)cpath;
    } else {
        int first = (preset_idx >= 0) ? preset_idx : 0;
        int last  = (preset_idx >= 0) ? preset_idx : NUM_PRESETS - 1;
        for (int i = first; i <= last; i++)
            render_one(&PRESETS[i], theme, image);
    }

    free(image);
    return 0;
}
