#ifndef IMGO_MINIFIER_H
#define IMGO_MINIFIER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Result of a successful imgo_optimize call. Ownership of `data` and
 * `meta_json` transfers to the caller; release both with imgo_result_free.
 *
 * `meta_json` layout (camelCase, matching the app-side Codable models):
 *   {"format":"WEBP","width":1280,"height":720,
 *    "inputWidth":4000,"inputHeight":3000}
 */
typedef struct {
  uint8_t *data;
  size_t len;
  char *meta_json;
} imgo_result;

/*
 * Optimize (and optionally convert) an image held in memory.
 *
 * request_json (UTF-8, may be NULL for defaults). Field names mirror the
 * serde contracts of imgo_shared::types verbatim (snake_case struct fields,
 * UPPERCASE enum values):
 *   {"output_format":"WEBP","options":{"quality":75,"lossless":false,
 *    "preserve_metadata":true,"resize":{"width":1920,"height":1080,
 *    "type":"DOWNSIZE_CONTAIN"},"indexed":false,"fastest":false}}
 * `output_format` null/omitted keeps the input format.
 *
 * Returns 0 on success and fills *out. On failure returns a nonzero code
 * (1 invalid arguments, 3 optimize failure) and the message is available via
 * imgo_last_error() on the calling thread.
 *
 * Thread-safe: may be called concurrently from any thread.
 */
int imgo_optimize(const uint8_t *input,
                  size_t input_len,
                  const char *request_json,
                  imgo_result *out);

/* Frees a result previously filled by imgo_optimize. NULL is a no-op. */
void imgo_result_free(imgo_result *result);

/* Last error message for the calling thread, or NULL. Valid until the next
 * failing imgo_* call on the same thread. */
const char *imgo_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* IMGO_MINIFIER_H */
