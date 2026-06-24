#!/usr/bin/env bash
# .github/scripts/generate-release-notes.sh
#
# Builds the GitHub Release title + body.
# All values come from env vars injected by post-release.yml.
#
# Writes to $GITHUB_OUTPUT:
#   release_title
#   release_body    (multiline EOF block)
#   commit_count
#   release_url

set -euo pipefail

# ── Label helpers ─────────────────────────────────────────────────────────────

platform_label() {
  case "$PLATFORM" in
    android) echo "Android" ;;
    ios)     echo "iOS"     ;;
    *)       echo "$PLATFORM" ;;
  esac
}

lane_label() {
  case "$LANE" in
    beta)                  [[ "$PLATFORM" == "ios" ]] && echo "Beta / TestFlight" || echo "Beta / Internal Testing" ;;
    promote_to_production) echo "Production (promoted)" ;;
    production)            echo "Production" ;;
    *)                     echo "$LANE" ;;
  esac
}

release_emoji() {
  case "$LANE" in
    beta)  echo "🧪" ;;
    *)     echo "🚀" ;;
  esac
}

# ── Distribution links ────────────────────────────────────────────────────────
# Replace YOUR_APP_ID and YOUR_TESTFLIGHT_TOKEN with your real values.

dist_section() {
  if [[ "$PLATFORM" == "android" ]]; then
    case "$LANE" in
      beta)
        echo "* 🧪 **Internal Testing:** https://play.google.com/apps/internaltest/YOUR_ANDROID_APP_ID"
        ;;
      promote_to_production|production)
        echo "* 🛍️ **Play Store:** https://play.google.com/store/apps/details?id=YOUR_ANDROID_APP_ID"
        ;;
    esac
  else
    case "$LANE" in
      beta)
        echo "* 🧪 **TestFlight:** https://testflight.apple.com/join/YOUR_TESTFLIGHT_TOKEN"
        echo "* 🔗 **App Store Connect:** https://appstoreconnect.apple.com/apps/YOUR_IOS_APP_ID/testflight/ios"
        ;;
      promote_to_production|production)
        echo "* 🛍️ **App Store:** https://apps.apple.com/app/idYOUR_IOS_APP_ID"
        ;;
    esac
  fi
}

# ── Resolve the commit this release actually points to ────────────────────────
# PROMOTION FIX:
# A beta→production promotion ships the SAME build that the beta run produced.
# The version/build in source is unchanged, so the tag (e.g. android-v1.0.4-4)
# is identical and was ALREADY created during the beta run — it points at the
# original build commit. By the time a promotion runs, HEAD may be several
# commits ahead of that tag. Release notes must describe the build that actually
# ships (the tagged commit), NOT whatever happens to be at HEAD now.
#
# For a brand-new beta/production release the tag was just created at HEAD in the
# previous workflow step, so RELEASE_REF resolves to HEAD and behaviour is
# unchanged. This branch only diverges for promotions — which is the point.
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  RELEASE_REF="refs/tags/${TAG}"
else
  RELEASE_REF="HEAD"
fi
RELEASE_SHA=$(git rev-parse "$RELEASE_REF")

# ── Commit list ───────────────────────────────────────────────────────────────

RANGE="${PREV_TAG}..${RELEASE_REF}"
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

CONTRIBUTOR_COUNT=$(echo "$CONTRIBUTORS_RAW" | sort -u | grep -c . || echo "0")

FILES_CHANGED=""
if git rev-parse "$PREV_TAG" &>/dev/null 2>&1; then
  FILES_CHANGED=$(git diff --name-only "$PREV_TAG" "$RELEASE_REF" 2>/dev/null | wc -l | tr -d ' ' || true)
fi

# ── Assemble ──────────────────────────────────────────────────────────────────

PLATFORM_LABEL=$(platform_label)
LANE_LABEL=$(lane_label)
EMOJI=$(release_emoji)
RELEASE_DATE=$(TZ='Asia/Kolkata' date +"%Y-%m-%d %H:%M IST")
SHORT_SHA="${RELEASE_SHA:0:8}"
WORKFLOW_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"
RELEASE_URL="https://github.com/${REPO}/releases/tag/${TAG}"

RELEASE_TITLE="${EMOJI} ${PLATFORM_LABEL} Release v${VERSION} (${BUILD})"

# Files-changed row (only shown when we have a value)
FILES_ROW=""
if [[ -n "$FILES_CHANGED" ]]; then
  FILES_ROW="| **Files Changed** | ${FILES_CHANGED} |"
fi

# Commits section body
if [[ "$COMMIT_COUNT" -eq 0 ]]; then
  COMMITS_BODY="_No new commits since \`${PREV_TAG}\` — this is likely a promotion of an existing build._"
else
  COMMITS_BODY="$COMMIT_LINES"
fi

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
${FILES_ROW}
| **Comparing** | \`${PREV_TAG}\` → \`${TAG}\` |

---

## Included Commits

${COMMITS_BODY}

---

## Build Information

| Field | Value |
|---|---|
| **Workflow** | ${WORKFLOW_NAME} |
| **Run Number** | #${RUN_NUMBER} |
| **Run URL** | [View run](${WORKFLOW_URL}) |
| **Triggered By** | @${ACTOR} |
"

# ── Write outputs ─────────────────────────────────────────────────────────────

{
  echo "release_title=${RELEASE_TITLE}"
  echo "commit_count=${COMMIT_COUNT}"
  echo "release_url=${RELEASE_URL}"
  echo "release_body<<RELEASE_BODY_EOF"
  printf '%s\n' "$RELEASE_BODY"
  echo "RELEASE_BODY_EOF"
} >> "$GITHUB_OUTPUT"

echo "✅ Release notes generated — $COMMIT_COUNT commits in range [$RANGE]"