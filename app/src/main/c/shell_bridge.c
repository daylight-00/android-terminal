#define _POSIX_C_SOURCE 200809L

#include <jni.h>

#include <errno.h>
#include <fcntl.h>
#include <pty.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct shell_session {
    pid_t child_pid;
    int master_fd;
} shell_session;

static void throw_io_exception(JNIEnv *env, const char *operation, int error_number) {
    char message[256];
    const char *detail = strerror(error_number);
    (void)snprintf(message, sizeof(message), "%s failed: %s (%d)", operation, detail, error_number);
    jclass exception_class = (*env)->FindClass(env, "java/io/IOException");
    if (exception_class != NULL) {
        (*env)->ThrowNew(env, exception_class, message);
    }
}

static char *copy_utf8(JNIEnv *env, jstring value) {
    if (value == NULL) {
        return NULL;
    }
    const char *temporary = (*env)->GetStringUTFChars(env, value, NULL);
    if (temporary == NULL) {
        return NULL;
    }
    char *copy = strdup(temporary);
    (*env)->ReleaseStringUTFChars(env, value, temporary);
    return copy;
}

static shell_session *from_handle(jlong handle) {
    return (shell_session *)(uintptr_t)handle;
}

static void close_child_fds(rlim_t maximum_fd) {
    rlim_t limit = maximum_fd;
    if (limit == RLIM_INFINITY || limit > 65536U) {
        limit = 65536U;
    }
    for (rlim_t fd = 3U; fd < limit; ++fd) {
        (void)close((int)fd);
    }
}

JNIEXPORT jlong JNICALL
Java_io_github_daylight00_nativeshell_NativePty_spawn(
        JNIEnv *env,
        jclass clazz,
        jstring shell_path_value,
        jstring cwd_value,
        jstring home_value,
        jstring temporary_directory_value,
        jint rows,
        jint columns) {
    char *shell_path = copy_utf8(env, shell_path_value);
    char *cwd = copy_utf8(env, cwd_value);
    char *home = copy_utf8(env, home_value);
    char *temporary_directory = copy_utf8(env, temporary_directory_value);

    if ((*env)->ExceptionCheck(env)) {
        free(shell_path);
        free(cwd);
        free(home);
        free(temporary_directory);
        return 0;
    }
    if (shell_path == NULL || cwd == NULL || home == NULL || temporary_directory == NULL) {
        free(shell_path);
        free(cwd);
        free(home);
        free(temporary_directory);
        throw_io_exception(env, "copy arguments", ENOMEM);
        return 0;
    }

    char home_entry[1024];
    char temporary_entry[1024];
    if (snprintf(home_entry, sizeof(home_entry), "HOME=%s", home) >= (int)sizeof(home_entry) ||
            snprintf(temporary_entry, sizeof(temporary_entry), "TMPDIR=%s", temporary_directory) >=
                    (int)sizeof(temporary_entry)) {
        free(shell_path);
        free(cwd);
        free(home);
        free(temporary_directory);
        throw_io_exception(env, "construct environment", ENAMETOOLONG);
        return 0;
    }

    char *const environment[] = {
            home_entry,
            temporary_entry,
            "PATH=/system/bin",
            "SHELL=/system/bin/sh",
            "TERM=xterm-256color",
            "LANG=C.UTF-8",
            "ANDROID_ROOT=/system",
            "ANDROID_DATA=/data",
            NULL,
    };

    struct winsize window_size;
    memset(&window_size, 0, sizeof(window_size));
    window_size.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    window_size.ws_col = (unsigned short)(columns > 0 ? columns : 80);

    struct rlimit descriptor_limit;
    if (getrlimit(RLIMIT_NOFILE, &descriptor_limit) != 0) {
        descriptor_limit.rlim_cur = 1024U;
    }

    int master_fd = -1;
    pid_t child_pid = forkpty(&master_fd, NULL, NULL, &window_size);
    if (child_pid < 0) {
        int saved_errno = errno;
        free(shell_path);
        free(cwd);
        free(home);
        free(temporary_directory);
        throw_io_exception(env, "forkpty", saved_errno);
        return 0;
    }

    if (child_pid == 0) {
        char *const arguments[] = {shell_path, NULL};
        close_child_fds(descriptor_limit.rlim_cur);
        if (chdir(cwd) != 0) {
            _exit(126);
        }
        execve(shell_path, arguments, environment);
        _exit(errno == ENOENT ? 127 : 126);
    }

    free(shell_path);
    free(cwd);
    free(home);
    free(temporary_directory);

    int descriptor_flags = fcntl(master_fd, F_GETFD);
    if (descriptor_flags >= 0) {
        (void)fcntl(master_fd, F_SETFD, descriptor_flags | FD_CLOEXEC);
    }

    shell_session *session = calloc(1U, sizeof(*session));
    if (session == NULL) {
        int saved_errno = errno;
        (void)kill(-child_pid, SIGHUP);
        (void)kill(child_pid, SIGKILL);
        (void)close(master_fd);
        (void)waitpid(child_pid, NULL, 0);
        throw_io_exception(env, "allocate session", saved_errno == 0 ? ENOMEM : saved_errno);
        return 0;
    }

    session->child_pid = child_pid;
    session->master_fd = master_fd;
    return (jlong)(uintptr_t)session;
}

JNIEXPORT jint JNICALL
Java_io_github_daylight00_nativeshell_NativePty_read(
        JNIEnv *env,
        jclass clazz,
        jlong handle,
        jbyteArray destination,
        jint offset,
        jint length) {
    shell_session *session = from_handle(handle);
    if (session == NULL || destination == NULL || offset < 0 || length < 0) {
        throw_io_exception(env, "read arguments", EINVAL);
        return -1;
    }

    jsize array_length = (*env)->GetArrayLength(env, destination);
    if (offset > array_length || length > array_length - offset) {
        throw_io_exception(env, "read bounds", EINVAL);
        return -1;
    }

    jbyte *bytes = (*env)->GetByteArrayElements(env, destination, NULL);
    if (bytes == NULL) {
        return -1;
    }

    ssize_t result;
    do {
        result = read(session->master_fd, bytes + offset, (size_t)length);
    } while (result < 0 && errno == EINTR);

    int saved_errno = errno;
    (*env)->ReleaseByteArrayElements(env, destination, bytes, result > 0 ? 0 : JNI_ABORT);

    if (result < 0) {
        if (saved_errno == EIO) {
            return 0;
        }
        throw_io_exception(env, "read", saved_errno);
        return -1;
    }
    return (jint)result;
}

JNIEXPORT jint JNICALL
Java_io_github_daylight00_nativeshell_NativePty_write(
        JNIEnv *env,
        jclass clazz,
        jlong handle,
        jbyteArray source,
        jint offset,
        jint length) {
    shell_session *session = from_handle(handle);
    if (session == NULL || source == NULL || offset < 0 || length < 0) {
        throw_io_exception(env, "write arguments", EINVAL);
        return -1;
    }

    jsize array_length = (*env)->GetArrayLength(env, source);
    if (offset > array_length || length > array_length - offset) {
        throw_io_exception(env, "write bounds", EINVAL);
        return -1;
    }

    jbyte *bytes = (*env)->GetByteArrayElements(env, source, NULL);
    if (bytes == NULL) {
        return -1;
    }

    size_t total = 0U;
    while (total < (size_t)length) {
        ssize_t result = write(
                session->master_fd,
                bytes + offset + (jint)total,
                (size_t)length - total);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result < 0) {
            int saved_errno = errno;
            (*env)->ReleaseByteArrayElements(env, source, bytes, JNI_ABORT);
            throw_io_exception(env, "write", saved_errno);
            return -1;
        }
        total += (size_t)result;
    }

    (*env)->ReleaseByteArrayElements(env, source, bytes, JNI_ABORT);
    return (jint)total;
}

JNIEXPORT void JNICALL
Java_io_github_daylight00_nativeshell_NativePty_resize(
        JNIEnv *env,
        jclass clazz,
        jlong handle,
        jint rows,
        jint columns,
        jint pixel_width,
        jint pixel_height) {
    shell_session *session = from_handle(handle);
    if (session == NULL || rows <= 0 || columns <= 0) {
        throw_io_exception(env, "resize arguments", EINVAL);
        return;
    }

    struct winsize window_size;
    memset(&window_size, 0, sizeof(window_size));
    window_size.ws_row = (unsigned short)rows;
    window_size.ws_col = (unsigned short)columns;
    window_size.ws_xpixel = (unsigned short)(pixel_width > 0 ? pixel_width : 0);
    window_size.ws_ypixel = (unsigned short)(pixel_height > 0 ? pixel_height : 0);

    if (ioctl(session->master_fd, TIOCSWINSZ, &window_size) != 0) {
        throw_io_exception(env, "ioctl(TIOCSWINSZ)", errno);
    }
}

JNIEXPORT void JNICALL
Java_io_github_daylight00_nativeshell_NativePty_signalProcessGroup(
        JNIEnv *env,
        jclass clazz,
        jlong handle,
        jint signal_number) {
    shell_session *session = from_handle(handle);
    if (session == NULL || signal_number <= 0) {
        throw_io_exception(env, "signal arguments", EINVAL);
        return;
    }
    if (kill(-session->child_pid, signal_number) != 0 && errno != ESRCH) {
        throw_io_exception(env, "kill process group", errno);
    }
}

JNIEXPORT jint JNICALL
Java_io_github_daylight00_nativeshell_NativePty_waitFor(
        JNIEnv *env,
        jclass clazz,
        jlong handle) {
    shell_session *session = from_handle(handle);
    if (session == NULL) {
        throw_io_exception(env, "wait arguments", EINVAL);
        return -1;
    }

    int status = 0;
    pid_t result;
    do {
        result = waitpid(session->child_pid, &status, 0);
    } while (result < 0 && errno == EINTR);

    if (result < 0) {
        if (errno == ECHILD) {
            return 0;
        }
        throw_io_exception(env, "waitpid", errno);
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return status;
}

JNIEXPORT void JNICALL
Java_io_github_daylight00_nativeshell_NativePty_destroy(
        JNIEnv *env,
        jclass clazz,
        jlong handle) {
    shell_session *session = from_handle(handle);
    if (session == NULL) {
        return;
    }
    if (session->master_fd >= 0) {
        (void)close(session->master_fd);
        session->master_fd = -1;
    }
    int status = 0;
    (void)waitpid(session->child_pid, &status, WNOHANG);
    free(session);
}
