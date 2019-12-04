#include <inttypes.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>

#define CL 64

static int debug = 0;

extern "C" {
typedef struct {
    uint32_t weight;
    uint16_t level;
    uint16_t winf:1;
    uint16_t rsvd:15;
} vertex_t;

#define VERTEX_PER_CL (CL/sizeof(vertex_t))
#define VERTEX(w,l,wi,li) (vertex_t) {  \
    .weight = (w),                      \
    .level = (l),                       \
    .winf = (wi),                       \
    .rsvd = 0                           \
}
#define IS_ACTIVE(v,curr_lvl) \
    ((v)->level == (curr_lvl))

typedef struct {
    uint32_t src;
    uint32_t dst;
    uint32_t weight;
    uint32_t rsvd;
} edge_t;

#define EDGE_PER_CL (CL/sizeof(edge_t))
#define EDGE(s,d,w) (edge_t) {  \
    .src = (s),                 \
    .dst = (d),                 \
    .weight = (w),              \
    .rsvd = 0                   \
}

typedef struct {
    uint32_t offset;
    uint32_t count;
} v2e_t;

typedef struct {
    uint32_t vertex;
    uint32_t weight;
} update_t;

#define UPDATE(v,w) (update_t) {   \
    .vertex = (v),      \
    .weight = (w)       \
}

#define UPDATE_PER_CL (CL/sizeof(update_t))

typedef struct {
      uint32_t edge_start_offset;
      uint32_t edge_start_cl;
      uint32_t num_edges;
      uint32_t num_cls;

      update_t *update_bin;
      uint32_t num_updates;
      uint32_t num_active_vertices;
} interval_t;

#define VERTEX_PER_INTERVAL 256
#define VERTEX_TO_INTERVAL(x) ((x)/VERTEX_PER_INTERVAL)
#define INTERVAL_TO_VERTEX(x) ((x)*VERTEX_PER_INTERVAL)

typedef struct {
    int num_v;
    int num_e;
    vertex_t *vertices;
    edge_t *edges;
    v2e_t *v2e;

    int num_intervals;
    interval_t *intervals;

} graph_t;

} /* C */

graph_t *graph_init(int num_v, int num_e, char *filename)
{
    int i, j;
    FILE *fp;
    uint32_t s, d;
    int num_intervals;

    if ((fp = fopen(filename, "r")) == NULL) {
        fprintf(stderr, "Cannot open file. Check the name.\n");
        return NULL;
    }

    graph_t *g = (graph_t *) malloc(sizeof(graph_t));
    g->num_v = num_v;
    g->num_e = num_e;
    g->vertices = (vertex_t *) malloc(sizeof(vertex_t) * num_v);
    g->edges = (edge_t *) malloc(sizeof(edge_t) * num_e);
    g->v2e = (v2e_t *) malloc(sizeof(v2e_t) * num_v);

    for (i = 0; i < num_v; i++) {
        g->vertices[i] = VERTEX(0, 0, 1, 1);
    }

    memset(g->edges, 0x0, num_e*sizeof(edge_t));
    memset(g->v2e, 0x0, num_v*sizeof(v2e_t));

    if (fscanf(fp, "%u %u\n", &s, &d) != EOF) {
        if (s >= num_v || d >= num_v) {
            goto error;
        }

        g->edges[0] = EDGE(s, d, (uint32_t)rand()%64);
        g->v2e[s].offset = 0;
        g->v2e[s].count++;
    }
        
    for (i = 1; i < num_e; i++) {
        if (fscanf(fp, "%u %u\n", &s, &d) != EOF) {
            g->edges[i] = EDGE(s, d, (uint32_t)rand()%64);
            g->v2e[s].count++;

            if (s != g->edges[i-1].src) {
                g->v2e[s].offset = i;
                if (s > g->edges[i-1].src + 1) {
                    for (j = g->edges[i-1].src + 1; j < s; j++) {
                        g->v2e[j].offset = i;
                    }
                }
            }
        }
    }

    fclose(fp);

    num_intervals = (num_v - 1) / VERTEX_PER_INTERVAL + 1;
    g->intervals = (interval_t *)malloc(sizeof(interval_t)*num_intervals);
    g->num_intervals = num_intervals;

    for (i = 0; i < num_intervals; i++) {
        int off = i * VERTEX_PER_INTERVAL;

        int start_off, end_off, ne;
        uint64_t start_cl, end_cl, ncl;
        if (i != num_intervals - 1) {
            start_off = g->v2e[i * VERTEX_PER_INTERVAL].offset;
            end_off = g->v2e[(i + 1) * VERTEX_PER_INTERVAL].offset;
            ne = end_off - start_off;
        }
        else {
            start_off = g->v2e[i * VERTEX_PER_INTERVAL].offset;
            end_off = g->num_e;
            ne = end_off - start_off;
        }

        start_cl = ((uint64_t) &g->edges[start_off]) / CL;
        end_cl = ((uint64_t) &g->edges[end_off]) / CL;

        if ((uint64_t) &g->edges[end_off] % CL != 0) {
            end_cl += 1;
        }

        ncl = end_cl - start_cl;

        g->intervals[i].edge_start_offset = start_off;
        g->intervals[i].edge_start_cl = start_cl;
        g->intervals[i].num_edges = ne;
        g->intervals[i].num_cls = ncl;

        g->intervals[i].update_bin = (update_t *)malloc(sizeof(update_t) * ne);
        g->intervals[i].num_updates = 0;
        g->intervals[i].num_active_vertices = 0;
    }

    return g;

error:
    free(g->vertices);
    free(g->edges);
    free(g->v2e);
    free(g);
    return NULL;
}

int sssp_sw(graph_t *g, int root)
{
    int have_update;
    int current_level;
    int i, j, k;

    if (root >= g->num_v) {
        return -EFAULT;
    }
    g->vertices[root].winf = 0;
    g->vertices[root].level = 1;
    g->intervals[VERTEX_TO_INTERVAL(root)].num_active_vertices = 1;
    have_update = 1;
    current_level = 1;

    while (have_update) {
        have_update = 0;
        int active_cnt = 0;

        if (debug) {
            printf("\n------------ level %d -------------\n", current_level);
        }

        /* scatter */
        for (i = 0; i < g->num_intervals; i++) {
            interval_t *curr = &g->intervals[i];
            if (curr->num_active_vertices == 0) {
                continue;
            }

            /* we need to set num_active_vertices to 0 */
            curr->num_active_vertices = 0;
            
            int update_cnt = 0;
            int start_vidx = INTERVAL_TO_VERTEX(i);
            int end_vidx = start_vidx + VERTEX_PER_INTERVAL;
            for (j = 0; j < curr->num_edges; j++) {
                edge_t *e = &g->edges[curr->edge_start_offset + j];
                vertex_t *src_v = &g->vertices[e->src];
                if (e->src >= start_vidx && e->src < end_vidx /* inside interval */
                        && IS_ACTIVE(src_v, current_level)) { /* src is active */
                    curr->update_bin[update_cnt] = UPDATE(e->dst, src_v->weight + e->weight);
                    update_cnt++;
                }
            }
            curr->num_updates = update_cnt;

            if (debug) {
                printf("interval %d: %d updates\n", i, update_cnt);
            }

            if (debug) {
                for (j = 0; j < curr->num_updates; j++) {
                    printf("[%d]: update: vertex %d to %d\n",
                            i,
                            curr->update_bin[j].vertex,
                            curr->update_bin[j].weight);
                }
            }
        }

        /* gather */
        for (i = 0; i < g->num_intervals; i++) {
            interval_t *curr = &g->intervals[i];
            if (curr->num_updates == 0) {
                continue;
            }

            for (j = 0; j < curr->num_updates; j++) {
                update_t *update = &curr->update_bin[j];
                vertex_t *update_vertex = &g->vertices[update->vertex];
                int vertex_interval = VERTEX_TO_INTERVAL(update->vertex);

                /* do the update */
                if (update_vertex->winf == 1 /* the value of the vertex is inf */
                        || update_vertex->weight > update->weight) {
                    if (debug) {
                        printf("interval %d: update interval %d vertex %d, %d -> %d\n",
                                j, vertex_interval, update->vertex,
                                update_vertex->winf?-1:update_vertex->weight,
                                update->weight);
                    }
                    update_vertex->weight = update->weight;
                    update_vertex->level = current_level + 1;
                    update_vertex->winf = 0;
                    g->intervals[vertex_interval].num_active_vertices++;
                    active_cnt++;
                }
            }

            curr->num_updates = 0;

        }

        for (i = 0; i < g->num_intervals; i++) {
            if (g->intervals[i].num_active_vertices != 0) {
                have_update = 1;
                break;
            }
        }

        printf("level %d: update %d vertices\n", current_level, active_cnt);
        fflush(stdout);

        current_level++;
    }

    return 0;
}
                    
int main(int argc, char *argv[])
{
    int opt;
    int num_v = -1, num_e = -1;
    int root = -1;
    char *filename = NULL;

    while ((opt = getopt (argc, argv, ":v:e:r:f:d")) != -1) {
        switch (opt) {
            case 'v':
                num_v = atoi(optarg);
                break;
            case 'e':
                num_e = atoi(optarg);
                break;
            case 'f':
                filename = optarg;
                break;
            case 'r':
                root = atoi(optarg);
                break;
            case 'd':
                debug = 1;
                break;
            case '?':
                printf("Unknown option: %c\n", opt);
                return -EINVAL;
        }
    }

    if (num_v < 0 || num_e < 0 || root < 0) {
        printf("Missing arguments.\n");
        return -EINVAL;
    }

    graph_t *graph = graph_init(num_v, num_e, filename);

    if (debug) {
        printf("read done\n");
    }

    if (graph == NULL) {
        return -ENOENT;
    }

    if (graph->num_v <= root) {
        return -EFAULT;
    }

    struct timeval before, after;
    gettimeofday(&before, NULL);


    sssp_sw(graph, root);

    int i, cnt = 0;
    for (i = 0; i < graph->num_v; i++) {
        if (graph->vertices[i].winf == 0) {
            cnt++;
        }
    }
    printf("vertex %d connects to %d of %d vertices\n", root, cnt, graph->num_v);

    gettimeofday(&after, NULL);
    printf("Time in seconds: %lf seconds\n",
            ((after.tv_sec - before.tv_sec)
                +(after.tv_usec - before.tv_usec)/1000000.0));

    return 0;
}

