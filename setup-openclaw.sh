#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="$HOME/.openclaw/openclaw.json"
BASE_URL="http://122.51.82.68:8059/v1"
PROVIDER_ID="szy"

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

read -r -s -p "Enter API Key: " API_KEY
echo

if [ -z "$API_KEY" ]; then
echo "API Key cannot be empty"
exit 1
fi

export API_KEY BASE_URL PROVIDER_ID CONFIG_PATH

python3 - <<'PY'
import json
import os
import sys
import urllib.request

config_path = os.environ["CONFIG_PATH"]
base_url = os.environ["BASE_URL"].rstrip("/")
provider_id = os.environ["PROVIDER_ID"]
api_key = os.environ["API_KEY"]

req = urllib.request.Request(
f"{base_url}/models",
headers={"Authorization": f"Bearer {api_key}"}
)

try:
with urllib.request.urlopen(req, timeout=30) as resp:
payload = json.loads(resp.read().decode("utf-8"))
except Exception as e:
print(f"Failed to fetch model list: {e}", file=sys.stderr)
sys.exit(1)

if isinstance(payload, dict) and "data" in payload:
items = payload["data"]
elif isinstance(payload, dict) and "models" in payload:
items = payload["models"]
elif isinstance(payload, list):
items = payload
else:
print("Unrecognized model response format", file=sys.stderr)
sys.exit(1)

models = []
for item in items:
model_id = item.get("id")
if not model_id:
continue
cost = item.get("cost") or {}
models.append({
"id": model_id,
"name": item.get("name") or model_id,
"reasoning": bool(item.get("reasoning", True)),
"input": item.get("input") or ["text"],
"cost": {
"input": cost.get("input", 0),
"output": cost.get("output", 0),
"cacheRead": cost.get("cacheRead", 0),
"cacheWrite": cost.get("cacheWrite", 0),
},
"contextWindow": item.get("contextWindow") or item.get("context_window") or 128000,
"maxTokens": item.get("maxTokens") or item.get("max_tokens") or 32768,
})

models.sort(key=lambda m: m["id"])
seen = set()
unique_models = []
for model in models:
if model["id"] in seen:
continue
seen.add(model["id"])
unique_models.append(model)
models = unique_models

if not models:
print("No models were returned by the API", file=sys.stderr)
sys.exit(1)

print()
print("Available models:")
for idx, model in enumerate(models, start=1):
reasoning = "reasoning" if model["reasoning"] else "no-reasoning"
print(f"[{idx}] {model['id']} ({reasoning}, ctx {model['contextWindow']}, max {model['maxTokens']})")
print()

selection = input("Select one or more model numbers (comma-separated, e.g. 1,3,5): ").strip()
parts = [p.strip() for p in selection.split(",") if p.strip()]

if not parts:
print("You must select at least one model", file=sys.stderr)
sys.exit(1)

selected_indexes = []
for part in parts:
if not part.isdigit():
print(f"Invalid selection item: {part}", file=sys.stderr)
sys.exit(1)
idx = int(part)
if idx < 1 or idx > len(models):
print(f"Selection out of range: {idx}", file=sys.stderr)
sys.exit(1)
zero_idx = idx - 1
if zero_idx not in selected_indexes:
selected_indexes.append(zero_idx)

selected_models = [models[i] for i in selected_indexes]

print()
print("Selected models:")
for idx, model in enumerate(selected_models, start=1):
print(f"[{idx}] {model['id']}")
print()

default_choice = input("Choose the default model number from the selected list: ").strip()
if not default_choice.isdigit():
print("Invalid default selection", file=sys.stderr)
sys.exit(1)

default_index = int(default_choice) - 1
if default_index < 0 or default_index >= len(selected_models):
print("Default selection out of range", file=sys.stderr)
sys.exit(1)

default_model = selected_models[default_index]
full_model = f"{provider_id}/{default_model['id']}"
backup_path = f"{config_path}.bak"

with open(config_path, "r", encoding="utf-8") as f:
data = json.load(f)

with open(backup_path, "w", encoding="utf-8") as f:
json.dump(data, f, ensure_ascii=False, indent=2)

data.setdefault("models", {})
data["models"].setdefault("providers", {})
data.setdefault("agents", {})
data["agents"].setdefault("defaults", {})
data["agents"]["defaults"].setdefault("model", {})

data["models"]["providers"][provider_id] = {
"baseUrl": base_url,
"apiKey": api_key,
"api": "openai-completions",
"models": selected_models,
}

data["agents"]["defaults"]["model"]["primary"] = full_model

with open(config_path, "w", encoding="utf-8") as f:
json.dump(data, f, ensure_ascii=False, indent=2)

print()
print("OpenClaw config updated")
print(f"Base URL: {base_url}")
print(f"Selected models: {', '.join(m['id'] for m in selected_models)}")
print(f"Default model: {full_model}")
print(f"Config file: {config_path}")
print(f"Backup file: {backup_path}")
print()
PY

openclaw gateway restart
sleep 2
openclaw status
