<div align="center">

<img src="docs/icon.png" alt="Embershard" width="160" height="160" />

# Embershard

**A cognitive inference engine for macOS — not a wrapper, a control plane.**

Embershard owns the full inference lifecycle and drives a local LLM as a stateless executor:
explicit KV-cache control, multi-sequence agents, and a planner → executor → critic pipeline,
all running on Apple Silicon via Metal.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![backend](https://img.shields.io/badge/backend-llama.cpp%20%2F%20Metal-orange)
![language](https://img.shields.io/badge/core-C11-blue)
![ui](https://img.shields.io/badge/app-SwiftUI-green)

</div>

---

## What it is

Most local-LLM tools wrap `llama.cpp` and let it manage state. Embershard inverts that: it treats
the backend as a **stateless token executor** and keeps ownership of everything that matters for
cognition like tokenization, batched ingestion, step-by-step decoding, KV-cache manipulation, and
multi-sequence isolation.

The development of this product has been orchestrated by me and coded by ClaudeCode.

That control plane is what makes the **agentic pipeline** possible: several specialised agents
(planner, executor, critic) share one physical model but live in **isolated KV sequences** inside a
single unified cache. No reloads, no separate processes — one model, many minds.

Embershard ships in two forms:

- **`embershard`** — a C CLI (single-shot + interactive REPL) with built-in benchmarking.
- **Embershard.app** — a native SwiftUI macOS app with chat, projects, skills, a HuggingFace model
  browser, and live hardware introspection (icon by DinosoftLabs)

---

## Features

| | |
|---|---|
| 🧠 **Stateless-executor architecture** | The engine owns ingestion, generation, and KV state. `llama.cpp` only decodes. |
| 🪢 **Multi-sequence agents** | Each agent runs in its own `llama_seq_id` within a **unified KV cache** — no context partitioning, no truncation. |
| 🔁 **Planner → Executor → Critic** | A built-in orchestrator decomposes a query, drafts an answer, then reviews and synthesises the final response. Stage transitions stream to the UI. |
| 💬 **Streaming generation** | Token-by-token callbacks, multi-turn conversations with incremental prompt ingestion. |
| 🧮 **KV-cache control** | Reset, truncate, fork, and shift sequences; automatic context-overflow handling. |
| 📉 **KV quantization** | F16 / Q8_0 / Q4_0 cache types for large-context memory savings. |
| ⚡ **Metal acceleration** | Full GPU offload on Apple Silicon, with Flash Attention. |
| 🖥️ **Native macOS app** | Tabbed chats, projects, customisable skills, model downloads, and a hardware scanner. |
| 📊 **Built-in benchmarking** | Tokens/sec and memory-pressure reporting per turn. |

---

## Build

### Prerequisites

- macOS 14+ on Apple Silicon
- CMake 3.20+, a C11 compiler (Xcode command-line tools)
- `llama.cpp` checked out under `vendor/`

```bash
# Backend (pinned under vendor/)
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git vendor/llama.cpp
```

### Engine + CLI

```bash
cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --target embershard -j$(sysctl -n hw.ncpu)
```

### Tests

```bash
cmake --build build --target test_engine -j$(sysctl -n hw.ncpu)
./build/test_engine /path/to/model.gguf
# Exercises es_generate, es_continue (multi-turn), long-output, and the agentic pipeline.
```

---

## Model setup

Download a GGUF directly (the macOS app has a built-in HuggingFace browser), or convert one:

```bash
# Default: Q4_K_M quantization (fits 16 GB RAM)
./scripts/convert_model.sh Qwen/Qwen2.5-14B-Instruct Q4_K_M
```

Embershard works with any instruct-tuned GGUF that carries a chat template. The agentic pipeline is
tuned to run well even on small models (tested down to **3B**, e.g. `Llama-3.2-3B-Instruct-Q4_K_M`).

---

## CLI usage

```bash
# Single-shot
./build/embershard -m model.gguf -p "Explain what an LLM is."

# Interactive REPL
./build/embershard -m model.gguf

# Agentic mode (planner → executor → critic)
./build/embershard -m model.gguf --agent --verbose
```

```
Options:
  -m <path>      Model file (required)
  -p <prompt>    Single-shot prompt (disables interactive REPL)
  -c <n>         Context size
  -t <n>         CPU threads
  -n <n>         Max tokens per turn
  --temp <f>     Sampling temperature (0 = greedy)
  --top-p <f>    Top-P sampling
  --agent        Enable multi-agent mode
  --verbose      Verbose agent pipeline output

Interactive commands:
  /reset    Clear conversation and KV cache
  /status   KV cache usage and memory stats
  /bench    Show last benchmark results
  /agent    Toggle agent mode on/off
  /help     Show help
  /quit     Exit
```

---

## C API

```c
#include "es_api.h"

ESConfig cfg = {
    .model_path  = "model.gguf",
    .n_gpu_layers = -1,        // all layers on GPU
    .n_ctx        = 8192,
    .temperature  = 0.7f,
    .top_p        = 0.95f,
    .kv_quant     = ES_KV_QUANT_F16,
};

ESEngineRef eng;
es_create(&cfg, &eng);

// Streaming generation
es_generate(eng, "You are a helpful assistant.", "Hello!", 512,
            on_token, on_done, user_data);

// Multi-turn continuation (reuses the KV cache)
es_continue(eng, "And what did I just say?", 512, on_token, on_done, user_data);

// Agentic pipeline — streams the critic's final answer, reports each stage
es_orchestrate(eng, "Compare REST and GraphQL.", 1024,
               on_stage, on_token, on_done, user_data);

es_destroy(eng);
```

---

## macOS app

A native SwiftUI front-end that links the engine as a static library and bundles the `llama.cpp`
dylibs.

```bash
cd app
swift build -c release            # development build
./make_dmg.sh                     # signed .app + drag-to-Applications .dmg
```

The app includes:

- **Chat** with Chrome-style tabs, projects, and per-chat skills
- **Agent mode** toggle (planner → executor → critic) with live stage indicators
- **Model browser** — search and download GGUF models from HuggingFace
- **Inference settings** — context size, max tokens, sampling, KV quantization, GPU layers
- **Hardware scan** — chip, cores, total/available RAM

> First launch on another Mac (ad-hoc signed): right-click → **Open** → **Open**, or
> `xattr -dr com.apple.quarantine /path/to/Embershard.app`.

---

## Project layout

```
embershard/
├── include/            # Public + internal C headers (es_api.h is the stable API)
├── src/                # Engine, orchestrator, agents, CLI, tests
│   ├── es_engine.c     # llama.cpp control layer
│   ├── es_api.c        # Public API + conversation state
│   ├── es_orchestrator.c   # Planner → Executor → Critic
│   ├── es_agent.c      # Single agent (role + KV sequence)
│   ├── main.c          # CLI (single-shot + REPL)
│   └── test_engine.c   # Integration tests
├── app/                # SwiftUI macOS application
├── scripts/            # Model conversion helpers
└── vendor/llama.cpp/   # Backend (not vendored in-repo)
```

---

## Roadmap

- [x] Controlled inference loop with Metal + benchmarking
- [x] Multi-sequence agents in a unified KV cache
- [x] Planner → Executor → Critic orchestration
- [x] Native macOS app with model management
- [ ] Persistent, compressible long-term memory
- [ ] Dynamic agent routing and tool use
- [ ] Speculative decoding

---

<div align="center">
<sub>Built on <a href="https://github.com/ggerganov/llama.cpp">llama.cpp</a> · Apple Silicon · Metal</sub>
</div>
