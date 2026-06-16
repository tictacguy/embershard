<img src="docs/icon.png" alt="Embershard" width="160" height="160" />

# Embershard

### [⬇️ Download the latest .dmg](https://github.com/tictacguy/embershard/releases/latest)

No need to clone or build — grab the signed `.dmg` from the latest release, drag
Embershard to Applications, then right-click → Open on first launch (ad-hoc
signed). Apple Silicon, macOS 14+.

Embershard is a native LLM inference engine and chat app for macOS / Apple
Silicon. Its chat path does **not** use llama.cpp at inference time: it reads the
GGUF itself, uploads the weights to Metal, builds its own transformer compute
graph on `ggml`, owns a resident KV cache, and tokenizes with its own byte-level
BPE / SentencePiece. `ggml` provides only the tensor kernels.

The project is intentionally narrow: it targets the `llama` and `qwen2`
architectures (Llama 3.x, Mistral, Qwen 2.5, and other models that report those
architectures in their GGUF), validated for numerical parity against llama.cpp.
It is not a general GGUF runner.

The development of this product has been orchestrated by me and coded by
ClaudeCode. The app icon is by DinosoftLabs.

## Acknowledgements to llama.cpp and GGML

The native engine (`es_gx`) does not call libllama, but it exists thanks to the
path opened by `llama.cpp` and `ggml`: their kernels, the GGUF format and tooling,
the quantization formats, and a large amount of hard-won engineering knowledge
were the reference while building the forward pass, the KV-cache layout, the
sampler, and the tokenizer. We link `ggml` for the tensor ops and the Metal
backend, and we keep llama.cpp available for the experimental multi-agent
orchestrator. Thanks to Georgi Gerganov and the contributors.

## Status

Beta. What works and is validated:

- Forward pass for `llama` and `qwen2` matches llama.cpp logits (cosine 0.999999,
  greedy continuations are token-identical).
- Resident KV cache (F16 / Q8_0 / Q4_0) with incremental O(n) decode and
  multi-turn reuse. A sliding window drops the oldest tokens when the context
  fills, preserving absolute RoPE positions (no re-rope), so long chats continue.
- Decode throughput is at parity with llama.cpp on the same model (both are
  memory-bandwidth bound and use the same ggml kernels).
- The whole app runs on the native engine: direct chat and the multi-agent
  pipeline (planner → executor) both run on `es_gx`, not llama.cpp.
- Native tokenizer with two backends, token-IDs identical to llama.cpp on the
  test corpus: byte-level BPE (`gpt2`: `llama-bpe`, `qwen2`) and SentencePiece
  (`llama`/SPM: Llama 2, Mistral v0.1/v0.2, TinyLlama).
- Sharded GGUFs (`-00001-of-N`) load by following the split metadata.

Not done / known limitations:

- Only `llama` / `qwen2` architectures. Gemma, Phi, MoE (gpt-oss, Mixtral), etc.
  are not supported and are filtered out of the model browser.
- Models larger than the GPU working set are not streamed from SSD; loading one
  fails cleanly (the app filters models by RAM). True SSD streaming is future work.
- Custom Metal kernels are not written yet: attention uses `ggml_flash_attn_ext`
  for prefill and a manual `ggml` path for decode.
- Tokenizers beyond BPE/SPM (tiktoken-style for gpt-oss, etc.) are not added,
  and would only matter once their architectures are supported.

## Architecture

```
es_gx.c    GGUF load (single or sharded) -> Metal weights, forward graph,
           resident KV cache (F16/Q8_0/Q4_0) + sliding window, sampling
es_tok.c   native tokenizer: byte-level BPE (gpt2) and SentencePiece (llama)
NativeEngine.swift  multi-turn chat + planner→executor pipeline on es_gx

(llama.cpp / es_engine.c / es_orchestrator.c remain for the CLI and tests.)
```

The native forward pass per layer: RMSNorm, Q/K/V projection (+ bias for qwen2),
RoPE (NORMAL for llama, NEOX for qwen2), attention (flash for prefill, manual
mul_mat/softmax for decode) over the resident K/V cache, output projection,
residual, gated FFN (SwiGLU), residual; final norm and output projection produce
the logits for the last position. Sampling (temperature, top-k, top-p, min-p,
repeat penalty, seed) runs on the host.

## Build

Prerequisites: macOS 14+ on Apple Silicon, CMake 3.20+, Xcode command-line
tools, and `llama.cpp` checked out under `vendor/` (for `ggml` and the Metal
backend).

```sh
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git vendor/llama.cpp

cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.ncpu)
```

Targets:

```
embershard        llama.cpp CLI (single-shot + REPL, agent mode)
test_gx           native-engine correctness gate vs llama.cpp (logits + greedy)
tok_test          tokenizer parity gate vs llama.cpp
gen_gx            standalone multi-turn generation, links ggml only (no libllama)
test_engine       agent/orchestrator integration test
```

## Validation

The native engine is gated against llama.cpp on the same GGUF:

```sh
# Loads the model once with llama.cpp (reference) and once with es_gx, feeds
# identical token IDs, compares last-token logits, then greedy-generates with
# both and checks the token sequences match.
./build/test_gx /path/to/model.gguf "The capital of France is" 32

# Tokenizer: compares es_tok vs llama_tokenize on a corpus.
./build/tok_test /path/to/model.gguf
```

Expected: argmax matches, cosine > 0.999, greedy token sequences identical,
tokenizer 12/12 cases identical.

Standalone generation without libllama:

```sh
./build/gen_gx /path/to/model.gguf "My name is Alice." "What is my name?"
```

## macOS app

A SwiftUI app that links the engine as a static library and bundles the `ggml`
dylibs. Chat runs entirely on `es_gx`.

```sh
cd app
swift build -c release      # development build
./make_dmg.sh               # signed .app + drag-to-Applications .dmg
```

Features: tabbed chats and projects, per-chat skills, an experimental multi-agent
mode, a HuggingFace model browser limited to engine-compatible official GGUFs
(with publisher shown), and an Inference panel exposing context size, max tokens,
and the full sampler (temperature, top-k, top-p, min-p, repeat penalty, seed).

First launch on another Mac (ad-hoc signed): right-click → Open → Open, or
`xattr -dr com.apple.quarantine /path/to/Embershard.app`.

## Models

The app browser lists official, engine-compatible GGUFs filtered by the
machine's RAM (Qwen 2.5 family; SmolLM2 from HuggingFaceTB). Search shows
community repacks too, marked as such. You can also import a local `.gguf`; if it
is not a `llama`/`qwen2` model it is marked unsupported and hidden from the chat
model picker.
