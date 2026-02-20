#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --selfhosted        Also start self-hosted ntfy server + tunnel"
    echo "                      (default: webhook tunnel only, use ntfy.sh public)"
    echo "  --token <TOKEN>     Use Cloudflare Named Tunnel (permanent URL)"
    echo "                      Obtain a token from the Cloudflare Zero Trust dashboard"
    echo "  -h, --help          Show this help"
}

PROFILE_ARGS=""
SELFHOSTED=false
TUNNEL_TOKEN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --selfhosted)
            PROFILE_ARGS="--profile selfhosted"
            SELFHOSTED=true
            shift
            ;;
        --token)
            if [[ $# -lt 2 ]]; then
                echo "Error: --token requires a value"
                exit 1
            fi
            TUNNEL_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Named Tunnel mode: override the command to use token-based tunnel
NAMED_TUNNEL=false
export CLOUDFLARE_TUNNEL_TOKEN=""
export TUNNEL_WEBHOOK_COMMAND=""

if [ -n "$TUNNEL_TOKEN" ]; then
    NAMED_TUNNEL=true
    export CLOUDFLARE_TUNNEL_TOKEN="$TUNNEL_TOKEN"
    export TUNNEL_WEBHOOK_COMMAND="tunnel --no-autoupdate run"
fi

echo "Starting asuku notification services..."
if [ "$NAMED_TUNNEL" = true ]; then
    echo "Mode: Named Tunnel (permanent URL)"
else
    echo "Mode: Quick Tunnel (temporary URL)"
fi

docker compose -f "$COMPOSE_FILE" $PROFILE_ARGS up -d

# Named Tunnel: URL is configured in Cloudflare dashboard, no need to extract
if [ "$NAMED_TUNNEL" = true ]; then
    echo ""
    echo "========================================="
    echo "  asuku Notification Services"
    echo "========================================="
    echo ""
    echo "Named Tunnel is running."
    echo "  Webhook URL is configured in your Cloudflare Zero Trust dashboard."
    echo "  → Paste your tunnel's public hostname into 'Webhook URL' in asuku Settings"

    if [ "$SELFHOSTED" = true ]; then
        echo ""
        echo "ntfy server is running locally."
        echo "  Configure an additional public hostname in Cloudflare dashboard"
        echo "  pointing to http://ntfy:80 for iPhone access."
    fi

    echo ""
    echo "To stop:  docker compose -f $COMPOSE_FILE $PROFILE_ARGS down"
    echo "To logs:  docker compose -f $COMPOSE_FILE $PROFILE_ARGS logs -f"
    exit 0
fi

# Quick Tunnel: poll for generated URLs
echo "Waiting for tunnels to initialize..."

MAX_ATTEMPTS=15
WEBHOOK_URL=""
NTFY_URL=""

for i in $(seq 1 $MAX_ATTEMPTS); do
    if [ -z "$WEBHOOK_URL" ]; then
        WEBHOOK_URL=$(docker compose -f "$COMPOSE_FILE" $PROFILE_ARGS logs tunnel-webhook 2>&1 \
            | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)
    fi

    if [ "$SELFHOSTED" = true ] && [ -z "$NTFY_URL" ]; then
        NTFY_URL=$(docker compose -f "$COMPOSE_FILE" $PROFILE_ARGS logs tunnel-ntfy 2>&1 \
            | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)
    fi

    # Check if we have all needed URLs
    if [ -n "$WEBHOOK_URL" ]; then
        if [ "$SELFHOSTED" = false ] || [ -n "$NTFY_URL" ]; then
            break
        fi
    fi

    sleep 2
done

echo ""
echo "========================================="
echo "  asuku Notification Services"
echo "========================================="
echo ""

if [ -n "$WEBHOOK_URL" ]; then
    echo "Webhook URL: $WEBHOOK_URL"
    echo "  → Paste into 'Webhook URL' in asuku Settings"
else
    echo "Webhook tunnel URL not ready yet."
    echo "  Check logs: docker compose -f $COMPOSE_FILE logs tunnel-webhook"
fi

if [ "$SELFHOSTED" = true ]; then
    echo ""
    if [ -n "$NTFY_URL" ]; then
        echo "ntfy Server URL: $NTFY_URL"
        echo "  → Set as 'Server URL' in asuku Settings"
        echo "  → On iPhone ntfy app: Add server with this URL, then subscribe to your topic"
    else
        echo "ntfy tunnel URL not ready yet."
        echo "  Check logs: docker compose -f $COMPOSE_FILE logs tunnel-ntfy"
    fi
else
    echo ""
    echo "Using ntfy.sh public server (default)."
    echo "  → Server URL in asuku Settings: https://ntfy.sh"
fi

echo ""
echo "NOTE: Quick Tunnel URLs change on each restart."
echo "  For permanent URLs, use: $0 --token <CLOUDFLARE_TUNNEL_TOKEN>"
echo ""
echo "To stop:  docker compose -f $COMPOSE_FILE $PROFILE_ARGS down"
echo "To logs:  docker compose -f $COMPOSE_FILE $PROFILE_ARGS logs -f"
