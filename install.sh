#!/bin/bash
# callrec installer. Idempotent — safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
BIN="$HOME/bin"

echo "==> dependencies"
command -v brew >/dev/null || { echo "install Homebrew first: https://brew.sh"; exit 1; }
for f in ffmpeg whisper-cpp; do
  brew list --formula "$f" >/dev/null 2>&1 || brew install "$f"
done
brew list --cask blackhole-2ch >/dev/null 2>&1 || {
  echo "--> installing BlackHole 2ch (asks for your password, then restarts CoreAudio)"
  brew install --cask blackhole-2ch
  sudo killall coreaudiod || true
  sleep 2
}

echo "==> whisper model (~1.6GB, once)"
MODEL="$HOME/.cache/whisper/ggml-large-v3-turbo.bin"
[ -f "$MODEL" ] || {
  mkdir -p "$(dirname "$MODEL")"
  curl -L --progress-bar -o "$MODEL" \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
}

echo "==> cli"
mkdir -p "$BIN"
install -m 755 bin/callrec "$BIN/callrec"
swiftc -O audio/setout.swift -o "$BIN/setout"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"; echo "   added ~/bin to PATH in .zshrc" ;;
esac

echo "==> audio routing"
swiftc -O audio/make-multi-output.swift -o /tmp/callrec-mkmulti && /tmp/callrec-mkmulti

echo "==> menu bar app"
bash app/build.sh

cat <<'EOF'

Done.

  open ~/Applications/CallRec.app     # menu bar dot: click, name the call, record
  callrec start <name> / callrec stop # same thing from the terminal

First recording will ask for microphone permission. Say yes.
EOF
