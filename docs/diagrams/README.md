# Diagrams

Editable [draw.io](https://www.drawio.com/) (diagrams.net) source files for this project.

| File | Shows |
|------|-------|
| `architecture.drawio` | Clusters, shared storage, managed identity, and how they connect. |
| `backup-flow.drawio` | What happens during a backup (resources + CSI snapshots → Blob). |
| `restore-flow.drawio` | What happens during a restore (Blob → destination, namespace mapping, PVs). |

## How to view / edit

- **VS Code:** install the *Draw.io Integration* extension (`hediet.vscode-drawio`), then open any `.drawio` file — it renders and edits inline.
- **Browser / desktop:** open [app.diagrams.net](https://app.diagrams.net) and load the file, or use the draw.io desktop app.

## Exporting to images (optional)

`.drawio` files do not render on GitHub automatically. To show them in Markdown, export to PNG/SVG:

- In the draw.io app: **File → Export as → PNG/SVG**, save alongside the `.drawio` file (e.g. `architecture.png`).
- Or with the CLI:
  ```bash
  drawio --export --format png --output architecture.png architecture.drawio
  ```

Then reference the image in Markdown: `![Architecture](docs/diagrams/architecture.png)`.

> The [ARCHITECTURE](../ARCHITECTURE.md) doc also contains Mermaid versions of these diagrams, which **do** render inline on GitHub. Use the `.drawio` files when you want to edit or produce polished exports.
