#define _POSIX_C_SOURCE 200809L

#include "session_environment.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int is_override(const char *entry) {
    static const char *const names[] = {"HOME", "TMPDIR", "TERM"};
    for (size_t index = 0U; index < sizeof(names) / sizeof(names[0]); ++index) {
        const size_t length = strlen(names[index]);
        if (strncmp(entry, names[index], length) == 0 && entry[length] == '=') {
            return 1;
        }
    }
    return 0;
}

static char *make_entry(const char *name, const char *value) {
    const size_t name_length = strlen(name);
    const size_t value_length = strlen(value);
    if (name_length > SIZE_MAX - value_length - 2U) {
        errno = EOVERFLOW;
        return NULL;
    }
    const size_t length = name_length + value_length + 2U;
    char *entry = malloc(length);
    if (entry == NULL) {
        return NULL;
    }
    memcpy(entry, name, name_length);
    entry[name_length] = '=';
    memcpy(entry + name_length + 1U, value, value_length + 1U);
    return entry;
}

void session_environment_destroy(char **environment) {
    if (environment == NULL) {
        return;
    }
    for (size_t index = 0U; environment[index] != NULL; ++index) {
        free(environment[index]);
    }
    free(environment);
}

char **session_environment_merge(
        char *const inherited_environment[],
        const char *home,
        const char *temporary_directory,
        const char *terminal_type) {
    if (inherited_environment == NULL || home == NULL || temporary_directory == NULL ||
            terminal_type == NULL) {
        errno = EINVAL;
        return NULL;
    }

    size_t inherited_count = 0U;
    size_t retained_count = 0U;
    while (inherited_environment[inherited_count] != NULL) {
        if (!is_override(inherited_environment[inherited_count])) {
            ++retained_count;
        }
        ++inherited_count;
    }

    if (retained_count > SIZE_MAX / sizeof(char *) - 4U) {
        errno = EOVERFLOW;
        return NULL;
    }
    char **merged = calloc(retained_count + 4U, sizeof(char *));
    if (merged == NULL) {
        return NULL;
    }

    size_t output = 0U;
    for (size_t index = 0U; index < inherited_count; ++index) {
        if (is_override(inherited_environment[index])) {
            continue;
        }
        merged[output] = strdup(inherited_environment[index]);
        if (merged[output] == NULL) {
            session_environment_destroy(merged);
            return NULL;
        }
        ++output;
    }

    merged[output] = make_entry("HOME", home);
    if (merged[output] == NULL) {
        session_environment_destroy(merged);
        return NULL;
    }
    ++output;
    merged[output] = make_entry("TMPDIR", temporary_directory);
    if (merged[output] == NULL) {
        session_environment_destroy(merged);
        return NULL;
    }
    ++output;
    merged[output] = make_entry("TERM", terminal_type);
    if (merged[output] == NULL) {
        session_environment_destroy(merged);
        return NULL;
    }
    ++output;
    merged[output] = NULL;
    return merged;
}
