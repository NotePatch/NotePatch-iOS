#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

if [[ "${CONFIGURATION:-Debug}" != "Release" && "${NOTE_PATCH_INCREMENT_BUILD_NUMBER:-0}" != "1" ]]; then
    exit 0
fi

marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
if [[ ! "${marketing_version}" =~ ^([0-9]+)\.([0-9]{2})$ ]]; then
    echo "Expected a two-decimal marketing version, found: ${marketing_version}" >&2
    exit 1
fi

major_version="${BASH_REMATCH[1]}"
minor_version=$((10#${BASH_REMATCH[2]} + 1))
if (( minor_version == 100 )); then
    major_version=$((major_version + 1))
    minor_version=0
fi
next_marketing_version="$(printf '%d.%02d' "${major_version}" "${minor_version}")"

build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
if [[ ! "${build_number}" =~ ^[0-9]+$ ]]; then
    echo "Expected an integer build number, found: ${build_number}" >&2
    exit 1
fi
next_build_number=$((10#${build_number} + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${next_marketing_version}" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${next_build_number}" Info.plist
