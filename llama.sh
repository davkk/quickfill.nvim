#!/usr/bin/env bash

host=${1:-localhost}
port=${2:-8012}

llama-server \
    -m ~/llms/sweep-next-edit-0.5b.q8_0.gguf \
    --n-gpu-layers 99 \
    --threads 8 \
    --ctx-size 0 \
    --flash-attn on \
    --mlock \
    --cache-reuse 256 \
    --verbose \
    --host $host \
    --port $port
