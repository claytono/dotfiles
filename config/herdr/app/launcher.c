/*
 * Herdr.app launcher.
 *
 * macOS Local Network privacy attributes a process to the app at the root of
 * its launch chain. A herdr server started from a terminal belongs to that
 * terminal and loses LAN access once the terminal quits. When LaunchServices
 * starts this bundle, the bundle is that root app; the launcher then execs
 * herdr in place, so the server and every pane under it count as Herdr.app.
 *
 * The herdr wrapper (config/herdr/herdr-wrapper.sh) starts servers this way.
 * `open` passes neither arguments nor environment to the app, so the wrapper
 * leaves a launch request in LAUNCH_DIR instead: its environment, as a
 * NUL-separated *.env file. The launcher claims one request, runs the server
 * with that environment, and deletes the file. Requests older than
 * REQUEST_MAX_AGE seconds were left behind by a wrapper that gave up, and are
 * deleted unused. Without a usable request, as when opened from Finder, it
 * runs `herdr server` with launchd's environment.
 *
 * Keep this file and Info.plist stable. Privacy grants survived a change to
 * the bundle's code signature in testing, but Apple documents them as
 * following the signature.
 */
#include <dirent.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define LAUNCH_DIR "Library/Caches/net.oneill.herdr/launch"
#define REQUEST_MAX_AGE 30

/* Read a request's environment. Sets *stale and returns NULL for a request
   too old to belong to the launch in progress. */
static char **read_env_file(const char *path, int *stale) {
    *stale = 0;
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0)
        return NULL;
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_uid != getuid() || !S_ISREG(st.st_mode)) {
        close(fd);
        return NULL;
    }
    if (time(NULL) - st.st_mtime > REQUEST_MAX_AGE) {
        close(fd);
        *stale = 1;
        return NULL;
    }
    char *buf = malloc((size_t)st.st_size + 1);
    if (buf == NULL) {
        close(fd);
        return NULL;
    }
    size_t len = 0;
    while (len < (size_t)st.st_size) {
        ssize_t n = read(fd, buf + len, (size_t)st.st_size - len);
        if (n <= 0)
            break;
        len += (size_t)n;
    }
    close(fd);
    buf[len] = '\0';

    size_t count = 1;
    for (size_t i = 0; i < len; i++)
        if (buf[i] == '\0')
            count++;
    char **envp = calloc(count + 1, sizeof *envp);
    if (envp == NULL)
        return NULL;
    size_t n = 0;
    for (char *p = buf; p < buf + len; p += strlen(p) + 1)
        if (*p != '\0')
            envp[n++] = p;
    envp[n] = NULL;
    if (n == 0) {
        free(envp);
        free(buf);
        return NULL;
    }
    return envp;
}

/* Claim one pending request by renaming it, so concurrent launches each get
   a different one, then read it. Every stale request is deleted on the way,
   since each holds a whole environment; a fresh one that cannot be read means
   running without a request, not taking another launch's. */
static char **claim_request(const char *home) {
    char dir[1024];
    snprintf(dir, sizeof dir, "%s/" LAUNCH_DIR, home);
    DIR *d = opendir(dir);
    if (d == NULL)
        return NULL;
    char **envp = NULL;
    int claimed = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        size_t len = strlen(e->d_name);
        if (len < 5 || e->d_name[0] == '.' || strcmp(e->d_name + len - 4, ".env") != 0)
            continue;
        char from[2048], to[2048];
        snprintf(from, sizeof from, "%s/%s", dir, e->d_name);
        struct stat st;
        if (lstat(from, &st) == 0 && time(NULL) - st.st_mtime > REQUEST_MAX_AGE) {
            unlink(from);
            continue;
        }
        if (claimed)
            continue;
        snprintf(to, sizeof to, "%s/.claimed-%d", dir, (int)getpid());
        if (rename(from, to) == 0) {
            int stale;
            envp = read_env_file(to, &stale);
            unlink(to);
            claimed = !stale;
        }
    }
    closedir(d);
    return envp;
}

int main(void) {
    const char *home = getenv("HOME");
    if (home == NULL) {
        struct passwd *pw = getpwuid(getuid());
        if (pw == NULL)
            return 1;
        home = pw->pw_dir;
    }
    char **envp = claim_request(home);

    char log_path[1024];
    snprintf(log_path, sizeof log_path, "%s/Library/Logs/herdr-server.log", home);
    /* Nothing rotates this file, so start it over once it passes 1 MB. */
    int log_flags = O_WRONLY | O_CREAT | O_APPEND;
    struct stat log_st;
    if (stat(log_path, &log_st) == 0 && log_st.st_size > 1024 * 1024)
        log_flags |= O_TRUNC;
    int log = open(log_path, log_flags, 0644);
    if (log >= 0) {
        dup2(log, STDOUT_FILENO);
        dup2(log, STDERR_FILENO);
        close(log);
    }

    /* The profile link follows herdr upgrades without changing this bundle. */
    char herdr[1024];
    snprintf(herdr, sizeof herdr, "%s/.nix-profile/bin/herdr", home);

    /* `open` delivers no arguments, so anything passed here is not ours. */
    char *args[] = {"herdr", "server", NULL};

    execve(herdr, args, envp != NULL ? envp : environ);
    perror("Herdr.app: exec herdr");
    return 1;
}
