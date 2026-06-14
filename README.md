# Embershard

A cognitive inference engine for macOS/Metal. Not a wrapper — a control plane that orchestrates a local LLM as a stateless executor.

## Phase 1: Minimum Viable Inference Engine

Controlled inference loop with integrated benchmarking on Metal.

### Build

```bash
# Clone with llama.cpp backend
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git vendor/llama.cpp

# Build (Metal enabled by default on macOS)
cmake -B build -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --target embershard -j$(sysctl -n hw.ncpu)
```

### Model Setup

Convert Qwen2.5-14B-Instruct from HuggingFace to GGUF:

```bash
# Default: Q4_K_M quantization (fits 16GB RAM)
./scripts/convert_model.sh Qwen/Qwen2.5-14B-Instruct Q4_K_M

# Higher quality option
./scripts/convert_model.sh Qwen/Qwen2.5-14B-Instruct Q5_K_M
```

### Run

```bash
./build/embershard -m models/Qwen-Qwen2.5-14B-Instruct-Q4_K_M.gguf -p "Explain what an LLM is."

# Options:
#   -m <path>    model file (GGUF)
#   -p <text>    prompt
#   -c <int>     context size (default: 4096)
#   -t <int>     CPU threads (default: 4)
#   -n <int>     max tokens to generate (default: 256)
```

### Architecture

```
┌─────────────────────────────────────────┐
│         Embershard Control Plane        │
│                                         │
│  ┌───────────┐  ┌──────────┐  ┌─────┐  │
│  │  Context  │  │  Engine   │  │Bench│  │
│  │  Manager  │  │ (control) │  │     │  │
│  └─────┬─────┘  └─────┬─────┘  └──┬──┘  │
│        │              │            │     │
├────────┼──────────────┼────────────┼─────┤
│        └──────────────┼────────────┘     │
│                       ▼                  │
│          ┌────────────────────┐          │
│          │  llama.cpp backend │          │
│          │  (Metal / CPU)     │          │
│          └────────────────────┘          │
└─────────────────────────────────────────┘
```

The engine treats llama.cpp as a **stateless executor**. It controls:
- Ingestion (tokenization + batched decode)
- Step-by-step token generation
- KV cache manipulation (reset, truncate, fork)
- Context state (explicit, serializable)

This is the foundation for Phase 2+ (sub-agents, routing, memory compression).
