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

printf "Enter API Key: "
stty -echo
read -r API_KEY
stty echo
printf "\n"

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
from datetime import datetime

config_path = os.environ["CONFIG_PATH"]
base_url = os.environ["BASE_URL"].rstrip("/")
provider_id = os.environ["PROVIDER_ID"]
api_key = os.environ["API_KEY"]


def normalize_input(value):
    if value is None:
        return ["text"]
    if isinstance(value, str):
        value = value.strip()
        return [value] if value else ["text"]
    if isinstance(value, list):
        normalized = [str(item).strip() for item in value if str(item).strip()]
        return normalized or ["text"]
    text = str(value).strip()
    return [text] if text else ["text"]


req = urllib.request.Request(
    f"{base_url}/models",
    headers={"Authorization": f"Bearer {api_key}"},
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
        "input": normalize_input(item.get("input")),
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


def clear_screen():
    os.system("cls" if os.name == "nt" else "clear")


def read_key():
    try:
        import msvcrt  # type: ignore

        first = msvcrt.getwch()
        if first in ("\r", "\n"):
            return "ENTER"
        if first == " ":
            return "SPACE"
        if first in ("\x00", "\xe0"):
            second = msvcrt.getwch()
            if second == "H":
                return "UP"
            if second == "P":
                return "DOWN"
        return None
    except ImportError:
        import termios
        import tty

        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            first = sys.stdin.read(1)
            if first in ("\r", "\n"):
                return "ENTER"
            if first == " ":
                return "SPACE"
            if first == "\x1b":
                second = sys.stdin.read(1)
                third = sys.stdin.read(1)
                if second == "[" and third == "A":
                    return "UP"
                if second == "[" and third == "B":
                    return "DOWN"
            return None
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)


def select_models_interactive(models):
    selected = set()
    cursor = 0
    while True:
        clear_screen()
        print("Available models:")
        print("Use Up/Down to move, Space to select, Enter to confirm.")
        print()
        for idx, model in enumerate(models):
            pointer = ">" if idx == cursor else " "
            marker = "[x]" if idx in selected else "[ ]"
            reasoning = "reasoning" if model["reasoning"] else "no-reasoning"
            print(f"{pointer} {marker} {model['id']} ({reasoning}, ctx {model['contextWindow']}, max {model['maxTokens']})")
        print()
        print(f"Selected: {len(selected)}")
        key = read_key()
        if key == "UP":
            cursor = (cursor - 1) % len(models)
        elif key == "DOWN":
            cursor = (cursor + 1) % len(models)
        elif key == "SPACE":
            if cursor in selected:
                selected.remove(cursor)
            else:
                selected.add(cursor)
        elif key == "ENTER":
            if selected:
                return [models[i] for i in sorted(selected)]


def select_default_interactive(selected_models, current_default):
    options = [{"label": "Keep current default model", "value": None}]
    options.extend({"label": model["id"], "value": model["id"]} for model in selected_models)

    cursor = 0
    selected = 0
    normalized_current = current_default
    prefix = f"{provider_id}/"

    if normalized_current and normalized_current.startswith(prefix):
        normalized_current = normalized_current[len(prefix):]

    if normalized_current:
        for idx, option in enumerate(options[1:], start=1):
            if option["value"] == normalized_current:
                cursor = idx
                selected = idx
                break

    while True:
        clear_screen()
        print("Choose default model:")
        print("Use Up/Down to move, Space to select, Enter to confirm.")
        print(f"Current default: {current_default or '(not set)'}")
        print()
        for idx, option in enumerate(options):
            pointer = ">" if idx == cursor else " "
            marker = "(*)" if idx == selected else "( )"
            print(f"{pointer} {marker} {option['label']}")
        key = read_key()
        if key == "UP":
            cursor = (cursor - 1) % len(options)
        elif key == "DOWN":
            cursor = (cursor + 1) % len(options)
        elif key == "SPACE":
            selected = cursor
        elif key == "ENTER":
            return options[selected]["value"]


selected_models = select_models_interactive(models)

with open(config_path, "r", encoding="utf-8") as f:
    data = json.load(f)

current_default = ((((data.get("agents") or {}).get("defaults") or {}).get("model") or {}).get("primary"))
selected_default_id = select_default_interactive(selected_models, current_default)
full_model = f"{provider_id}/{selected_default_id}" if selected_default_id else None
backup_path = f"{config_path}.bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

with open(backup_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

data.setdefault("auth", {})
data["auth"].setdefault("profiles", {})
data.setdefault("models", {})
data["models"].setdefault("providers", {})
data.setdefault("agents", {})
data["agents"].setdefault("defaults", {})
data["agents"]["defaults"].setdefault("model", {})

data["auth"]["profiles"][f"{provider_id}:default"] = {
    "provider": provider_id,
    "mode": "api_key",
}

data["models"]["providers"][provider_id] = {
    "baseUrl": base_url,
    "apiKey": api_key,
    "api": "openai-completions",
    "models": selected_models,
}

if full_model:
    data["agents"]["defaults"]["model"]["primary"] = full_model

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

with open(config_path, "r", encoding="utf-8") as f:
    written = json.load(f)

written_models = ((((written.get("models") or {}).get("providers") or {}).get(provider_id) or {}).get("models")) or []
if not written_models:
    print(f"Provider '{provider_id}' has no models after write", file=sys.stderr)
    sys.exit(1)

for model in written_models:
    model_input = normalize_input(model.get("input"))
    if not model_input:
        print(
            f"Provider '{provider_id}' model '{model.get('id')}' is missing input values after write",
            file=sys.stderr,
        )
        sys.exit(1)

print()
print("OpenClaw config updated")
print(f"Base URL: {base_url}")
print(f"Selected models: {', '.join(m['id'] for m in selected_models)}")
if full_model:
    print(f"Default model: {full_model}")
else:
    print("Default model: kept existing value")
print(f"Config file: {config_path}")
print(f"Backup file: {backup_path}")
print()
PY

echo
printf '%s\n' "Requesting gateway restart..."
openclaw gateway restart
printf '%s\n' "Done."
