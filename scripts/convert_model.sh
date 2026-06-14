#!/usr/bin/env bash
set -euo pipefail

# Embershard model conversion: HuggingFace → GGUF
# Default: Qwen/Qwen2.5-14B-Instruct with Q4_K_M quantization

MODEL_ID="${1:-Qwen/Qwen2.5-14B-Instruct}"
QUANT="${2:-Q4_K_M}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LLAMA_DIR="$PROJECT_DIR/vendor/llama.cpp"
MODELS_DIR="$PROJECT_DIR/models"
VENV_DIR="$PROJECT_DIR/.venv"

MODEL_NAME=$(echo "$MODEL_ID" | tr '/' '-')
HF_DIR="$MODELS_DIR/hf/$MODEL_NAME"
GGUF_F16="$MODELS_DIR/$MODEL_NAME-f16.gguf"
GGUF_OUT="$MODELS_DIR/$MODEL_NAME-$QUANT.gguf"

echo "=== embershard model conversion ==="
echo "model:  $MODEL_ID"
echo "quant:  $QUANT"
echo "output: $GGUF_OUT"
echo ""

# Check if final output already exists
if [ -f "$GGUF_OUT" ]; then
    echo "[skip] $GGUF_OUT already exists"
    exit 0
fi

# Setup python venv
if [ ! -d "$VENV_DIR" ]; then
    echo "[setup] creating python venv..."
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install -q huggingface_hub transformers torch sentencepiece protobuf

# Download model from HF
if [ ! -d "$HF_DIR" ]; then
    echo "[download] fetching $MODEL_ID from HuggingFace..."
    huggingface-cli download "$MODEL_ID" --local-dir "$HF_DIR"
else
    echo "[skip] $HF_DIR already exists"
fi

# Convert to GGUF F16
if [ ! -f "$GGUF_F16" ]; then
    echo "[convert] HF → GGUF F16..."
    python3 "$LLAMA_DIR/convert_hf_to_gguf.py" "$HF_DIR" \
        --outfile "$GGUF_F16" \
        --outtype f16
else
    echo "[skip] F16 GGUF already exists"
fi

# Build llama-quantize if needed
QUANTIZE_BIN="$LLAMA_DIR/build/bin/llama-quantize"
if [ ! -f "$QUANTIZE_BIN" ]; then
    echo "[build] compiling llama-quantize..."
    cmake -B "$LLAMA_DIR/build" -S "$LLAMA_DIR" \
        -DGGML_METAL=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "$LLAMA_DIR/build" --target llama-quantize -j$(sysctl -n hw.ncpu)
fi

# Quantize
echo "[quantize] F16 → $QUANT..."
"$QUANTIZE_BIN" "$GGUF_F16" "$GGUF_OUT" "$QUANT"

echo ""
echo "[done] model ready: $GGUF_OUT"
echo ""
echo "run with:"
echo "  ./build/embershard -m $GGUF_OUT"

# Cleanup F16 (large, no longer needed)
read -p "remove F16 intermediate ($GGUF_F16)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$GGUF_F16"
    echo "[cleanup] removed F16"
fi
