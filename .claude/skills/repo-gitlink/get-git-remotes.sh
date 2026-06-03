#!/bin/bash
# get-git-remotes.sh
# Extracts git remote URLs from .claude/repo subdirectories
# Output: .claude/www/git.remote
# Default: append + auto-dedup (preserves history, skips URLs already in file)
# -f, --force: reset the file before writing (no dedup needed)

FORCE=false
while [[ "$1" == -* ]]; do
    case "$1" in
        -f|--force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [-f|--force]"
            echo "  -f, --force  Reset existing output file before writing"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../repo"
OUTPUT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../www/git.remote"
WWW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../www"

mkdir -p "$WWW_DIR"

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository directory not found: $REPO_DIR" >&2
    exit 1
fi

if [ "$FORCE" = true ] && [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
fi
touch "$OUTPUT_FILE"

# Load existing URLs into an associative array (for dedup in append mode)
declare -A existing=()
if [ "$FORCE" = false ] && [ -s "$OUTPUT_FILE" ]; then
    while IFS= read -r line; do
        # Only consider lines that look like git URLs
        if [[ "$line" =~ ^(git@|https?://) ]]; then
            existing["$line"]=1
        fi
    done < "$OUTPUT_FILE"
fi

added=0
deduped=0
no_remote=0
not_git=0

for repo in "$REPO_DIR"/*/; do
    [ -d "$repo/.git" ] || { ((not_git++)); continue; }

    remote_url=$(cd "$repo" && git remote get-url origin 2>/dev/null)
    if [ -z "$remote_url" ]; then
        echo "Warning: $(basename "$repo") has no remote 'origin'" >&2
        ((no_remote++))
        continue
    fi

    if [ "${existing[$remote_url]+_}" ]; then
        ((deduped++))
        continue
    fi

    echo "$remote_url" >> "$OUTPUT_FILE"
    existing["$remote_url"]=1
    ((added++))
done

echo "Added: $added, Deduped: $deduped, NoRemote: $no_remote, NotGit: $not_git"
echo "Output: $OUTPUT_FILE"
