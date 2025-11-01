#!/usr/bin/env bash
set -euo pipefail

# Local builder for chatlog. Supports Ubuntu/Linux and preinstalled Go.

GO_VERSION_DEFAULT="1.24.0"
BINARY_NAME="chatlog"
OUT_DIR="bin"
OUT_PATH="${OUT_DIR}/${BINARY_NAME}"
SKIP_INSTALL=${SKIP_INSTALL:-0}
GO_VERSION="${GO_VERSION:-$GO_VERSION_DEFAULT}"
# Prefer user-level toolchain dir, not inside the repo
TOOLCHAIN_DIR_DEFAULT="${XDG_DATA_HOME:-$HOME/.local/share}/chatlog-tools"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$TOOLCHAIN_DIR_DEFAULT}"

usage() {
  cat <<EOF
Usage: $0 [--go-version X.Y.Z] [--skip-install] [--target OS/ARCH]

Builds bin/chatlog with CGO enabled and embedded version string.
Environment:
  SKIP_INSTALL=1    Skip installing toolchain packages
  GO_VERSION=X.Y.Z  Go version to install (default: ${GO_VERSION_DEFAULT})
  TOOLCHAIN_DIR=DIR Install/use toolchains under DIR (default: ${TOOLCHAIN_DIR_DEFAULT})

Examples:
  $0                       # build for current platform
  $0 --target windows/amd64  # cross-build Windows .exe (uses Zig if no mingw)
EOF
}

log() { printf "[%s] %s\n" "$1" "$2"; }
info() { log INFO "$1"; }
warn() { log WARN "$1"; }
err()  { log ERROR "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --go-version)
        GO_VERSION=${2:-}; shift 2;;
      --toolchain-dir)
        TOOLCHAIN_DIR=${2:-}; shift 2;;
      --target)
        TARGET=${2:-}; shift 2;;
      --skip-install)
        SKIP_INSTALL=1; shift;;
      -h|--help)
        usage; exit 0;;
      *)
        err "Unknown arg: $1"; usage; exit 2;;
    esac
  done
}

need_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ] && have sudo; then echo sudo; else echo ""; fi
}

ensure_build_essentials() {
  if [ "${SKIP_INSTALL}" = "1" ]; then return 0; fi
  if [ -f /etc/debian_version ] && have apt-get && have sudo; then
    info "Installing build tools (apt-get)"
    set +e
    $(need_sudo) apt-get update -y && $(need_sudo) apt-get install -y build-essential curl ca-certificates
    local rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      warn "apt install failed or not permitted; will try local toolchain bootstrap."
    fi
  else
    warn "No sudo/apt or unsupported distro; will try local toolchain bootstrap."
  fi
}

install_go_local() {
  local tools="$TOOLCHAIN_DIR"
  local go_root="$tools/go-${GO_VERSION}"
  local go_bin="$go_root/go/bin/go"
  if [ -x "$go_bin" ]; then
    info "Using local Go at $go_bin"
    export PATH="$go_root/go/bin:$PATH"
    return 0
  fi
  mkdir -p "$tools"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64) arch2=amd64;;
    aarch64) arch2=arm64;;
    *) err "Unsupported arch for local Go: $arch"; exit 1;;
  esac
  local url1="https://go.dev/dl/go${GO_VERSION}.linux-${arch2}.tar.gz"
  local url2="https://storage.googleapis.com/golang/go${GO_VERSION}.linux-${arch2}.tar.gz"
  info "Downloading Go ${GO_VERSION} -> $url1 (fallback: $url2)"
  if ! curl -fsSL -o "$tools/go.tgz" "$url1"; then
    warn "Primary Go download failed; trying fallback"
    curl -fsSL -o "$tools/go.tgz" "$url2"
  fi
  mkdir -p "$go_root"
  tar -C "$go_root" -xzf "$tools/go.tgz"
  rm -f "$tools/go.tgz"
  export PATH="$go_root/go/bin:$PATH"
  info "Installed local Go: $(go version)"
}

install_zig_local() {
  local tools="$TOOLCHAIN_DIR"
  local zig_root="$tools/zig"
  local zig_bin="$zig_root/zig"
  if [ -x "$zig_bin" ]; then
    info "Using local Zig at $zig_bin"
    export PATH="$zig_root:$PATH"
    export CC="zig cc" CXX="zig c++"
    return 0
  fi
  mkdir -p "$tools"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64) zig_pkg="zig-linux-x86_64-0.13.0";;
    aarch64) zig_pkg="zig-linux-aarch64-0.13.0";;
    *) err "Unsupported arch for Zig: $arch"; exit 1;;
  esac
  local url="https://ziglang.org/download/0.13.0/${zig_pkg}.tar.xz"
  info "Downloading Zig -> $url"
  curl -fsSL -o "$tools/zig.tar.xz" "$url"
  mkdir -p "$zig_root"
  tar -C "$tools" -xJf "$tools/zig.tar.xz"
  rm -f "$tools/zig.tar.xz"
  # Move/rename to stable path
  rm -rf "$zig_root" || true
  mv "$tools/${zig_pkg}" "$zig_root"
  export PATH="$zig_root:$PATH"
  export CC="zig cc" CXX="zig c++"
  info "Installed local Zig: $(zig version)"
}

# Migrate old repo-local toolchains from ./\.tools to user-level TOOLCHAIN_DIR
migrate_repo_tools() {
  local old_tools="$PWD/.tools"
  if [ -d "$old_tools" ]; then
    mkdir -p "$TOOLCHAIN_DIR"
    if [ -d "$old_tools/go-${GO_VERSION}" ] && [ ! -d "$TOOLCHAIN_DIR/go-${GO_VERSION}" ]; then
      info "Migrating Go toolchain from repo .tools to ${TOOLCHAIN_DIR}"
      mv "$old_tools/go-${GO_VERSION}" "$TOOLCHAIN_DIR/"
    fi
    if [ -d "$old_tools/zig" ] && [ ! -d "$TOOLCHAIN_DIR/zig" ]; then
      info "Migrating Zig toolchain from repo .tools to ${TOOLCHAIN_DIR}"
      mv "$old_tools/zig" "$TOOLCHAIN_DIR/"
    fi
    # Remove old directory if empty
    rmdir "$old_tools" 2>/dev/null || true
  fi
}

ensure_go() {
  if have go; then
    info "Go found: $(go version)"
    return 0
  fi
  # Try system install (may fail without sudo), then local fallback
  if [ -f /etc/debian_version ] && have apt-get && have sudo && [ "${SKIP_INSTALL}" != "1" ]; then
    set +e
    $(need_sudo) apt-get update -y && $(need_sudo) apt-get install -y curl ca-certificates golang
    local rc=$?
    set -e
    if [ $rc -eq 0 ] && have go; then
      info "Go installed via apt: $(go version)"
      return 0
    fi
    warn "apt golang install failed; falling back to local Go."
  fi
  install_go_local
}

# Create a CC/CXX wrapper for a Zig target
ensure_zig_wrappers() {
  local zig_root="$TOOLCHAIN_DIR/zig"
  local zig_bin="$zig_root/zig"
  if [ ! -x "$zig_bin" ]; then
    install_zig_local
  fi
  local triple="$1"  # e.g., x86_64-windows-gnu
  local wrap_dir="$TOOLCHAIN_DIR/wrappers/$triple"
  mkdir -p "$wrap_dir"
  local ccwrap="$wrap_dir/cc"
  local cxxwrap="$wrap_dir/cxx"
  # Always (re)write wrappers to ensure correct content
  cat >"$ccwrap" <<EOF
#!/usr/bin/env bash
exec "$zig_bin" cc -target $triple "\$@"
EOF
  chmod +x "$ccwrap"
  cat >"$cxxwrap" <<EOF
#!/usr/bin/env bash
exec "$zig_bin" c++ -target $triple "\$@"
EOF
  chmod +x "$cxxwrap"
  export CC="$ccwrap" CXX="$cxxwrap"
}

normalize_target() {
  # Sets GOOS/GOARCH and OUT_PATH based on TARGET or host
  local host_os host_arch
  host_os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$host_os" in linux*) host_os=linux;; darwin*) host_os=darwin;; msys*|mingw*|cygwin*) host_os=windows;; esac
  host_arch=$(uname -m)
  case "$host_arch" in x86_64) host_arch=amd64;; aarch64) host_arch=arm64;; esac
  local os=${host_os}
  local arch=${host_arch}
  if [ -n "${TARGET:-}" ]; then
    os=${TARGET%/*}
    arch=${TARGET#*/}
  fi
  export GOOS="$os" GOARCH="$arch"
  local ext=""
  [ "$os" = "windows" ] && ext=".exe"
  if [ -n "${TARGET:-}" ]; then
    OUT_PATH="${OUT_DIR}/${BINARY_NAME}_${os}_${arch}${ext}"
  else
    OUT_PATH="${OUT_DIR}/${BINARY_NAME}${ext}"
  fi
}

build() {
  mkdir -p "${OUT_DIR}"
  # Ensure Go exists in PATH (system or local)
  if ! have go; then
    err "go not found. Run again after ensure_go or with network access."; exit 1
  fi
  normalize_target
  # Ensure a C compiler exists. For Windows/other targets, use Zig wrappers.
  if [ "$GOOS" = "windows" ]; then
    local arch_triple
    case "$GOARCH" in
      amd64) arch_triple="x86_64";;
      arm64) arch_triple="aarch64";;
      *) err "Unsupported GOARCH for Windows: $GOARCH"; exit 1;;
    esac
    ensure_zig_wrappers "${arch_triple}-windows-gnu"
  else
    if ! have gcc && ! have cc; then
      install_zig_local
      export CC="$(command -v zig) cc" CXX="$(command -v zig) c++"
    fi
  fi
  local version
  version=$(git describe --tags --always --dirty="-dev" 2>/dev/null || echo dev)
  info "Building ${BINARY_NAME} (version: ${version})"
  export CGO_ENABLED=1
  # CC/CXX already exported when needed
  go build -trimpath \
    -ldflags "-X github.com/sjzar/chatlog/pkg/version.Version=${version} -w -s" \
    -o "${OUT_PATH}" main.go
  info "Built: ${OUT_PATH}"
  ls -la "${OUT_DIR}" || true
  "${OUT_PATH}" version || true
}

main() {
  parse_args "$@"
  migrate_repo_tools
  ensure_build_essentials
  ensure_go
  build
}

main "$@"
