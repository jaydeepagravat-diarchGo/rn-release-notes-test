#!/usr/bin/env bash
# .github/scripts/send-slack-notification.sh

set -euo pipefail

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "SLACK_WEBHOOK_URL not set — skipping Slack notification."
  exit 0
fi

# ── Labels ────────────────────────────────────────────────────────────────────

platform_label() {
  case "$PLATFORM" in
    android) echo "Android 🤖" ;;
    ios)     echo "iOS 🍎"     ;;
    *)       echo "$PLATFORM"  ;;
  esac
}

release_type_label() {
  case "$LANE" in
    beta)
      [[ "$PLATFORM" == "ios" ]] && echo "TestFlight 🧪" || echo "Internal Testing 🧪"
      ;;
    promote_to_production) echo "Production 🚀 (promoted)" ;;
    production)            echo "Production 🚀"            ;;
    *)                     echo "$LANE" ;;
  esac
}

install_link() {
  if [[ "$PLATFORM" == "android" ]]; then
    case "$LANE" in
      beta) echo "${ANDROID_INTERNAL_TESTING_URL}" ;;
      *)    echo "${ANDROID_PLAY_STORE_URL}" ;;
    esac
  else
    case "$LANE" in
      beta) echo "${IOS_TESTFLIGHT_URL}" ;;
      *)    echo "${IOS_APP_STORE_URL}" ;;
    esac
  fi
}

# ── Values ────────────────────────────────────────────────────────────────────

PLATFORM_LABEL=$(platform_label)
RELEASE_TYPE=$(release_type_label)
INSTALL_URL=$(install_link)
WORKFLOW_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"
RELEASE_DATE=$(TZ='Asia/Kolkata' date +"%Y-%m-%d %H:%M IST")

# ── Debug ─────────────────────────────────────────────────────────────────────

echo "=== DEBUG VALUES ==="
echo "PLATFORM_LABEL : '$PLATFORM_LABEL'"
echo "RELEASE_TYPE   : '$RELEASE_TYPE'"
echo "INSTALL_URL    : '$INSTALL_URL'"
echo "WORKFLOW_URL   : '$WORKFLOW_URL'"
echo "RELEASE_DATE   : '$RELEASE_DATE'"
echo "VERSION        : '$VERSION'"
echo "BUILD          : '$BUILD'"
echo "TAG            : '$TAG'"
echo "COMMIT_COUNT   : '$COMMIT_COUNT'"
echo "ACTOR          : '$ACTOR'"
echo "RELEASE_URL    : '$RELEASE_URL'"
echo "===================="

# ── Payload ───────────────────────────────────────────────────────────────────

PAYLOAD=$(cat <<SLACK_EOF
{
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🚀 Release Successful — ${PLATFORM_LABEL}",
        "emoji": true
      }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Platform:*\n${PLATFORM_LABEL}" },
        { "type": "mrkdwn", "text": "*Release Type:*\n${RELEASE_TYPE}" },
        { "type": "mrkdwn", "text": "*Version:*\n\`${VERSION}\`" },
        { "type": "mrkdwn", "text": "*Build:*\n\`${BUILD}\`" },
        { "type": "mrkdwn", "text": "*Tag:*\n\`${TAG}\`" },
        { "type": "mrkdwn", "text": "*Commits Included:*\n${COMMIT_COUNT}" },
        { "type": "mrkdwn", "text": "*Triggered By:*\n@${ACTOR}" },
        { "type": "mrkdwn", "text": "*Date:*\n${RELEASE_DATE}" }
      ]
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "📋 GitHub Release" },
          "url": "${RELEASE_URL}"
        },
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "📲 Install / Test" },
          "url": "${INSTALL_URL}"
        },
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "⚙️ Workflow Run" },
          "url": "${WORKFLOW_URL}"
        }
      ]
    },
    { "type": "divider" }
  ]
}
SLACK_EOF
)

# ── Validate JSON ─────────────────────────────────────────────────────────────

echo "=== DEBUG PAYLOAD ==="
echo "$PAYLOAD"
echo "===================="

echo "=== JSON VALIDATION ==="
echo "$PAYLOAD" | python3 -m json.tool && echo "✅ JSON is valid" || echo "❌ JSON is invalid"
echo "===================="

# ── Send ──────────────────────────────────────────────────────────────────────

HTTP_STATUS=$(curl -s -o /tmp/slack-response.txt -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$SLACK_WEBHOOK_URL")

BODY=$(cat /tmp/slack-response.txt)

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "✅ Slack notification sent."
else
  echo "⚠️  Slack notification failed. HTTP $HTTP_STATUS — $BODY"
fi