# Sourced by run.sh and release.sh from the repository root: fetches the DDHotKey submodule, installs
# Carthage through Homebrew if it is missing and builds the frameworks when Cartfile.resolved changed.
# Exports XCODE_XCCONFIG_FILE when the installed Xcode needs a higher deployment target.

if [[ -z "$(ls -A DDHotKey 2>/dev/null)" ]]; then
  git submodule update --init --recursive
fi

# Every Xcode release drops the oldest systems (Xcode 27 builds for macOS 12 and later), while
# MacPass and its frameworks declare 10.13. If the installed SDK refuses that, raise the target
# to the oldest one it accepts, for the frameworks and for MacPass alike.
PROJECT_TARGET="$(sed -n 's/.*MACOSX_DEPLOYMENT_TARGET = \(.*\);/\1/p' MacPass.xcodeproj/project.pbxproj | sort -V | head -1)"
SDK_TARGET="$(plutil -extract SupportedTargets.macosx.MinimumDeploymentTarget raw "$(xcrun --sdk macosx --show-sdk-path)/SDKSettings.json" 2>/dev/null || true)"
if [[ -n "${SDK_TARGET}" && "$(printf '%s\n' "${PROJECT_TARGET}" "${SDK_TARGET}" | sort -V | head -1)" != "${SDK_TARGET}" ]]; then
  echo "This Xcode builds for macOS ${SDK_TARGET} and later, raising the deployment target from ${PROJECT_TARGET}."
  mkdir -p build
  echo "MACOSX_DEPLOYMENT_TARGET = ${SDK_TARGET}" > build/deployment-target.xcconfig
  export XCODE_XCCONFIG_FILE="${PWD}/build/deployment-target.xcconfig"
fi

# The frameworks are rebuilt only when Cartfile.resolved differs from the one they were built from.
BUILT_FROM="Carthage/Build/Cartfile.resolved"
if ! cmp -s Cartfile.resolved "${BUILT_FROM}"; then
  if ! command -v carthage >/dev/null; then
    if ! command -v brew >/dev/null; then
      echo "Carthage is missing: https://github.com/Carthage/Carthage#installing-carthage" >&2
      exit 1
    fi
    brew install carthage
  fi
  carthage checkout

  # Carthage builds every shared scheme that lists macosx among its platforms, and recent Xcode
  # lists it for iOS targets too, because they can run on a Mac. The iOS schemes of KissXML,
  # KeePassKit and TransformerKit then get built for the Mac and fail. Keep the macOS schemes only.
  for SCHEME_FILE in Carthage/Checkouts/*/*.xcodeproj/xcshareddata/xcschemes/*.xcscheme; do
    SDK_NAME="$(xcodebuild -project "${SCHEME_FILE%/xcshareddata/*}" -scheme "$(basename "${SCHEME_FILE}" .xcscheme)" \
      -showBuildSettings -skipUnavailableActions SUPPORTS_MACCATALYST=NO 2>/dev/null | awk '$1 == "SDK_NAME" { print $3; exit }')"
    if [[ "${SDK_NAME}" != macosx* ]]; then
      rm "${SCHEME_FILE}"
    fi
  done

  # The macOS 27 SDK has no Darwin.Availability and Darwin.C.xlocale modules any more, which
  # TransformerKit imports. Fixed in https://github.com/MacPass/TransformerKit/pull/2; this goes
  # away when the Cartfile points to a commit that has it.
  sed -i '' -e 's|^@import Darwin\.Availability;|#import <Availability.h>|' -e 's|^@import Darwin\.C\.xlocale;|#import <xlocale.h>|' \
    Carthage/Checkouts/TransformerKit/Sources/*.[hm]

  carthage build --platform macOS --cache-builds
  cp Cartfile.resolved "${BUILT_FROM}"
fi
