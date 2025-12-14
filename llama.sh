#!/usr/bin/env bash

host=${1:-localhost}
port=${2:-8012}

llama-server \
    -hf bartowski/Qwen2.5-Coder-0.5B-GGUF:Q4_0 \
    --n-gpu-layers 99 \
    --threads 8 \
    --ctx-size 0 \
    --flash-attn on \
    --mlock \
    --cache-reuse 256 \
    --verbose \
    --host $host \
    --port $port

# -hf ibm-granite/granite-4.0-350m-GGUF:Q8_0 \
# --batch-size 2048 \
# --ubatch-size 512 \
