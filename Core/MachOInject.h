#ifndef PP_MACHO_INJECT_H
#define PP_MACHO_INJECT_H
#include <stddef.h>
/* Returns 0 on success. Error buffer contains a human-readable reason otherwise. */
int PPInjectDylib(const char *binary, const char *loadPath, char *error, size_t errorSize);
#endif
