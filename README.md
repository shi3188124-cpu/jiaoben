# jiaoben

OpenClaw provider setup scripts for the `szy` backend at `http://122.51.82.68:8059/v1`.

## Files

- `setup-openclaw.sh` — bash script for macOS / Linux
- `setup-openclaw.ps1` — PowerShell script for Windows

## What the scripts do

- prompt for your API key
- fetch available models from the configured backend
- let you choose which models to keep
- optionally choose a default model
- back up your existing `~/.openclaw/openclaw.json`
- write the selected provider config into OpenClaw
- restart the OpenClaw gateway at the end

## Notes

- The request base URL is fixed in the scripts.
- The scripts modify your local OpenClaw config file directly.
- Your API key is written into the OpenClaw config for provider use.
- Make sure `openclaw` is already installed before running these scripts.

## macOS / Linux

```bash
chmod +x setup-openclaw.sh
./setup-openclaw.sh
```

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-openclaw.ps1
```

## Requirements

### macOS / Linux
- `openclaw`
- `python3`
- terminal with interactive key input support

### Windows
- `openclaw`
- `python` or `py -3`
- PowerShell terminal with interactive key input support
