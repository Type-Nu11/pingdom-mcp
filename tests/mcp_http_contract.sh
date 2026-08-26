#!/usr/bin/env sh
set -eu

image_name="pingdom-mcp-http-contract"
container_name="pingdom-mcp-http-contract"
host_port="18081"

cleanup() {
    docker rm --force "$container_name" >/dev/null 2>&1 || true
}

cleanup
trap cleanup EXIT

docker build --tag "$image_name" .
docker run --detach --rm --name "$container_name" --publish "127.0.0.1:${host_port}:8080" "$image_name" >/dev/null

attempt=0
while [ "$attempt" -lt 10 ]; do
    response="$(curl --silent --show-error --max-time 1 \
        --header 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","id":1400,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"http-contract-test","version":"1"}}}' \
        "http://127.0.0.1:${host_port}/mcp" 2>/dev/null || true)"
    if printf '%s' "$response" | grep -q '"jsonrpc":"2.0"'; then
        printf '%s' "$response" | grep -q '"id":1400'
        printf 'MCP HTTP contract passed\n'
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 1
done

docker logs "$container_name"
printf 'MCP HTTP contract failed: /mcp did not return JSON-RPC bytes\n' >&2
exit 1
