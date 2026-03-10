#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="$HOME/.openclaw/openclaw.json"
BASE_URL="http://122.51.82.68:8059/v1"
PROVIDER_ID="szy"
MODEL_ID="gpt-5.4"
FULL_MODEL="$PROVIDER_ID/$MODEL_ID"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw not found. Please install OpenClaw first."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. Please install Python 3 first."
  exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "OpenClaw config file not found: $CONFIG_PATH"
  exit 1
fi

read -s -p "Enter API Key: " API_KEY
echo

if [ -z "$API_KEY" ]; then
  echo "API Key cannot be empty"
  exit 1
fi

export API_KEY

python3 - <<'PY'
import json
import os

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
base_url = "http://122.51.82.68:8059/v1"
provider_id = "szy"
model_id = "gpt-5.4"
full_model = f"{provider_id}/{model_id}"
api_key = os.environ.get("API_KEY", "")

with open(config_path, "r", encoding="utf-8") as f:
    data = json.load(f)

data.setdefault("models", {})
data["models"].setdefault("providers", {})
data.setdefault("agents", {})
data["agents"].setdefault("defaults", {})
data["agents"]["defaults"].setdefault("model", {})

data["models"]["providers"][provider_id] = {
    "baseUrl": base_url,
    "apiKey": api_key,
    "api": "openai-completions",
    "models": [
        {
            "id": model_id,
            "name": "GPT-5.4",
            "reasoning": True,
            "input": ["text"],
            "cost": {
                "input": 0,
                "output": 0,
                "cacheRead": 0,
                "cacheWrite": 0
            },
            "contextWindow": 128000,
            "maxTokens": 32768
        }
    ]
}

data["agents"]["defaults"]["model"]["primary"] = full_model

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY

echo
echo "OpenClaw config updated"
echo "Default model: $FULL_MODEL"
echo "Config file: $CONFIG_PATH"
echo

openclaw gateway restart
sleep 2
openclaw status
