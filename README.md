<img src="docs/icon.png" alt="Embershard" width="160" height="160" />

# Embershard

### [⬇️ Download the latest .dmg](https://github.com/tictacguy/embershard/releases/latest)

**Latest release:** v0.1.3

Grab the signed `.dmg` from the latest release, drag Embershard into
Applications, and right-click → Open the first time (you'll need to approve it's opening by going to System Settings->Privacy and Security->Scroll down until "Security" section and click "Open Anyway"). No clone, no toolchain. Apple Silicon, macOS 14 or newer.

Embershard is a macOS chat app with its own LLM inference engine underneath. The
interesting part is what *isn't* there: at inference time the chat path never
calls into llama.cpp. Embershard opens the GGUF on its own, pushes the weights to
Metal, assembles its transformer compute graph directly on `ggml`, keeps the KV
cache resident across turns, and runs its own byte-level BPE / SentencePiece
tokenizer. `ggml` is used purely as a bag of tensor kernels.

That independence is deliberate, and so is the narrow scope: Embershard runs the
`llama` and `qwen2` families (Llama 3.x, Mistral, Qwen 2.5, and anything that
reports those architectures in its GGUF) and nothing else. It is a focused engine
checked for numerical parity against the reference — not a drop-in GGUF runner.

> Embershard grew out of [ds4](https://github.com/antirez/ds4), which set the
> template for a small, honest, self-contained native project. ds4 was the
> inspiration; the engine, app, and writing here are their own thing.

Orchestrated by me, written with ClaudeCode. App icon by DinosoftLabs.

## Why bother re-implementing the forward pass

Wrapping libllama is the easy path, and it is the one most apps take. Embershard
takes the harder one so the whole hot loop — graph construction, the KV-cache
layout, the sampler, tokenization — lives in code we own and can reason about.
`llama.cpp` and `ggml` still made it possible: their kernels, the GGUF format and
its tooling, the quant formats, and a great deal of hard-won engineering were the
map we followed while building everything above the tensor ops. We link `ggml`
for those ops and the Metal backend, and keep llama.cpp around only for the
experimental multi-agent orchestrator. Thanks to Georgi Gerganov and the
contributors.

## What's proven

Beta, but the core is measured rather than asserted:

- **Logit parity.** The `llama` and `qwen2` forward pass matches llama.cpp to a
  cosine of 0.999999; greedy continuations come out token-for-token identical.
- **Resident KV cache** in F16 / Q8_0 / Q4_0, incremental O(n) decode, reused
  across turns. When the context fills, a sliding window evicts the oldest tokens
  while keeping absolute RoPE positions intact (no re-roping), so long
  conversations keep going.
- **Throughput at parity** with llama.cpp on the same model — both are
  memory-bandwidth bound on identical ggml kernels, so there is nothing to win or
  lose here.
- **One engine for everything.** Plain chat and the planner → executor agent
  pipeline both run on `es_gx`; llama.cpp is not in the inference path.
- **Tokenizer parity.** Token IDs match llama.cpp across the test corpus, with
  two backends: byte-level BPE (`gpt2`: `llama-bpe`, `qwen2`) and SentencePiece
  (`llama`/SPM: Llama 2, Mistral v0.1/v0.2, TinyLlama).
- **Sharded GGUFs** (`-00001-of-N`) load by following the split metadata.

## Limits

- Architectures stop at `llama` / `qwen2`. Gemma, Phi, and MoE models (gpt-oss,
  Mixtral, …) are unsupported and filtered out of the browser.
- A model that exceeds the GPU working set is not streamed from SSD — loading it
  fails cleanly, and the browser filters by available RAM up front. SSD streaming
  is future work.
- No bespoke Metal kernels yet: prefill uses `ggml_flash_attn_ext`, decode a
  manual `ggml` path.
- Tokenizers past BPE/SPM (tiktoken-style for gpt-oss, etc.) aren't written, and
  won't matter until the matching architectures land.

## How it works

```
es_gx.c             GGUF load (single or sharded) -> Metal weights, forward
                    graph, resident KV cache (F16/Q8_0/Q4_0) + sliding window,
                    host-side sampling
es_tok.c            tokenizer: byte-level BPE (gpt2) and SentencePiece (llama)
NativeEngine.swift  multi-turn chat + planner→executor pipeline on es_gx

(llama.cpp / es_engine.c / es_orchestrator.c stay for the CLI and tests.)
```

Per layer the forward pass is the familiar stack: RMSNorm, Q/K/V projection (with
bias on qwen2), RoPE (NORMAL for llama, NEOX for qwen2), attention over the
resident K/V cache (flash for prefill, manual mul_mat/softmax for decode), output
projection and residual, a SwiGLU-gated FFN and residual. A final norm and output
projection give the logits for the last position; temperature, top-k, top-p,
min-p, repeat penalty and seed are applied on the host.

## Building from source

You need macOS 14+ on Apple Silicon, CMake 3.20+, the Xcode command-line tools,
and a `llama.cpp` checkout under `vendor/` (for `ggml` and the Metal backend).

```sh
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git vendor/llama.cpp

cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.ncpu)
```

Targets:

```
embershard   llama.cpp CLI (single-shot + REPL, agent mode)
test_gx      native-engine parity gate vs llama.cpp (logits + greedy)
tok_test     tokenizer parity gate vs llama.cpp
gen_gx       standalone multi-turn generation, links ggml only (no libllama)
test_engine  agent/orchestrator integration test
```

## Checking parity

The engine is gated against llama.cpp on the same GGUF — this is how the numbers
above are produced, not a claim taken on faith:

```sh
# Load once with llama.cpp (reference) and once with es_gx, feed identical token
# IDs, compare last-token logits, then greedy-generate with both and diff the
# token sequences.
./build/test_gx /path/to/model.gguf "The capital of France is" 32

# Tokenizer: es_tok vs llama_tokenize over a corpus.
./build/tok_test /path/to/model.gguf
```

Pass criteria: argmax agrees, cosine > 0.999, greedy sequences identical,
tokenizer 12/12 cases byte-for-byte.

Generation with no libllama in the link at all:

```sh
./build/gen_gx /path/to/model.gguf "My name is Alice." "What is my name?"
```

## The app

A SwiftUI front end that links the engine as a static library and bundles the
`ggml` dylibs; every token is produced by `es_gx`.

```sh
cd app
swift build -c release      # development build
./make_dmg.sh               # signed .app + drag-to-Applications .dmg
```

Inside: tabbed chats, projects (each with its own icon and system prompt) you can
organize chats into, per-chat skills, multi-select delete, and three chat modes
when you start a new one:

- **Standard** — one model, one conversation. Flip the **Agent** toggle for a
  planner → executor pass on multi-step questions.
- **Pomme** *(Beta)* — a macOS helper that operates on your files. See below.
- **Arena** — ask up to four models the same thing and watch them answer side by
  side, concurrently (two at a time under 32 GB of unified memory, four with more).

Plus a HuggingFace browser restricted to engine-compatible official GGUFs with the
publisher shown, and an inference panel for context size, max tokens and the full
sampler.

First launch on another Mac (ad-hoc signed): right-click → Open → Open, or
`xattr -dr com.apple.quarantine /path/to/Embershard.app`.

## Pomme — the macOS helper

Because this is a Mac-only app, Pomme lets the local model actually *do* things on
your machine. You describe one task in plain language and the model's only job is
to pick the right tool; everything else — the filesystem work, the summaries — is
plain Swift, so it stays predictable and doesn't hallucinate results. Anything that
changes your files is shown as a **preview you accept, decline, or adjust** (à la
Claude Code) before it runs, and deletes only ever go to the **Trash**.

The tools: find files by name, biggest files (in a folder or across the whole Mac),
where your space is going, recently-changed files, a heuristic threat scan, the
heaviest running apps, tidy the Desktop or a folder by type, organize by date, find
duplicates, clean old Downloads, move/rename, create a folder, and quit an app. Read-
only tools run immediately; the rest ask first. It's deliberately one tool per turn —
ask again for the next step — which keeps it stable on small local models.

## Picking models

The browser lists official, engine-compatible GGUFs filtered by your machine's
RAM (the Qwen 2.5 family; SmolLM2 from HuggingFaceTB). Search also surfaces
community repacks, flagged as such. Import a local `.gguf` and, if it isn't a
`llama`/`qwen2` model, it's marked unsupported and kept out of the chat picker.
