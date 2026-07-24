#ifndef ANDROID_TERMINAL_SESSION_ENVIRONMENT_H
#define ANDROID_TERMINAL_SESSION_ENVIRONMENT_H

char **session_environment_merge(
        char *const inherited_environment[],
        const char *home,
        const char *temporary_directory,
        const char *terminal_type);

void session_environment_destroy(char **environment);

#endif
