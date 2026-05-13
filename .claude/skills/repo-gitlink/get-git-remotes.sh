#!/bin/bash
# get-git-remotes.sh
# Extracts git remote URLs from .claude/repo subdirectories
# Output: .claude/www/git.remote

FORCE=false
while [[ "$1" == -* ]]; do
    case "$1" in
        -f|--force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [-f|--force]"
            echo "  -f, --force  Overwrite existing output file"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../repo"
OUTPUT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../www/git.remote"
WWW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../www"

mkdir -p "$WWW_DIR"

if [ "$FORCE" = true ] && [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
fi

> "$OUTPUT_FILE"

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository directory not found: $REPO_DIR" >&2
    exit 1
fi

found=0
skipped=0

for repo in "$REPO_DIR"/*/; do
    if [ -d "$repo/.git" ]; then
        remote_url=$(cd "$repo" && git remote get-url origin 2>/dev/null)
        if [ -n "$remote_url" ]; then
            echo "$remote_url" >> "$OUTPUT_FILE"
            ((found++))
        else
            echo "Warning: $(basename "$repo") has no remote 'origin'" >&2
            ((skipped++))
        fi
    else
        ((skipped++))
    fi
done

echo "Done. Found: $found, Skipped: $skipped"
echo "Output: $OUTPUT_FILE"
