#!/bin/bash
# Builds MacPass with its dependencies and starts it, without opening Xcode:
#
#   scripts/run.sh
#
# The first run fetches the DDHotKey submodule, installs Carthage through Homebrew if it is
# missing and builds the frameworks; later runs only rebuild MacPass. The result is a Debug
# build in build/Build/Products/Debug/MacPass.app, signed ad hoc.
set -euo pipefail

MY_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${MY_FOLDER}/.."

DERIVED_DATA="${PWD}/build"
APP="${DERIVED_DATA}/Build/Products/Debug/MacPass.app"
BUILD_LOG="${DERIVED_DATA}/xcodebuild.log"
mkdir -p "${DERIVED_DATA}"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is missing: install it from the App Store and open it once." >&2
  exit 1
fi

source "${MY_FOLDER}/build-dependencies.sh"

# The project signs with the maintainer's team and an entitlements file that needs a provisioning
# profile. Sign ad hoc and without entitlements instead. The hardened runtime has to be off then:
# without the disable-library-validation entitlement it refuses to load the embedded frameworks.
echo "Building MacPass, log in ${BUILD_LOG}"
if ! xcodebuild build -project MacPass.xcodeproj -scheme MacPass -configuration Debug -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= ENABLE_HARDENED_RUNTIME=NO \
    > "${BUILD_LOG}" 2>&1; then
  grep -E "error:|BUILD FAILED" "${BUILD_LOG}" | sort -u >&2
  exit 1
fi

# A running copy of this build is asked to quit, so that it can still offer to save changes.
BINARY="${APP}/Contents/MacOS/MacPass"
if pgrep -f "${BINARY}" >/dev/null; then
  osascript -e "tell application \"${APP}\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -f "${BINARY}" >/dev/null || break
    sleep 0.2
  done
  if pgrep -f "${BINARY}" >/dev/null; then
    echo "MacPass is still running, maybe with unsaved changes. Quit it and start this script again." >&2
    exit 1
  fi
fi

open -n "${APP}"
