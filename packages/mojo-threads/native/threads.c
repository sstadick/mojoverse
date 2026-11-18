/* Opaque pthread layouts belong to the platform C compiler, not Mojo. */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#ifdef __linux__
#include <sched.h>
#endif

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    pthread_t thread;
    intptr_t (*entry)(intptr_t);
    intptr_t context;
    int started;
} Worker;

static void checked(int code) {
    if (code) {
        fprintf(stderr, "mojo-threads: pthread operation failed: %d\n", code);
        abort();
    }
}
void *mt_worker_new(void) {
    Worker *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    int code = pthread_mutex_init(&s->mutex, NULL);
    if (code) { free(s); return NULL; }
    code = pthread_cond_init(&s->changed, NULL);
    if (code) { checked(pthread_mutex_destroy(&s->mutex)); free(s); return NULL; }
    return s;
}
void mt_lock(Worker *s) { checked(pthread_mutex_lock(&s->mutex)); }
void mt_unlock(Worker *s) { checked(pthread_mutex_unlock(&s->mutex)); }
void mt_wait(Worker *s) { checked(pthread_cond_wait(&s->changed, &s->mutex)); }
void mt_notify_all(Worker *s) { checked(pthread_cond_broadcast(&s->changed)); }
static void *run_worker(void *context) {
    Worker *s = context;
    /* Match Mojo's C-ABI Int callback exactly; pthread's entry uses void*. */
    (void)s->entry(s->context);
    return NULL;
}
int mt_start(Worker *s, intptr_t (*entry)(intptr_t), intptr_t context) {
    if (s->started) return EBUSY;
    s->entry = entry;
    s->context = context;
    int code = pthread_create(&s->thread, NULL, run_worker, s);
    if (!code) s->started = 1;
    return code;
}
void mt_join(Worker *s) {
    if (s->started) {
        checked(pthread_join(s->thread, NULL));
        s->started = 0;
    }
}
void mt_worker_free(Worker *s) {
    if (!s) return;
    if (s->started) {
        fputs("mojo-threads: join before destroying worker\n", stderr);
        abort();
    }
    checked(pthread_cond_destroy(&s->changed));
    checked(pthread_mutex_destroy(&s->mutex));
    free(s);
}
int mt_cpus(void) {
#ifdef __linux__
    cpu_set_t mask;
    if (!sched_getaffinity(0, sizeof(mask), &mask)) {
        int count = CPU_COUNT(&mask);
        if (count > 0) return count;
    }
#endif
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
}
