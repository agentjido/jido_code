# Jido Code Desktop

Desktop application powered by Phoenix LiveView and Tauri. Packages the Phoenix backend as a standalone executable via Burrito, wrapped in a native Tauri window.

This is not the normal contributor workflow. For day-to-day repository development, work from the repo root with:

```bash
mix setup
mix server
```

using a host PostgreSQL instance on `localhost:5432` with `postgres` / `postgres`.

## Prerequisites

- Elixir 1.18+, Erlang OTP 27+
- Rust 1.92+, Cargo
- Node.js 24+, npm
- Zig 0.15+ (required by Burrito, install via [ZVM](https://github.com/marler4/zvm): `zvm install 0.15.2`)
- PostgreSQL running locally

## Build

### 1. Build Phoenix desktop release

```bash
MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release jido_code_desktop
```

This produces platform-specific binaries in `burrito_out/`.

### 2. Symlink binaries for Tauri sidecar

```bash
cd tauri/src-tauri
ln -sf ../../burrito_out/jido_code_desktop_macos jido_code_backend-aarch64-apple-darwin
ln -sf ../../burrito_out/jido_code_desktop_linux jido_code_backend-x86_64-unknown-linux-gnu
ln -sf ../../burrito_out/jido_code_desktop_windows.exe jido_code_backend-x86_64-pc-windows-msvc.exe
cd ../..
```

### 3. Build Tauri desktop app

```bash
cd tauri && npx tauri build
```

## Development

To run Tauri in dev mode (still requires a built Phoenix sidecar binary):

```bash
cd tauri && npx tauri dev
```

This desktop path is separate from the normal repo-root development flow above.

## How it works

1. **Burrito** wraps the Phoenix release into platform-specific executables with an embedded Erlang runtime
2. **Tauri** launches the Phoenix binary as a sidecar process on `localhost:4000`
3. A loading screen is shown while the backend boots
4. Once the backend responds, Tauri opens a webview pointing to `localhost:4000`
5. The desktop sidecar currently expects either an explicit `DATABASE_URL` or a host PostgreSQL instance; if `DATABASE_URL` is unset it falls back to `ecto://postgres:postgres@localhost/jido_code_dev`

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `ecto://postgres:postgres@localhost/jido_code_dev` | PostgreSQL connection string |
| `PORT` | `4000` | HTTP port for the Phoenix server |
| `SECRET_KEY_BASE` | built-in fallback | Cookie signing secret |
| `TOKEN_SIGNING_SECRET` | built-in fallback | Auth token signing secret |
