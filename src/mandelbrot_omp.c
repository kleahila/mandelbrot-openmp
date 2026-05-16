/*
 * mandelbrot_omp.c — Deep Zoom Mandelbrot (Parallel OpenMP)
 * CEN 330 - Parallel Programming Term Project
 *
 * Compile (Linux):  gcc -O2 -Wall -Wextra -fopenmp -o bin/mandelbrot_omp src/mandelbrot_omp.c -lm -lpthread
 * Compile (macOS):  clang -O2 -Wall -Wextra -Xpreprocessor -fopenmp \
 *                     -I/opt/homebrew/opt/libomp/include \
 *                     -L/opt/homebrew/opt/libomp/lib -lomp \
 *                     -o bin/mandelbrot_omp src/mandelbrot_omp.c -lm
 *
 * Run:  bin/mandelbrot_omp [num_threads] [--theme N] [--preset N]
 *       bin/mandelbrot_omp 4 --cx -0.745 --cy 0.112 --zoom 0.001 --cname myzoom [--theme N]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <omp.h>
#include <pthread.h>
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

/* ── Progress thread shared state ─────────────────────────────────────────── */
typedef struct {
    volatile int    rows_done;   /* atomic via #pragma omp atomic  */
    volatile int    stop;        /* set by main after parallel region */
    int             next_snap;   /* next snapshot pct to save (10..100) */
    unsigned char  *image;       /* shared pixel buffer (memset 0 before use) */
    const char     *preset_name;
    double          start_time;  /* omp_get_wtime() before parallel region */
    int             num_threads;
} ProgState;

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

static void draw_progress(int done, int total, double elapsed, int threads)
{
    int pct    = (total > 0) ? (done * 100) / total : 100;
    int filled = pct / 5;
    double eta = (done > 0 && done < total) ? elapsed * (total - done) / (double)done : 0.0;
    fprintf(stderr, "\r  [");
    for (int i = 0; i < 20; i++)
        fputs(i < filled ? "\xe2\x96\x88" : "\xe2\x96\x91", stderr);
    fprintf(stderr, "] %3d%% | Row %4d/%-4d | T=%-2d | Elapsed: %5.1fs | ETA: %5.1fs   ",
            pct, done, total, threads, elapsed, eta);
    fflush(stderr);
}

static void save_snapshot(const char *preset_name, int pct, const unsigned char *image)
{
    /* Snapshot copies current image so omp threads can keep writing */
    unsigned char *snap = (unsigned char *)malloc(WIDTH * HEIGHT * 3);
    if (!snap) return;
    memcpy(snap, image, WIDTH * HEIGHT * 3);

    char path[256];
    snprintf(path, sizeof(path), "results/%s_snap_%d.png", preset_name, pct);
    write_png(path, WIDTH, HEIGHT, snap);
    free(snap);

    fprintf(stderr, "\n  \xe2\x86\x92 Snapshot saved: %s\n", path);
}

static void *progress_fn(void *arg)
{
    ProgState *s = (ProgState *)arg;
    struct timespec ts = {0, 100000000L};  /* 100 ms */

    while (!s->stop) {
        nanosleep(&ts, NULL);
        if (s->stop) break;

        int done    = s->rows_done;
        double elap = omp_get_wtime() - s->start_time;
        draw_progress(done, HEIGHT, elap, s->num_threads);

        int pct = (done * 100) / HEIGHT;
        while (s->next_snap <= pct && s->next_snap <= 90) {
            save_snapshot(s->preset_name, s->next_snap, s->image);
            s->next_snap += 10;
        }
    }

    /* Final bar at 100% */
    double elap = omp_get_wtime() - s->start_time;
    draw_progress(HEIGHT, HEIGHT, elap, s->num_threads);
    fprintf(stderr, "\n");
    return NULL;
}

static void make_outpath(char *buf, size_t sz, const char *name, int num_threads, int theme)
{
    if (theme == 0)
        snprintf(buf, sz, "results/%s_%dt_classic.png", name, num_threads);
    else
        snprintf(buf, sz, "results/%s_%dt_%s.png", name, num_threads, THEME_NAMES[theme]);
}

static double render_one(const Preset *p, int num_threads, int theme, unsigned char *image)
{
    memset(image, 0, WIDTH * HEIGHT * 3);

    double aspect = (double)WIDTH / HEIGHT;
    double x_min  = p->cx - p->zoom * aspect;
    double x_max  = p->cx + p->zoom * aspect;
    double y_min  = p->cy - p->zoom;
    double y_max  = p->cy + p->zoom;

    ProgState ps;
    ps.rows_done   = 0;
    ps.stop        = 0;
    ps.next_snap   = 10;
    ps.image       = image;
    ps.preset_name = p->name;
    ps.num_threads = num_threads;

    omp_set_num_threads(num_threads);
    ps.start_time = omp_get_wtime();

    pthread_t tid;
    pthread_create(&tid, NULL, progress_fn, &ps);

#pragma omp parallel for schedule(dynamic, 1)
    for (int py = 0; py < HEIGHT; py++) {
        for (int px = 0; px < WIDTH; px++) {
            double cr = x_min + (x_max - x_min) * px / (double)WIDTH;
            double ci = y_min + (y_max - y_min) * py / (double)HEIGHT;
            unsigned char r, g, b;
            color_pixel(mandelbrot_iter(cr, ci, p->max_iter), p->max_iter, theme, &r, &g, &b);
            int base = (py * WIDTH + px) * 3;
            image[base] = r; image[base+1] = g; image[base+2] = b;
        }
        #pragma omp atomic
        ps.rows_done++;
    }

    double elapsed = omp_get_wtime() - ps.start_time;
    ps.stop = 1;
    pthread_join(tid, NULL);

    /* Save any snapshots the progress thread missed (e.g. very fast renders) */
    while (ps.next_snap <= 100) {
        save_snapshot(p->name, ps.next_snap, image);
        ps.next_snap += 10;
    }

    return elapsed;
}

int main(int argc, char *argv[])
{
    int    num_threads  = 4;
    int    theme        = 0;
    int    preset_idx   = -1;  /* -1 = all */
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
            if (v >= 1) num_threads = v;
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

        double elapsed = render_one(&cp, num_threads, theme, image);

        char path[256];
        snprintf(path, sizeof(path), "results/custom_%s_%dt_%s.png",
                 custom_name, num_threads, THEME_NAMES[theme]);
        write_png(path, WIDTH, HEIGHT, image);

        printf("\n");
        printf("  Preset    : %s (custom)\n", custom_name);
        printf("  Threads   : %d\n",          num_threads);
        printf("  Time      : %.3fs\n",        elapsed);
        printf("  Theme     : %s\n",           THEME_DISPLAY[theme]);
        printf("  Output    : %s\n",           path);
        printf("  Snapshots : results/%s_snap_10.png ... %s_snap_100.png\n\n",
               custom_name, custom_name);
        printf("TIME_%s=%.6f\n", custom_name, elapsed);
    } else {
        int first = (preset_idx >= 0) ? preset_idx : 0;
        int last  = (preset_idx >= 0) ? preset_idx : NUM_PRESETS - 1;

        double times[NUM_PRESETS] = {0};
        for (int i = first; i <= last; i++) {
            const Preset *p = &PRESETS[i];
            times[i] = render_one(p, num_threads, theme, image);

            char path[256];
            make_outpath(path, sizeof(path), p->name, num_threads, theme);
            write_png(path, WIDTH, HEIGHT, image);

            printf("\n");
            printf("  Preset    : %s\n",   p->display_name);
            printf("  Threads   : %d\n",   num_threads);
            printf("  Time      : %.3fs\n", times[i]);
            printf("  Theme     : %s\n",   THEME_DISPLAY[theme]);
            printf("  Output    : %s\n",   path);
            printf("  Snapshots : results/%s_snap_10.png ... %s_snap_100.png\n\n",
                   p->name, p->name);
        }

        /* Machine-parseable lines for benchmark.sh */
        for (int i = first; i <= last; i++)
            printf("TIME_%s=%.6f\n", PRESETS[i].name, times[i]);
    }

    free(image);
    return 0;
}
