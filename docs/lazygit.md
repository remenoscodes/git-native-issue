# lazygit Integration

Add issue tracking to [lazygit](https://github.com/jesseduffield/lazygit) via custom commands. Browse, create, comment on, and close issues without leaving the TUI.

## Setup

Add the following to your lazygit config file:

- **macOS**: `~/Library/Application Support/lazygit/config.yml`
- **Linux**: `~/.config/lazygit/config.yml`

```yaml
customCommands:
  # ── List issues ────────────────────────────────────────────
  - key: 'I'
    description: 'List issues (git-native-issue)'
    command: 'git issue ls --format full'
    context: 'global'
    output: 'popup'
    outputTitle: 'Issues'

  # ── Show issue details ────────────────────────────────────
  - key: 'i'
    description: 'Show issue details'
    context: 'global'
    output: 'popup'
    outputTitle: 'Issue Details'
    prompts:
      - type: 'menuFromCommand'
        title: 'Select issue'
        key: 'Issue'
        command: 'git issue ls --format oneline'
        filter: '(?P<value>^\S+)\s+\S+\s+(?P<label>.+)$'
    command: 'git issue show {{.Form.Issue}}'

  # ── Create issue ──────────────────────────────────────────
  - key: 'C'
    description: 'Create issue'
    context: 'global'
    prompts:
      - type: 'input'
        title: 'Issue title'
        key: 'Title'
      - type: 'menu'
        title: 'Priority'
        key: 'Priority'
        options:
          - value: ''
            name: 'none'
            description: 'No priority'
          - value: '-p low'
            name: 'low'
          - value: '-p medium'
            name: 'medium'
          - value: '-p high'
            name: 'high'
          - value: '-p critical'
            name: 'critical'
      - type: 'input'
        title: 'Labels (comma-separated, or empty)'
        key: 'Labels'
    command: >-
      git issue create "{{.Form.Title}}"
      {{.Form.Priority}}
      {{if .Form.Labels}}{{range $label := split .Form.Labels ","}} -l "{{trim $label}}"{{end}}{{end}}
    loadingText: 'Creating issue...'
    output: 'log'

  # ── Comment on issue ──────────────────────────────────────
  - key: 'c'
    description: 'Comment on issue'
    context: 'global'
    prompts:
      - type: 'menuFromCommand'
        title: 'Select issue'
        key: 'Issue'
        command: 'git issue ls --format oneline'
        filter: '(?P<value>^\S+)\s+\S+\s+(?P<label>.+)$'
      - type: 'input'
        title: 'Comment'
        key: 'Comment'
    command: 'git issue comment {{.Form.Issue}} -m "{{.Form.Comment}}"'
    loadingText: 'Adding comment...'
    output: 'log'

  # ── Close issue ───────────────────────────────────────────
  - key: 'X'
    description: 'Close issue'
    context: 'global'
    prompts:
      - type: 'menuFromCommand'
        title: 'Select issue to close'
        key: 'Issue'
        command: 'git issue ls --format oneline --state open'
        filter: '(?P<value>^\S+)\s+\S+\s+(?P<label>.+)$'
      - type: 'input'
        title: 'Close reason (optional)'
        key: 'Reason'
    command: >-
      git issue state {{.Form.Issue}} --close
      {{if .Form.Reason}}-m "{{.Form.Reason}}"{{end}}
    loadingText: 'Closing issue...'
    output: 'log'

  # ── Search issues ─────────────────────────────────────────
  - key: '/'
    description: 'Search issues'
    context: 'global'
    output: 'popup'
    outputTitle: 'Search Results'
    prompts:
      - type: 'input'
        title: 'Search pattern'
        key: 'Pattern'
    command: 'git issue search "{{.Form.Pattern}}"'
```

## Keybinding Summary

| Key | Action | Context |
|-----|--------|---------|
| `Shift+I` | List all issues | Global |
| `i` | Show issue details (picker) | Global |
| `Shift+C` | Create new issue | Global |
| `c` | Comment on issue (picker) | Global |
| `Shift+X` | Close issue (picker) | Global |
| `/` | Search issues | Global |

## Requirements

- [git-native-issue](https://github.com/remenoscodes/git-native-issue) installed
- lazygit 0.40+ (custom commands support)

## Notes

- All commands use `global` context so they work from any lazygit panel
- The `menuFromCommand` prompts parse `git issue ls --format oneline` output to build interactive pickers
- Customize keybindings to avoid conflicts with your existing config
- The `/` key may conflict with lazygit's built-in search — remap if needed
