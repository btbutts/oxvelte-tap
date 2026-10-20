#!/usr/bin/env bash
set -euo pipefail

# Create a new release of oxvelte.
#
# Usage:
#   ./scripts/release.sh patch    # 0.1.0 -> 0.1.1
#   ./scripts/release.sh minor    # 0.1.0 -> 0.2.0
#   ./scripts/release.sh major    # 0.1.0 -> 1.0.0
#   ./scripts/release.sh 0.2.0    # explicit version

CURRENT=$(grep '^version' Cargo.toml | head -1 | sed 's/.*"\(.*\)"/\1/')
echo "Current version: ${CURRENT}"

IFS='.' read -r major minor patch <<< "$CURRENT"

case "${1:-}" in
  patch) NEW="${major}.${minor}.$((patch + 1))" ;;
  minor) NEW="${major}.$((minor + 1)).0" ;;
  major) NEW="$((major + 1)).0.0" ;;
  "") echo "Usage: $0 <patch|minor|major|VERSION>"; exit 1 ;;
  *) NEW="$1" ;;
esac

echo "New version: ${NEW}"
echo ""

# Update Cargo.toml
sed -i.bak "s/^version = \"${CURRENT}\"/version = \"${NEW}\"/" Cargo.toml
rm -f Cargo.toml.bak

# Update all npm package.json files (the npm/ packages only exist on
# branches that still ship them; skip when the directory is gone)
if [ -d npm ]; then
  for pkg_json in npm/oxvelte/package.json npm/@oxvelte/*/package.json; do
    if [ -f "$pkg_json" ]; then
      sed -i.bak "s/\"version\": \".*\"/\"version\": \"${NEW}\"/" "$pkg_json"
      rm -f "$pkg_json.bak"
    fi
  done

  # Update optionalDependencies versions
  sed -i.bak "s/\"@oxvelte\/cli-\([^\"]*\)\": \"[^\"]*\"/\"@oxvelte\/cli-\1\": \"${NEW}\"/g" npm/oxvelte/package.json
  rm -f npm/oxvelte/package.json.bak
fi

# Verify build (this also refreshes Cargo.lock with the new version)
echo "Building..."
cargo build --release

echo "Running tests..."
cargo test --lib

# The release tarball is built from the tag by the release workflow and must
# compile with --locked — so Cargo.lock must be tracked and must carry the new
# version. Fail loudly instead of tagging a broken release.
git ls-files --error-unmatch Cargo.lock > /dev/null
grep -q "^version = \"${NEW}\"$" <(awk '/^name = "oxvelte"$/,/^$/' Cargo.lock) \
  || { echo "error: Cargo.lock was not updated to ${NEW}"; exit 1; }

# Commit and tag
git add Cargo.toml Cargo.lock
if [ -d npm ]; then
  git add npm/
fi
git commit -m "release: v${NEW}"
git tag -a "v${NEW}" -m "v${NEW}"

echo ""
echo "Pushing main and v${NEW} to origin..."
git push origin main
git push origin "v${NEW}"

echo ""
echo "Release v${NEW} published."
echo "The GitHub Actions release workflow now runs on the tag: it builds the"
echo "source tarball, smoke-tests that it compiles with --locked, and creates"
echo "the GitHub release with the tarball and its SHA-256 attached."
