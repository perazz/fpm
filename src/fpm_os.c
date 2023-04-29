#include <stdlib.h>

/// @brief Determine the absolute, canonicalized path for a given path.
/// @param path
/// @param resolved_path
/// @param maxLength
/// @return
char* c_realpath(char* path, char* resolved_path, int maxLength) {
// Checking macro in C because it doesn't work with gfortran on Windows, even
// when exported manually.
#if defined(_WIN32) || defined(_WIN64) || defined(__MSYS__) || defined(__MINGW64__) || defined(__MINGW32__)
  return _fullpath(resolved_path, path, maxLength);
#else
  return realpath(path, resolved_path);
#endif
}
