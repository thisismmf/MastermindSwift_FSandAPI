# Mastermind (Swift Terminal)

A tiny terminal-based **Mastermind** game in Swift with two modes:
- **Local** (offline logic)
- **API** (talks to `https://mastermind.darkube.app`)

## Rules
- Guess a **4-digit** code, digits **1..6**.
- Response after each guess:
  - **B** = correct digit in the **correct position**
  - **W** = correct digit in the **wrong position**
- Type `exit` anytime to quit.

## Requirements
- Swift **5.9+**, macOS **12+**

## Run

```bash
# Local mode (default)
swift run mastermind
# or with options
swift run mastermind --mode local --seed 42 --cheat --max 10

# API mode
swift run mastermind --mode api --base https://mastermind.darkube.app -v
# optional auth
MM_API_KEY=YOUR_TOKEN swift run mastermind --mode api
# auto-delete the game when you quit
swift run mastermind --mode api --autodelete
```

### CLI Options
- `--mode local|api` – run offline or via API  
- `--base <url>` – API base URL  
- `--apikey <token>` / `MM_API_KEY` – API key if required  
- `--max <n>` – limit attempts  
- `-v` / `--verbose` – verbose logs  
- (local only) `--seed <n>`, `--cheat`

## API Details (used by this client)
- `POST /game` → returns `{ "game_id": "<id>" }`
- `POST /guess` with body `{ "guess":"1234", "game_id":"<id>" }`
- `DELETE /game/{gameID}` (optional cleanup with `--autodelete`)

> **Note:** The provided API requires **unique digits** in each guess. The client checks this and warns before sending.

## Build (optional)
```bash
swift build -c release
.build/release/mastermind
```

Enjoy!
