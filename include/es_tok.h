#ifndef ES_TOK_H
#define ES_TOK_H

// --- Embershard native tokenizer ---
// Byte-level BPE (GPT-2 family) read directly from a GGUF's tokenizer metadata.
// Produces token IDs byte-identical to llama.cpp for the "llama-bpe" (Llama 3)
// and "qwen2" pre-tokenizers. No libllama dependency.

#include <stdint.h>
#include <stdbool.h>

struct gguf_context;

#ifdef __cplusplus
extern "C" {
#endif

typedef struct es_tok es_tok;

// Build from an already-parsed GGUF context (copies what it needs).
es_tok *es_tok_create(const struct gguf_context *gguf);
void    es_tok_free(es_tok *t);

int  es_tok_bos(const es_tok *t);
int  es_tok_eos(const es_tok *t);
bool es_tok_add_bos_default(const es_tok *t);
bool es_tok_is_eog(const es_tok *t, int32_t id);   // any end-of-generation token
bool es_tok_is_spm(const es_tok *t);               // SentencePiece (else byte-level BPE)

// Encode UTF-8 text into token IDs. Returns count written, or -1 if > max_out.
int es_tok_encode(es_tok *t, const char *text, int32_t *out, int max_out,
                  bool add_bos, bool parse_special);

// Append the bytes for one token ID to buf (NUL-terminated). Returns bytes added.
int es_tok_decode(es_tok *t, int32_t id, char *buf, int buf_size);

#ifdef __cplusplus
}
#endif

#endif // ES_TOK_H
