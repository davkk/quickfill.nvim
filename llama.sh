#!/usr/bin/env bash

host=${1:-localhost}
port=${2:-8012}

llama-server \
    -hf Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF:Q8_0 \
    --n-gpu-layers 99 \
    --threads 8 \
    --ctx-size 0 \
    --batch-size 2048 \
    --ubatch-size 1024 \
    --flash-attn on \
    --mlock \
    --cache-reuse 32 \
    --verbose \
    --host $host \
    --port $port
