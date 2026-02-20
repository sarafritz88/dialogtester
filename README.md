# Dialog System — Integration Guide

A simple JSON-driven dialog system for Godot 4. Drop in a generated JSON file, set your variables, and the UI handles the rest.

The live web tester lets anyone paste or upload a JSON file and see it running in-browser instantly — no install required.

---

## Live Web Tester (GitHub Pages)

The workflow deploys the built game directly into the `dialogTest/` folder of your `sarafritz88.github.io` repo, so it lives at:
```
https://sarafritz88.github.io/dialogTest/
```

### First-time setup

**1. Create a Personal Access Token**
The workflow needs permission to push into your Pages repo.

- Go to GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens**
- Click **Generate new token**
- Set **Repository access** to `sarafritz88/sarafritz88.github.io` only
- Under **Permissions**, give **Contents** → **Read and write**
- Copy the token

**2. Add the token as a secret in this repo**
- Go to this repo's **Settings → Secrets and variables → Actions**
- Click **New repository secret**
- Name: `PAGES_DEPLOY_TOKEN`
- Value: paste the token

**3. Push this project to GitHub**
```bash
cd /path/to/dialog-test
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/sarafritz88/<this-repo-name>.git
git branch -M main
git push -u origin main
```

The workflow runs automatically on every push to `main` and deploys to your Pages site.

### How it works

On every push to `main`, GitHub Actions:
- Installs Godot headlessly and exports the project to HTML5
- Injects a service worker for cross-origin isolation (required for Godot web exports)
- Clones your `sarafritz88.github.io` repo, replaces the `dialogTest/` folder with the fresh build, and pushes

### Checking the Godot version

The workflow uses Godot **4.4.1**. If your installed version differs, update this line in `.github/workflows/deploy.yml`:
```yaml
version: 4.4.1
```

### Using the web tester

Once deployed, users can:
- **Upload** a `.json` file using the file picker
- **Paste** raw JSON into the text area
- Click **Load into game** — the dialog restarts immediately with the new content

No page reload needed. The game keeps running and swaps the dialog live.

---

## Quick Start

1. Place your generated `dialog_data.json` in `res://` (the project root)
2. Open the project and run — the dialog loads automatically

To point to a different file, change this line in `main.gd`:
```gdscript
const DIALOG_FILE := "res://dialog_data.json"
```

---

## JSON Structure

```json
{
  "start_id": 0,
  "variables": {
	"player_name": "Traveler"
  },
  "nodes": [
	{
	  "id": 0,
	  "npc_name": "Guard",
	  "npc_line": "Halt, {player_name}. Who goes there?",
	  "choices": [
		{ "text": "A friend.", "next_id": 1 },
		{ "text": "None of your business.", "next_id": 2 }
	  ]
	}
  ]
}
```

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `start_id` | int | Yes | ID of the first node to display |
| `variables` | object | No | Key/value pairs for text substitution (see below) |
| `nodes` | array | Yes | List of dialog nodes |

### Node Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | int | Yes | Unique identifier for this node |
| `npc_name` | string | Yes | Name displayed above the NPC area |
| `npc_line` | string | Yes | The NPC's spoken line |
| `choices` | array | Yes | Player response options (at least one required) |

### Choice Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `text` | string | Yes | The text shown on the button |
| `next_id` | int | Yes | ID of the node to go to when selected. Use `-1` to end the conversation |

---

## Variables & Text Substitution

Any value in `variables` can be inserted into `npc_line`, `npc_name`, or choice `text` using `{key}` syntax.

```json
"variables": {
  "player_name": "Sara",
  "settlement": "Ironhaven",
  "days_remaining": "9"
}
```

```json
"npc_line": "You have {days_remaining} days, {player_name}. {settlement} is counting on you."
```

**Priority order** (highest wins):
1. Values set at runtime via `set_dialog_var()` in GDScript
2. Values defined in the JSON `variables` block
3. Fallback defaults in `main.gd`

### Setting Variables from GDScript

Call this before or during a conversation to inject live game data:

```gdscript
# Get a reference to the main scene
var dialog = $Main  # adjust path as needed

dialog.set_dialog_var("player_name", "Sara")
dialog.set_dialog_var("days_remaining", str(quest_timer.days_left))
```

---

## Ending a Conversation

Set `next_id` to `-1` on any choice to end the dialog. The UI will show a restart button (useful during testing).

```json
{ "text": "[Leave]", "next_id": -1 }
```

---

## Loading a Different File at Runtime

To swap conversations dynamically (e.g. different NPCs), call:

```gdscript
dialog.load_dialog_from_file("res://dialogs/merchant.json")
```

Or if your tool produces data directly in GDScript rather than a file:

```gdscript
dialog.load_dialog(nodes_array, start_id)
```

Where `nodes_array` is an `Array` of Dictionaries matching the node structure above.

---

## Node ID Rules

- IDs must be **unique integers** within a file
- IDs do **not** need to be sequential — gaps are fine (e.g. 0, 5, 10)
- `next_id` values must match an existing node ID, or be `-1`
- Multiple choices can point to the same `next_id` (branching that converges is fine)
- Nodes can reference earlier IDs to create loops

---

## Common Pitfalls

**Dialog not loading / "node not found" error**
All IDs in the JSON are parsed as numbers. Make sure `id` and `next_id` values are plain integers with no quotes around them — `0` not `"0"`.

**Variable not substituting**
Check that the key in `{curly_braces}` exactly matches the key in `variables` — substitution is case-sensitive. `{Player_Name}` and `{player_name}` are different.

**Text getting cut off**
The NPC text label auto-wraps, but very long lines may overflow the dialog box depending on window size. Aim to keep individual `npc_line` values under ~300 characters.

**Choices overflowing**
The choices container scrolls vertically if needed, but more than 4–5 choices will feel cramped. Consider splitting long choice lists across multiple nodes.
