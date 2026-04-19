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
    ;;
  --project)
    install_project "$2" "$3"
    ;;
  all)
    install_global
    echo ""
    echo "Global skills installed."
    echo "To install project skills, run:"
    echo "  bash install.sh --project tradingapp /path/to/tradingapp"
    ;;
  *)
    echo "Usage:"
    echo "  bash install.sh              # Global skills only + instructions"
    echo "  bash install.sh --global     # Global skills only"
    echo "  bash install.sh --project <name> <path>"
    ;;
esac

echo ""
echo "Done."
