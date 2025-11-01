# Repository Guidelines

## Project Structure & Modules
- `main.go`: entrypoint; wires CLI to runtime.
- `cmd/chatlog/`: Cobra commands (`key`, `decrypt`, `server`, etc.).
- `internal/`: core packages — `chatlog/` (TUI flow), `ui/`, `wechat/`, `wechatdb/`, `mcp/`, `model/`, `errors/`.
- `pkg/`: shared utilities — `config/`, `util/`, `version/`, etc.
- `docs/`: guides (Docker, MCP, prompts). `script/`: packaging and entrypoint scripts.
- CI & release: `.github/workflows/release.yml`, `.goreleaser.yaml`, `Dockerfile`, `docker-compose.yml`.

## Build, Test, and Development
- `make build` — builds `bin/chatlog` for host (CGO enabled, embeds version).
- `make test` — runs `go test ./... -cover`.
- `make lint` — runs `golangci-lint`. Install locally if missing.
- `make crossbuild ENABLE_UPX=1` — multi‑arch builds.
- Run TUI locally: `go run .` or `bin/chatlog` after build.
- Docker (example): `docker-compose up -d` (mount your WeChat data to `/app/data`).

## Coding Style & Naming
- Go 1.24+. Format with `gofmt`/`goimports`; keep files go‑idiomatic (tabs, lowercase package names).
- Public identifiers use `CamelCase`; unexported `lowerCamelCase`. Keep packages cohesive and small.
- Logging: prefer `zerolog` for structured logs in new code; avoid mixing loggers per file.
- Errors: wrap with `%w`; return sentinel/types from `internal/errors` where applicable.
- Config/env: prefer `viper` and `CHATLOG_*` envs; avoid hardcoded paths.

## Testing Guidelines
- Unit tests live alongside code as `*_test.go`; use table‑driven tests (`TestXxx`).
- Separate integration tests via build tags (e.g., `//go:build integration`) or suffix like `_integration_test.go`.
- Do not depend on personal paths or real data; use temp dirs/fixtures. Run with `make test` before pushing.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat(scope): …`, `fix(scope): …`, `docs: …`, `chore: …`. Reference issues (`Fixes #123`).
- PRs should include: clear description, rationale, test coverage, and docs updates (`docs/*.md`) when behavior changes. Add TUI screenshots or API examples when UI/HTTP changes.
- Keep changes focused and minimal. Do not push `v*` tags; releases are handled by CI via GoReleaser.

## Security & Configuration Tips
- Never commit secrets, decrypted data, or local databases. Respect `.gitignore`.
- Local config: `$HOME/.chatlog/chatlog.json` (Windows: `%USERPROFILE%\.chatlog\chatlog.json`). Prefer env vars for examples.
- Handle user data carefully; avoid logging sensitive content by default.

