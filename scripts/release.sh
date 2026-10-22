#!/bin/bash
# Builds MacPass from main, signs it with a Developer ID, has Apple notarize it and publishes the DMG
# as a release of the fork on GitHub, with the Sparkle appcast on the fork's GitHub Pages:
#
#   scripts/release.sh [--no-publish] [version]
#
# The version defaults to FORK_BASE with the next fourth number, for example 0.8.3.1, and becomes
# the tag. FORK_BASE is one above the upstream release the fork builds on: raise it after merging a
# newer upstream release. Sparkle compares the build number, so the scheme can change any time. With --no-publish the script stops at the notarized DMG
# in build/release and tags nothing.
#
# This follows the release workflow of https://github.com/orestesgaolin/MacPass
# (.github/workflows/release.yml), run on this Mac instead of GitHub Actions.
#
# Needs once on the Mac that releases:
# - the certificate and key of SIGNING_IDENTITY in the login keychain;
# - notary credentials: an App Store Connect API key of that team in SECRETS, as notary.p8 and
#   notary.env with NOTARY_KEY_ID and NOTARY_ISSUER; or, without those files, a keychain profile
#   stored with an app-specific password of an Apple ID in the team:
#     xcrun notarytool store-credentials notarytool-password --apple-id <Apple ID> --team-id 38LK44494Q
# - the private Sparkle key for SUPublicEDKey in MacPass-Info.plist, as SPARKLE_KEY_FILE, the
#   way Sparkle's generate_keys -x exports it. It is read from the file, never from the keychain,
#   so that no keychain prompt stops the release.
set -euo pipefail

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: EMOJI - FZCO (38LK44494Q)}"
SECRETS="${SECRETS:-${HOME}/cloud/code/infra/secrets/macpass}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-password}"
SPARKLE_KEY_FILE="${SPARKLE_KEY_FILE:-${SECRETS}/sparkle.key}"
FORK_BASE="${FORK_BASE:-0.8.3}"
REMOTE="${REMOTE:-fork}"
UPSTREAM="${UPSTREAM:-origin/master}"

MY_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${MY_FOLDER}/.."

fail() {
  echo "$*" >&2
  exit 1
}

PUBLISH=1
VERSION=""
for ARG in "$@"; do
  case "${ARG}" in
    --no-publish) PUBLISH=0 ;;
    -*) fail "Usage: scripts/release.sh [--no-publish] [version]" ;;
    *) VERSION="${ARG}" ;;
  esac
done

REPO="$(git remote get-url "${REMOTE}" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"

# Everything that can stop the release is checked before the build.
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || fail "Releases are made from main."
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "Commit or stash the changes first."
git fetch --quiet --tags "${REMOTE}" main
if [[ "${PUBLISH}" == 1 && "$(git rev-parse HEAD)" != "$(git rev-parse "${REMOTE}/main")" ]]; then
  fail "main differs from ${REMOTE}/main: push or pull first."
fi

if [[ -z "${VERSION}" ]]; then
  LAST_NUMBER="$(git tag -l "${FORK_BASE}.*" | sed "s/^${FORK_BASE}\.//" | grep -E '^[0-9]+$' | sort -n | tail -1 || true)"
  VERSION="${FORK_BASE}.$(( ${LAST_NUMBER:-0} + 1 ))"
fi
if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  fail "The tag ${VERSION} exists already."
fi

security find-identity -v -p codesigning | grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null \
  || fail "The keychain has no valid identity \"${SIGNING_IDENTITY}\"."
if [[ -f "${SECRETS}/notary.env" ]]; then
  source "${SECRETS}/notary.env"
  NOTARY_AUTH=(--key "${SECRETS}/notary.p8" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}")
else
  NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE}")
fi
xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 \
  || fail "The notary credentials do not work, see the top of $0."
if [[ "${PUBLISH}" == 1 ]]; then
  gh auth status >/dev/null 2>&1 || fail "Log in to GitHub first: gh auth login"
fi

# Sparkle's tools come from the release archive of the Sparkle version in Cartfile.resolved.
SPARKLE_VERSION="$(sed -n 's/^binary ".*Sparkle.json" "\(.*\)"$/\1/p' Cartfile.resolved)"
SPARKLE_TOOLS="${PWD}/build/sparkle-${SPARKLE_VERSION}/bin"
if [[ ! -x "${SPARKLE_TOOLS}/sign_update" ]]; then
  mkdir -p "build/sparkle-${SPARKLE_VERSION}"
  curl -sSLf "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJf - -C "build/sparkle-${SPARKLE_VERSION}" ./bin
fi
PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw MacPass/MacPass-Info.plist)"
[[ -r "${SPARKLE_KEY_FILE}" ]] || fail "The Sparkle key ${SPARKLE_KEY_FILE} is missing."
# The file holds the base64 seed of the Ed25519 key (32 bytes, or 96 in older exports).
KEY_PUBLIC="$(xcrun swift -e 'import CryptoKit; import Foundation
let seed = Data(base64Encoded: readLine() ?? "")?.prefix(32) ?? Data()
print((try? Curve25519.Signing.PrivateKey(rawRepresentation: seed))?.publicKey.rawRepresentation.base64EncodedString() ?? "")' \
  < "${SPARKLE_KEY_FILE}")"
[[ "${KEY_PUBLIC}" == "${PUBLIC_KEY}" ]] || fail "${SPARKLE_KEY_FILE} is not the key of SUPublicEDKey."

source "${MY_FOLDER}/build-dependencies.sh"

DERIVED_DATA="${PWD}/build/release"
APP="${DERIVED_DATA}/Build/Products/Release/MacPass.app"
BUILD_LOG="${DERIVED_DATA}/xcodebuild.log"
DMG="${DERIVED_DATA}/MacPass-${VERSION}.dmg"
rm -rf "${DERIVED_DATA}"
mkdir -p "${DERIVED_DATA}"

# Built unsigned and signed below, because Xcode would sign with the maintainer's team and the
# entitlements file that needs a provisioning profile. The build phase sets CFBundleVersion to the
# number of commits on main followed by a 0, which Sparkle compares.
echo "Building MacPass ${VERSION}, log in ${BUILD_LOG}"
if ! xcodebuild build -project MacPass.xcodeproj -scheme MacPass -configuration Release -derivedDataPath "${DERIVED_DATA}" \
    CURRENT_PROJECT_VERSION="${VERSION}" CODE_SIGNING_ALLOWED=NO > "${BUILD_LOG}" 2>&1; then
  grep -E "error:|BUILD FAILED" "${BUILD_LOG}" | sort -u >&2
  exit 1
fi
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "${APP}/Contents/Info.plist")"
MINIMUM_SYSTEM="$(plutil -extract LSMinimumSystemVersion raw "${APP}/Contents/Info.plist")"

# Apple's timestamp server fails now and then, so codesign gets three tries.
codesign_timestamped() {
  for _ in 1 2 3; do
    codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "$@" && return 0
    sleep 10
  done
  return 1
}
sign() {
  codesign_timestamped --options runtime "$@"
}

# Inside out: Sparkle's helpers in the order its documentation gives, then the frameworks, then the app.
# The Developer ID entitlements lack keychain-access-groups, which needs a provisioning profile.
echo "Signing with ${SIGNING_IDENTITY}"
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework"
sign "${SPARKLE}/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "${SPARKLE}/Versions/B/XPCServices/Downloader.xpc"
sign "${SPARKLE}/Versions/B/Autoupdate"
sign "${SPARKLE}/Versions/B/Updater.app"
for FRAMEWORK in "${APP}"/Contents/Frameworks/*.framework; do
  sign "${FRAMEWORK}"
done
sign --entitlements MacPass/MacPass-Developer-ID.entitlements "${APP}"
codesign --verify --deep --strict "${APP}"

notarize() {
  echo "Notarizing $(basename "$1"), this takes a few minutes"
  local RESULT ID
  RESULT="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --output-format json)" || true
  if [[ "$(plutil -extract status raw - <<< "${RESULT}" 2>/dev/null)" != Accepted ]]; then
    echo "${RESULT}" >&2
    ID="$(plutil -extract id raw - <<< "${RESULT}" 2>/dev/null)" || true
    if [[ -n "${ID}" ]]; then
      xcrun notarytool log "${ID}" "${NOTARY_AUTH[@]}" >&2 || true
    fi
    fail "Apple did not notarize $1."
  fi
}

# The app is notarized on its own as well, so that it carries the ticket after leaving the DMG.
ditto -c -k --keepParent "${APP}" "${DERIVED_DATA}/MacPass.zip"
notarize "${DERIVED_DATA}/MacPass.zip"
xcrun stapler staple -q "${APP}"

mkdir "${DERIVED_DATA}/dmg"
ditto "${APP}" "${DERIVED_DATA}/dmg/MacPass.app"
ln -s /Applications "${DERIVED_DATA}/dmg/Applications"
hdiutil create -quiet -volname "MacPass ${VERSION}" -srcfolder "${DERIVED_DATA}/dmg" -fs HFS+ -format UDZO "${DMG}"
codesign_timestamped "${DMG}"
notarize "${DMG}"
xcrun stapler staple -q "${DMG}"
spctl --assess --type execute "${APP}"
spctl --assess --type open --context context:primary-signature "${DMG}"
echo "Built ${DMG}"

# Release notes: the commits since the previous release of the fork, or since upstream for the first one.
PREVIOUS_TAG="$(git tag -l '*.*.*.*' --merged HEAD --sort=-v:refname | head -1)"
if [[ -n "${PREVIOUS_TAG}" ]]; then
  SINCE="${PREVIOUS_TAG}"
  SINCE_NAME="${PREVIOUS_TAG}"
else
  SINCE="$(git merge-base HEAD "${UPSTREAM}")"
  SINCE_NAME="upstream MacPass at ${SINCE:0:8}"
fi
CHANGES="$(git log --no-merges --reverse --format=%s "${SINCE}..HEAD")"
SIGNER="${SIGNING_IDENTITY#Developer ID Application: }"
{
  echo "Changes since ${SINCE_NAME}:"
  echo
  sed 's/^/- /' <<< "${CHANGES}"
  echo
  echo "Signed with the Developer ID of ${SIGNER} and notarized by Apple. Needs macOS ${MINIMUM_SYSTEM} or later."
} > "${DERIVED_DATA}/notes.md"

ED_SIGNATURE="$("${SPARKLE_TOOLS}/sign_update" --ed-key-file "${SPARKLE_KEY_FILE}" "${DMG}")"
ESCAPED_CHANGES="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|<li>&</li>|' <<< "${CHANGES}" | tr -d '\n')"
cat > "${DERIVED_DATA}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MacPass (${REPO})</title>
    <link>https://github.com/${REPO}</link>
    <item>
      <title>MacPass ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/${REPO}/releases</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<p>Changes since ${SINCE_NAME}:</p><ul>${ESCAPED_CHANGES}</ul>]]></description>
      <enclosure url="https://github.com/${REPO}/releases/download/${VERSION}/MacPass-${VERSION}.dmg" type="application/octet-stream" ${ED_SIGNATURE}/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "${DERIVED_DATA}/appcast.xml"

if [[ "${PUBLISH}" == 0 ]]; then
  echo "Not published: release notes and appcast are in ${DERIVED_DATA}."
  exit 0
fi

git tag -a "${VERSION}" -m "MacPass ${VERSION}"
git push --quiet "${REMOTE}" "refs/tags/${VERSION}"
gh release create "${VERSION}" "${DMG}" --repo "${REPO}" --verify-tag --title "MacPass ${VERSION} (${BUILD_NUMBER})" \
  --notes-file "${DERIVED_DATA}/notes.md"

# The appcast replaces the previous one on gh-pages, which holds nothing else; Sparkle only needs the
# newest release.
PARENT=()
if git fetch --quiet "${REMOTE}" gh-pages 2>/dev/null; then
  PARENT=(-p "$(git rev-parse FETCH_HEAD)")
fi
BLOB="$(git hash-object -w "${DERIVED_DATA}/appcast.xml")"
TREE="$(printf '100644 blob %s\tappcast.xml\n' "${BLOB}" | git mktree)"
COMMIT="$(git commit-tree "${TREE}" ${PARENT[@]+"${PARENT[@]}"} -m "Appcast for MacPass ${VERSION}")"
git push --quiet "${REMOTE}" "${COMMIT}:refs/heads/gh-pages"
# GitHub may turn Pages on by itself for a new gh-pages branch, and then the POST gets HTTP 409.
if ! gh api "repos/${REPO}/pages" >/dev/null 2>&1; then
  gh api -X POST "repos/${REPO}/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null 2>&1 \
    || gh api "repos/${REPO}/pages" >/dev/null || fail "Could not turn on GitHub Pages for gh-pages."
fi
echo "Published https://github.com/${REPO}/releases/tag/${VERSION}"
echo "Sparkle reads $(plutil -extract SUFeedURL raw MacPass/MacPass-Info.plist)"
