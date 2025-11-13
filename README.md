# PR Context Generator

Generates LLM-ready context files from GitHub pull requests without affecting your local git state.

## Setup

1. Install `jq`: `sudo apt-get install jq` or `brew install jq`

2. Create GitHub token at https://github.com/settings/tokens with `repo` scope

3. Add to `~/.profile`:
```bash
export GITHUB_TOKEN='ghp_your_token_here'
```

4. Place script at `~/scripts/pr-context` and make executable:
```bash
chmod +x ~/scripts/pr-context
```

## VSCode Task

Create `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Generate PR Context",
      "type": "shell",
      "command": "/home/luke/scripts/pr-context -o /home/luke/.pr-context/out.txt ${input:branchNames}",
      "options": {
        "cwd": "${workspaceFolder}",
        "env": {
          "GITHUB_TOKEN": "<YOUR-GPG-TOKEN-HERE>"
        }
      },
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      },
      "problemMatcher": []
    }
  ],
  "inputs": [
    {
      "id": "branchNames",
      "type": "promptString",
      "description": "Branch names (space-separated)"
    }
  ]
}
```

Replace `ghp_your_token_here` with your actual token.

## Usage

VSCode: `Ctrl+Shift+P` > "Tasks: Run Task" > "Generate PR Context"

Command line: `~/scripts/pr-context branch-name`
