#!/usr/bin/env bash
# .github/scripts/generate-release-notes.sh
#
# Builds the GitHub Release title and body from environment variables
# populated by the calling workflow job.
#
# Required env vars (all injected by post-release.yml):
#   PLATFORM, LANE, TAG, VERSION, BUILD, PREV_TAG
#   ACTOR, SHA, BRANCH, RUN_NUMBER, RUN_ID, REPO, WORKFLOW_NAME
#
# Writes to $GITHUB_OUTPUT:
#   release_title
#   release_body   (multiline, EOF-delimited)
#   commit_count
#   release_url    (constructed — actual URL after release creation)

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

platform_label() {
  case "$PLATFORM" in
    android) echo "Android" ;;
    ios)     echo "iOS"     ;;
    *)       echo "$PLATFORM" ;;
  esac
}

lane_label() {
  case "$LANE" in
    beta)                  echo "Beta" ;;
    promote_to_production) echo "Production (promoted)" ;;
    production)            echo "Production" ;;
    *)                     echo "$LANE" ;;
  esac
}

release_type_emoji() {
  case "$LANE" in
    beta)                  echo "🧪" ;;
    promote_to_production) echo "🚀" ;;
    production)            echo "🚀" ;;
    *)                     echo "📦" ;;
  esac
}

# ── Distribution links ────────────────────────────────────────────────────────

# These are standard, non-repo-specific links. Replace the app IDs if needed,
# or inject them as secrets/env vars for your specific app.
#
# We embed them only when the lane makes them relevant.

dist_section() {
  local lines=""
  if [[ "$PLATFORM" == "android" ]]; then
    case "$LANE" in
      beta)
        lines+="* 🧪 **Internal Testing:** https://play.google.com/apps/internaltest/4701465847560328530"$'\n'
        lines+="* 🔗 **Play Console:** https://play.google.com/console/u/0/developers/5954935899608654188/app/4976344022028616551/tracks/internal-testing"$'\n'
        ;;
      promote_to_production|production)
        lines+="* 🛍️ **Play Store:** https://play.google.com/store/apps/details?id=com.diarchgouser"$'\n'
        ;;
    esac
  else
    case "$LANE" in
      beta)
        lines+="* 🧪 **TestFlight:** https://testflight.apple.com/join/YOUR_TESTFLIGHT_TOKEN"$'\n'
        lines+="* 🔗 **App Store Connect:** https://appstoreconnect.apple.com/apps/YOUR_APP_ID/testflight/ios"$'\n'
        ;;
      promote_to_production|production)
        lines+="* 🛍️ **App Store:** https://apps.apple.com/us/app/diarchgo/id6753003161"$'\n'
        ;;
    esac
  fi
  echo "$lines"
}

# ── Commit list ───────────────────────────────────────────────────────────────

# For a brand-new beta/production release the tag was just created at HEAD in the
# previous workflow step, so RELEASE_REF resolves to HEAD and behaviour is
# unchanged. This branch only diverges for promotions — which is the point.
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  RELEASE_REF="refs/tags/${TAG}"
else
  RELEASE_REF="HEAD"
fi
RELEASE_SHA=$(git rev-parse "$RELEASE_REF")

# Determine the range: previous tag (or root) → HEAD
RANGE="${PREV_TAG}..${RELEASE_REF}"

# Collect commits: short sha | author | subject
COMMIT_LOG=$(git log "$RANGE" --pretty=format:"%h|%an|%s" 2>/dev/null || true)
COMMIT_COUNT=0
COMMIT_LINES=""
CONTRIBUTORS_RAW=""

if [[ -n "$COMMIT_LOG" ]]; then
  while IFS='|' read -r sha author subject; do
    COMMIT_COUNT=$((COMMIT_COUNT + 1))
    COMMIT_LINES="${COMMIT_LINES}* \`${sha}\` ${subject} _(${author})_"$'\n'
    CONTRIBUTORS_RAW="${CONTRIBUTORS_RAW}${author}"$'\n'
  done <<< "$COMMIT_LOG"
fi

CONTRIBUTOR_COUNT=$(echo "$CONTRIBUTORS_RAW" | sort -u | grep -c . || true)

# Attempt files-changed count (best effort — skip if slow/unavailable)
FILES_CHANGED=""
if [[ -n "$PREV_TAG" ]] && git rev-parse "$PREV_TAG" &>/dev/null; then
  FILES_CHANGED=$(git diff --name-only "$PREV_TAG" HEAD 2>/dev/null | wc -l | tr -d ' ' || true)
fi

# ── Assemble release notes ────────────────────────────────────────────────────

PLATFORM_LABEL=$(platform_label)
LANE_LABEL=$(lane_label)
EMOJI=$(release_type_emoji)
RELEASE_DATE=$(TZ='Asia/Kolkata' date +"%Y-%m-%d %H:%M IST")
SHORT_SHA="${RELEASE_SHA:0:8}"
WORKFLOW_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"
RELEASE_TITLE="${EMOJI} ${PLATFORM_LABEL} Release v${VERSION} (${BUILD})"

RELEASE_BODY="## Release Overview

| Field | Value |
|---|---|
| **Platform** | ${PLATFORM_LABEL} |
| **Version** | \`${VERSION}\` |
| **Build** | \`${BUILD}\` |
| **Lane / Type** | ${LANE_LABEL} |
| **Git Tag** | \`${TAG}\` |
| **Branch** | \`${BRANCH}\` |
| **Commit** | \`${SHORT_SHA}\` |
| **Date** | ${RELEASE_DATE} |
| **Triggered By** | @${ACTOR} |

---

## Distribution

$(dist_section)
---

## Change Summary

| Metric | Value |
|---|---|
| **Total Commits** | ${COMMIT_COUNT} |
| **Contributors** | ${CONTRIBUTOR_COUNT} |
$([ -n "$FILES_CHANGED" ] && echo "| **Files Changed** | ${FILES_CHANGED} |")
| **Comparing** | \`${PREV_TAG}\` → \`${TAG}\` |

---

## Included Commits

${COMMIT_LINES}
---

## Build Information

| Field | Value |
|---|---|
| **Workflow** | ${WORKFLOW_NAME} |
| **Run Number** | #${RUN_NUMBER} |
| **Run URL** | [View run](${WORKFLOW_URL}) |
| **Triggered By** | @${ACTOR} |"

# ── Write outputs ─────────────────────────────────────────────────────────────

# Constructed release URL (softprops action will create the actual release).
# We build the expected URL so the Slack notifier can reference it before
# we have the real API response.
RELEASE_URL="https://github.com/${REPO}/releases/tag/${TAG}"

# Multiline output requires EOF delimiter syntax.
{
  echo "release_title=${RELEASE_TITLE}"
  echo "commit_count=${COMMIT_COUNT}"
  echo "release_url=${RELEASE_URL}"
  echo "release_body<<RELEASE_BODY_EOF"
  echo "$RELEASE_BODY"
  echo "RELEASE_BODY_EOF"
} >> "$GITHUB_OUTPUT"

echo "Release notes generated — $COMMIT_COUNT commits in range [$RANGE]"