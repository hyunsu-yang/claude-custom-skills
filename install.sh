#!/bin/bash
# Claude Custom Skills installer
# Usage:
#   bash install.sh              # Install all (global + prompt for project paths)
#   bash install.sh --global     # Global skills only
#   bash install.sh --project tradingapp /path/to/project

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLOBAL_SRC="$SCRIPT_DIR/skills/global"
GLOBAL_DST="$HOME/.claude/skills"
COMMANDS_SRC="$SCRIPT_DIR/commands"
COMMANDS_DST="$HOME/.claude/commands"

install_global() {
  echo "=== Installing global skills ==="
  mkdir -p "$GLOBAL_DST"
  for skill_dir in "$GLOBAL_SRC"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$GLOBAL_DST/$skill_name"
    if [ -L "$target" ]; then
      echo "  [skip] $skill_name (symlink exists)"
    else
      rm -rf "$target"
      ln -s "$skill_dir" "$target"
      echo "  [link] $skill_name -> $skill_dir"
    fi
  done
}

install_commands() {
  echo "=== Installing global commands ==="
  if [ ! -d "$COMMANDS_SRC" ]; then
    echo "  (no commands/ directory — skipping)"
    return 0
  fi
  mkdir -p "$COMMANDS_DST"
  for cmd_file in "$COMMANDS_SRC"/*.md; do
    [ -e "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    target="$COMMANDS_DST/$cmd_name"
    if [ -L "$target" ]; then
      echo "  [skip] $cmd_name (symlink exists)"
    elif [ -e "$target" ]; then
      # 이 레포가 관리하지 않는 실물 파일 — 덮어쓰지 않는다
      echo "  [WARN] $cmd_name exists as a real file, not managed by this repo — skipped"
      echo "         (to adopt it: move it into $COMMANDS_SRC, then rerun)"
    else
      ln -s "$cmd_file" "$target"
      echo "  [link] $cmd_name -> $cmd_file"
    fi
  done
}

install_project() {
  local project_name="$1"
  local project_path="$2"
  local src="$SCRIPT_DIR/skills/$project_name"
  local dst="$project_path/.claude/skills"

  if [ ! -d "$src" ]; then
    echo "Error: project '$project_name' not found in skills/"
    exit 1
  fi
  if [ ! -d "$project_path" ]; then
    echo "Error: project path '$project_path' does not exist"
    exit 1
  fi

  echo "=== Installing $project_name skills to $dst ==="
  mkdir -p "$dst"
  for skill_dir in "$src"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$dst/$skill_name"
    if [ -L "$target" ]; then
      echo "  [skip] $skill_name (symlink exists)"
    else
      rm -rf "$target"
      ln -s "$skill_dir" "$target"
      echo "  [link] $skill_name -> $skill_dir"
    fi
  done
}

case "${1:-all}" in
  --global)
    install_global
    echo ""
    install_commands
    ;;
  --commands)
    install_commands
    ;;
  --project)
    install_project "$2" "$3"
    ;;
  all)
    install_global
    echo ""
    install_commands
    echo ""
    echo "Global skills and commands installed."
    echo "To install project skills, run:"
    echo "  bash install.sh --project tradingapp /path/to/tradingapp"
    echo "  bash install.sh --project stockapp /path/to/stockapp"
    ;;
  *)
    echo "Usage:"
    echo "  bash install.sh              # Global skills + commands + instructions"
    echo "  bash install.sh --global     # Global skills + commands"
    echo "  bash install.sh --commands   # Slash commands only"
    echo "  bash install.sh --project <name> <path>"
    ;;
esac

echo ""
echo "Done."
