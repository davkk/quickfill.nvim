#!/usr/bin/env bash

host=${1:-localhost}
port=${2:-8012}

llama-server \
    -m ~/llms/bartowski_qwen2.5-coder-0.5b-q4_0.gguf \
    --n-gpu-layers 12 \
    --threads 8 \
    --ctx-size 0 \
    --mlock \
    --cache-reuse 512 \
    --host $host \
    --port $port
