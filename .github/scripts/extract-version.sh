#!/usr/bin/env bash
# .github/scripts/extract-version.sh
#
# Reads version info from project source files.
# No manual input required.
#
# Android → android/app/build.gradle
# iOS     → ios/<AppName>/Info.plist  (auto-discovered)
#
# Outputs (via $GITHUB_OUTPUT):
#   version   e.g. "1.2.23"
#   build     e.g. "70"
#   tag       e.g. "android-v1.2.23-70"

set -euo pipefail

PLATFORM="${1:-}"

if [[ -z "$PLATFORM" ]]; then
  echo "ERROR: platform argument required (android|ios)" >&2
  exit 1
fi

# ── Android ──────────────────────────────────────────────────────────────────
extract_android() {
  local gradle_file="android/app/build.gradle"

  if [[ ! -f "$gradle_file" ]]; then
    echo "ERROR: $gradle_file not found." >&2
    exit 1
  fi

  # Supports both Groovy DSL:  versionName "1.2.3"
  #          and Kotlin DSL:   versionName = "1.2.3"
  VERSION=$(grep -E '^\s*versionName\s*[=]?\s*"' "$gradle_file" \
    | head -1 \
    | sed -E 's/.*versionName\s*=?\s*"([^"]+)".*/\1/')

  BUILD=$(grep -E '^\s*versionCode\s*[=]?\s*[0-9]+' "$gradle_file" \
    | head -1 \
    | sed -E 's/.*versionCode\s*=?\s*([0-9]+).*/\1/')

  if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    echo "ERROR: Could not parse versionName/versionCode from $gradle_file" >&2
    echo "       Make sure the file contains lines like:" >&2
    echo "         versionName \"1.2.3\"" >&2
    echo "         versionCode 70" >&2
    exit 1
  fi

  echo "✅ Android version — versionName=$VERSION  versionCode=$BUILD"

  TAG="android-v${VERSION}-${BUILD}"
  {
    echo "version=$VERSION"
    echo "build=$BUILD"
    echo "tag=$TAG"
  } >> "$GITHUB_OUTPUT"
}

# ── iOS ───────────────────────────────────────────────────────────────────────
extract_ios() {
  # Auto-discover Info.plist — skip Pods and test targets
  local plist
  plist=$(find ios -maxdepth 3 -name "Info.plist" \
    ! -path "*/Pods/*" \
    ! -path "*/test*" \
    ! -path "*/Test*" \
    | head -1)

  if [[ -z "$plist" ]]; then
    echo "ERROR: Info.plist not found under ios/" >&2
    exit 1
  fi

  echo "Reading from: $plist"

  # 1. Read raw values from plist
  if command -v /usr/libexec/PlistBuddy &>/dev/null; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")
    BUILD=$(/usr/libexec/PlistBuddy   -c "Print CFBundleVersion"            "$plist")
  else
    VERSION=$(python3 - "$plist" CFBundleShortVersionString <<'PYEOF'
import sys, plistlib
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
print(data.get(sys.argv[2], ""))
PYEOF
)
    BUILD=$(python3 - "$plist" CFBundleVersion <<'PYEOF'
import sys, plistlib
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
print(data.get(sys.argv[2], ""))
PYEOF
)
  fi

  # 2. Resolve Xcode placeholders if they reference build settings variables
  local pbxproj
  pbxproj=$(find ios -name "project.pbxproj" | head -1)

  if [[ "$VERSION" == "\$(MARKETING_VERSION)" ]]; then
    if [[ -f "$pbxproj" ]]; then
      VERSION=$(grep -E '^\s*MARKETING_VERSION\s*=' "$pbxproj" | head -1 | sed -E 's/.*=\s*([^;]+);.*/\1/' | xargs)
      echo "ℹ️ Resolved $(MARKETING_VERSION) from project.pbxproj -> $VERSION"
    else
      echo "ERROR: Version uses $(MARKETING_VERSION) but project.pbxproj not found." >&2
      exit 1
    fi
  fi

  if [[ "$BUILD" == "\$(CURRENT_PROJECT_VERSION)" ]]; then
    if [[ -f "$pbxproj" ]]; then
      BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION\s*=' "$pbxproj" | head -1 | sed -E 's/.*=\s*([^;]+);.*/\1/' | xargs)
      echo "ℹ️ Resolved $(CURRENT_PROJECT_VERSION) from project.pbxproj -> $BUILD"
    else
      echo "ERROR: Build uses $(CURRENT_PROJECT_VERSION) but project.pbxproj not found." >&2
      exit 1
    fi
  fi

  if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    echo "ERROR: Could not read CFBundleShortVersionString/CFBundleVersion from $plist" >&2
    exit 1
  fi

  echo "✅ iOS version — CFBundleShortVersionString=$VERSION  CFBundleVersion=$BUILD"

  TAG="ios-v${VERSION}-${BUILD}"
  {
    echo "version=$VERSION"
    echo "build=$BUILD"
    echo "tag=$TAG"
  } >> "$GITHUB_OUTPUT"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$PLATFORM" in
  android) extract_android ;;
  ios)     extract_ios     ;;
  *)
    echo "ERROR: Unknown platform '$PLATFORM'. Use 'android' or 'ios'." >&2
    exit 1
    ;;
esac
