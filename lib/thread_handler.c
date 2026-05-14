#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#include <process.h>
#define change_dir _chdir
#else
#include <sys/wait.h>
#include <unistd.h>
#define change_dir chdir
#endif

typedef struct {
    const char *cwd;
    const char *shell_command;
    char **argv;
    int exit_code;
} thread_task_t;

static void *run_worker(void *data) {
    thread_task_t *task = (thread_task_t *)data;

    if (task->cwd != NULL && change_dir(task->cwd) != 0) {
        fprintf(stderr, "[thread_handler] chdir impossible vers '%s': %s\n", task->cwd, strerror(errno));
        task->exit_code = 127;
        return NULL;
    }

#ifdef _WIN32
    if (task->shell_command != NULL) {
        int rc = system(task->shell_command);
        task->exit_code = rc < 0 ? 127 : rc;
        return NULL;
    }

    int rc = _spawnvp(_P_WAIT, task->argv[0], (const char * const *)task->argv);
    if (rc < 0) {
        fprintf(stderr, "[thread_handler] spawn impossible: %s\n", strerror(errno));
        task->exit_code = 127;
    } else {
        task->exit_code = rc;
    }
    return NULL;
#else
    if (task->shell_command != NULL) {
        int rc = system(task->shell_command);
        if (rc < 0) {
            task->exit_code = 127;
        } else if (WIFEXITED(rc)) {
            task->exit_code = WEXITSTATUS(rc);
        } else if (WIFSIGNALED(rc)) {
            task->exit_code = 128 + WTERMSIG(rc);
        } else {
            task->exit_code = 127;
        }
        return NULL;
    }

    pid_t pid;
    int status;

    pid = fork();
    if (pid < 0) {
        fprintf(stderr, "[thread_handler] fork impossible: %s\n", strerror(errno));
        task->exit_code = 127;
        return NULL;
    }

    if (pid == 0) {
        execvp(task->argv[0], task->argv);
        fprintf(stderr, "[thread_handler] execvp impossible: %s\n", strerror(errno));
        _exit(127);
    }

    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "[thread_handler] waitpid impossible: %s\n", strerror(errno));
        task->exit_code = 127;
        return NULL;
    }

    if (WIFEXITED(status)) {
        task->exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        task->exit_code = 128 + WTERMSIG(status);
    } else {
        task->exit_code = 127;
    }

    return NULL;
#endif
}

int main(int argc, char **argv) {
    pthread_t thread;
    thread_task_t task;
    int rc;
    int first_arg = 1;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s [--chdir repertoire] <programme> [arguments...]\n", argv[0]);
        return 101;
    }

    task.cwd = NULL;
    task.shell_command = NULL;

    if (argc >= 4 && strcmp(argv[1], "--chdir") == 0) {
        task.cwd = argv[2];
        first_arg = 3;
    }

    if (first_arg + 1 < argc && strcmp(argv[first_arg], "--command") == 0) {
        task.shell_command = argv[first_arg + 1];
        task.argv = NULL;
        task.exit_code = 0;
    } else {
        task.argv = &argv[first_arg];
        task.exit_code = 0;
    }

    if (first_arg >= argc) {
        fprintf(stderr, "Usage: %s [--chdir repertoire] <programme> [arguments...]\n", argv[0]);
        return 101;
    }

    rc = pthread_create(&thread, NULL, run_worker, &task);
    if (rc != 0) {
        fprintf(stderr, "[thread_handler] pthread_create impossible: %s\n", strerror(rc));
        return 127;
    }

    rc = pthread_join(thread, NULL);
    if (rc != 0) {
        fprintf(stderr, "[thread_handler] pthread_join impossible: %s\n", strerror(rc));
        return 127;
    }

    return task.exit_code;
}
