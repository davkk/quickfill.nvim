#!/usr/bin/env bash

host=${1:-localhost}
port=${2:-8012}

llama-server \
    --host $host \
    --port $port \
    --model ~/llms/bartowski_qwen2.5-coder-0.5b-q4_0.gguf \
    --n-gpu-layers 99 \
    --ctx-size 0 \
    --cache-reuse 512 \
    --mlock \
    --n-predict 16 \
    --top-k 20 \
    --top-p 0.3 \
    --repeat-penalty 1.5
