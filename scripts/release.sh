#!/usr/bin/env bash
# release.sh — publish the latest .dmg as a GitHub Release and protect `main`.
#
# Requires the GitHub CLI authenticated as the repo owner:
#   brew install gh
#   gh auth login          # choose GitHub.com, HTTPS, authenticate in browser
#
# Then:
#   ./scripts/release.sh 0.1.0
#
# This is intentionally a script you run yourself: it performs authenticated,
# outward-facing GitHub actions (release upload + branch protection).

set -euo pipefail

VERSION="${1:-0.1.0}"
REPO="tictacguy/embershard"
DMG="app/dist/Embershard-${VERSION}-mac.dmg"

command -v gh >/dev/null || { echo "gh not found: brew install gh && gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated: run 'gh auth login'"; exit 1; }

# 1. Build the .dmg if it isn't there yet.
if [ ! -f "$DMG" ]; then
    echo "▸ Building $DMG …"
    (cd app && ./make_dmg.sh)
fi
[ -f "$DMG" ] || { echo "ERROR: $DMG not found"; exit 1; }

# 2. Create (or update) the GitHub Release and attach the .dmg.
echo "▸ Publishing release v$VERSION …"
if gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" -R "$REPO" --clobber
else
    gh release create "v$VERSION" "$DMG" -R "$REPO" \
        --title "Embershard $VERSION" \
        --notes "Native macOS LLM inference engine + chat app (Apple Silicon, macOS 14+).

Download \`Embershard-${VERSION}-mac.dmg\`, drag Embershard to Applications, then
right-click → Open on first launch (ad-hoc signed)."
fi

# 3. Protect main: require a pull request before merging (no direct pushes).
echo "▸ Protecting branch main (require PRs) …"
gh api -X PUT "repos/$REPO/branches/main/protection" \
    -H "Accept: application/vnd.github+json" --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "✓ Done. Latest release: https://github.com/$REPO/releases/latest"
