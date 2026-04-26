#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/boringNotch.xcodeproj"
SCHEME="boringNotch"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataRelease"
RELEASES_DIR="$ROOT_DIR/releases"
STAGING_ROOT="$ROOT_DIR/.release_staging"

APP_BUNDLE_NAME="QuartzNotch.app"
VOLUME_NAME="QuartzNotch"
DMG_SCRIPT="$ROOT_DIR/Configuration/dmg/create_dmg.sh"

VERSION=""
BUILD_NUMBER=""
DEV_ID_APP=""
NOTARY_PROFILE=""
SPARKLE_ACCOUNT="quartznotch_clayton"
SKIP_NOTARIZE="0"
SKIP_SPARKLE="0"
OSS_MODE="0"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") --version <x.y.z> --build <n> [--dev-id-app "Developer ID Application: ..."] [--notary-profile <profile>] [--oss]

Required:
  --version         Marketing version used in output filename (ex: 0.2.0)
  --build           Build number used in output filename (ex: 200)
  --dev-id-app      Developer ID Application certificate common name (required unless --oss)

Recommended:
  --notary-profile  notarytool keychain profile name (required for notarization)

Optional:
  --oss             Open-source mode: ad-hoc signing, no notarization
  --sparkle-account Sparkle key account in macOS Keychain (default: quartznotch_clayton)
  --skip-notarize   Skip Apple notarization + stapling
  --skip-sparkle    Skip Sparkle signature generation
  -h, --help        Show this help

Example:
  $(basename "$0") \\
    --version 0.2.0 \\
    --build 200 \\
    --dev-id-app "Developer ID Application: Clayton XXXX (TEAMID)" \\
    --notary-profile QUARTZ_NOTARY

  $(basename "$0") \\
    --version 0.2.0 \\
    --build 200 \\
    --oss
USAGE
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

resolve_sparkle_sign_tool() {
  local candidates=(
    "$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    "$ROOT_DIR/.build/DerivedDataRelease/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    "$ROOT_DIR/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  local discovered
  discovered="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -n 1)"
  if [[ -n "$discovered" && -x "$discovered" ]]; then
    printf '%s\n' "$discovered"
    return 0
  fi

  return 1
}

resign_adhoc_bundle() {
  local app_path="$1"
  [[ -d "$app_path" ]] || die "App not found for ad-hoc signing: $app_path"

  # 1) Nested app bundles / XPC services first (inside app and frameworks).
  while IFS= read -r nested_bundle; do
    codesign --force --sign - "$nested_bundle"
  done < <(find "$app_path/Contents" -type d \( -name '*.app' -o -name '*.xpc' \) | sort)

  # 2) Framework binaries + dylibs.
  if [[ -d "$app_path/Contents/Frameworks" ]]; then
    while IFS= read -r fw; do
      local fw_name fw_bin
      fw_name="$(basename "$fw" .framework)"
      fw_bin="$fw/Versions/A/$fw_name"
      if [[ -f "$fw_bin" ]]; then
        codesign --force --sign - "$fw_bin"
      fi
    done < <(find "$app_path/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' | sort)

    # Sign loose dylibs if any.
    while IFS= read -r dylib; do
      codesign --force --sign - "$dylib"
    done < <(find "$app_path/Contents/Frameworks" -type f -name '*.dylib' | sort)

    # Re-sign each framework bundle AFTER nested code has been updated.
    while IFS= read -r fw; do
      if [[ "$(basename "$fw")" == "MediaRemoteAdapter.framework" ]]; then
        # Non-standard framework layout; binary was already signed above.
        continue
      fi
      codesign --force --sign - "$fw"
    done < <(find "$app_path/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' | sort)
  fi

  # 3) Main executable.
  local main_exec
  main_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -n "$main_exec" && -f "$app_path/Contents/MacOS/$main_exec" ]]; then
    codesign --force --sign - "$app_path/Contents/MacOS/$main_exec"
  fi

  # 4) Top-level app signature (no --deep because MediaRemoteAdapter.framework is non-standard).
  codesign --force --sign - "$app_path"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --dev-id-app)
      DEV_ID_APP="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --sparkle-account)
      SPARKLE_ACCOUNT="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE="1"
      shift
      ;;
    --skip-sparkle)
      SKIP_SPARKLE="1"
      shift
      ;;
    --oss)
      OSS_MODE="1"
      SKIP_NOTARIZE="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$VERSION" ]] || die "--version is required"
[[ -n "$BUILD_NUMBER" ]] || die "--build is required"
if [[ "$OSS_MODE" != "1" ]]; then
  [[ -n "$DEV_ID_APP" ]] || die "--dev-id-app is required unless --oss is set"
fi
if [[ "$SKIP_NOTARIZE" != "1" && "$OSS_MODE" != "1" ]]; then
  [[ -n "$NOTARY_PROFILE" ]] || die "--notary-profile is required unless --skip-notarize is set"
fi

require_cmd xcodebuild
require_cmd codesign
require_cmd xattr
require_cmd ditto
require_cmd stat
[[ -f "$DMG_SCRIPT" ]] || die "DMG script not found: $DMG_SCRIPT"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  require_cmd xcrun
fi

mkdir -p "$RELEASES_DIR" "$STAGING_ROOT"

OUTPUT_BASENAME="QuartzNotch-${VERSION}(${BUILD_NUMBER})"
OUTPUT_DMG="$RELEASES_DIR/${OUTPUT_BASENAME}.dmg"
STAGING_DIR="$STAGING_ROOT/${OUTPUT_BASENAME}"
STAGED_APP="$STAGING_DIR/$APP_BUNDLE_NAME"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "[1/8] Building app ($SCHEME, $CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/dev/null

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_BUNDLE_NAME"
[[ -d "$BUILT_APP" ]] || die "Built app not found at: $BUILT_APP"

echo "[2/8] Preparing staging app..."
ditto "$BUILT_APP" "$STAGED_APP"
xattr -cr "$STAGED_APP"

echo "[3/8] Signing app with Developer ID..."
if [[ "$OSS_MODE" == "1" ]]; then
  echo "      OSS mode: ad-hoc signing full bundle (frameworks/xpc/app)"
  resign_adhoc_bundle "$STAGED_APP"
  echo "      OSS mode: skipping strict bundle verification (non-standard framework layout)"
else
  codesign --force --deep --options runtime --timestamp --sign "$DEV_ID_APP" "$STAGED_APP"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

  # Gatekeeper preflight (should be accepted after proper signing)
  spctl --assess --type execute --verbose=4 "$STAGED_APP" || true
fi

echo "[4/8] Creating DMG..."
rm -f "$OUTPUT_DMG"
bash "$DMG_SCRIPT" "$STAGED_APP" "$OUTPUT_DMG" "$VOLUME_NAME"

if [[ ! -f "$OUTPUT_DMG" ]]; then
  die "DMG creation failed: $OUTPUT_DMG"
fi

echo "[5/8] Signing DMG..."
if [[ "$OSS_MODE" == "1" ]]; then
  echo "      OSS mode: skipping DMG codesign"
else
  codesign --force --timestamp --sign "$DEV_ID_APP" "$OUTPUT_DMG"
  codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "[6/8] Notarizing DMG with profile '$NOTARY_PROFILE'..."
  xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "[7/8] Stapling notarization ticket..."
  xcrun stapler staple -v "$OUTPUT_DMG"
  xcrun stapler validate -v "$OUTPUT_DMG"
else
  echo "[6/8] Notarization skipped (--skip-notarize)."
  echo "[7/8] Stapling skipped (--skip-notarize)."
fi

if [[ "$SKIP_SPARKLE" != "1" ]]; then
  SPARKLE_SIGN_TOOL="$(resolve_sparkle_sign_tool)" || die "Sparkle sign_update tool not found. Rebuild the app once in Xcode or rerun the release build to restore Sparkle artifacts."
  echo "[8/8] Generating Sparkle signature..."
  SPARKLE_SIGNATURE="$($SPARKLE_SIGN_TOOL --account "$SPARKLE_ACCOUNT" -p "$OUTPUT_DMG")"
  DMG_LENGTH="$(stat -f%z "$OUTPUT_DMG")"

  cat <<SNIPPET

Sparkle enclosure snippet (paste into appcast.xml):
<enclosure url="https://github.com/Clayton630/QuartzNotch/releases/download/v${VERSION}/$(basename "$OUTPUT_DMG")" length="${DMG_LENGTH}" type="application/octet-stream" sparkle:edSignature="${SPARKLE_SIGNATURE}"/>

SNIPPET
else
  echo "[8/8] Sparkle signature skipped (--skip-sparkle)."
fi

echo "Done. DMG ready: $OUTPUT_DMG"
