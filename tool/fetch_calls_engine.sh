#!/usr/bin/env bash
# Fetches the sources of the calls engine (tgcalls + WebRTC, as built by
# Telegram-Android) at a pinned commit, plus the Lumina glue, into
# build/calls-engine/. GPL-3.0-or-later, see docs/DECISIONS.md D14.
#
#   tool/fetch_calls_engine.sh            # fetch (no-op when up to date)
#   CALLS_ENGINE_DIR=/tmp/x tool/fetch_calls_engine.sh
#
# Only what the voip build needs is checked out: Telegram's jni/voip tree,
# a few in-tree third_party dirs, the prebuilt static libraries for our
# ABIs, the org.webrtc Java package, and shallow copies of the submodules
# (header-only where that is enough). Submodule commits come from the
# pinned Telegram tree, so TG_COMMIT is the only pin to bump.
set -euo pipefail

TG_COMMIT=3de37c8cfb039452be7398909461da6288babf15
TG_REPO=https://github.com/DrKLO/Telegram.git
ABIS=(arm64-v8a x86_64)

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${CALLS_ENGINE_DIR:-$root/build/calls-engine}"
tg="$out/telegram"
stamp="$out/.fetched-$TG_COMMIT"

if [[ ! -f "$stamp" ]]; then
  # Keep build-*/ (object files) across re-fetches.
  rm -rf "$tg" "$out"/.fetched-*
  mkdir -p "$out"
  git init -q "$tg"
  git -C "$tg" remote add origin "$TG_REPO"
  git -C "$tg" config core.sparseCheckout true
  git -C "$tg" sparse-checkout set --no-cone \
    '/TMessagesProj/jni/voip/' \
    '/TMessagesProj/jni/openssl/' \
    '/TMessagesProj/jni/third_party/libsrtp/' \
    '/TMessagesProj/jni/third_party/pffft/' \
    '/TMessagesProj/jni/third_party/rnnoise/' \
    '/TMessagesProj/jni/third_party/usrsctplib/' \
    "${ABIS[@]/#//TMessagesProj/jni/prebuild/lib/}" \
    "${ABIS[@]/#//TMessagesProj/jni/prebuild/include/}" \
    '/TMessagesProj/src/main/java/org/webrtc/' \
    '/TMessagesProj/src/main/java/org/telegram/messenger/voip/VideoCapturerDevice.java' \
    '/LICENSE'
  git -C "$tg" fetch -q --depth 1 --filter=blob:none origin "$TG_COMMIT"
  git -C "$tg" checkout -q FETCH_HEAD

  # submodule <path under jni> [sparse patterns...]: shallow checkout at the
  # commit the Telegram tree points to.
  submodule() {
    local path="$1"
    shift
    local url commit dest
    url="$(git -C "$tg" show HEAD:.gitmodules | git config -f - "submodule.TMessagesProj/jni/$path.url")"
    commit="$(git -C "$tg" ls-tree HEAD "TMessagesProj/jni/$path" | awk '{print $3}')"
    dest="$tg/TMessagesProj/jni/$path"
    [[ -n "$url" && -n "$commit" ]] || { echo "No submodule $path in the pinned tree" >&2; exit 1; }
    echo "  $path @ ${commit:0:12}"
    rm -rf "$dest"
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
    if (($#)); then
      git -C "$dest" config core.sparseCheckout true
      git -C "$dest" sparse-checkout set --no-cone "$@"
    fi
    git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$commit"
    git -C "$dest" checkout -q FETCH_HEAD
  }

  echo "Submodules:"
  submodule tgcalls
  submodule third_party/absl
  submodule third_party/libyuv
  submodule third_party/xiph/opus
  # Headers only: the libraries themselves are Telegram's prebuilt .a files.
  submodule third_party/boringssl '/include/' '/LICENSE'
  submodule third_party/libvpx '/vpx/*.h' '/LICENSE' '/PATENTS'
  submodule third_party/wamr '/core/iwasm/include/' '/LICENSE'
  submodule third_party/openh264 '/codec/api/' '/LICENSE'
  submodule third_party/ffmpeg '/libavcodec/*.h' '/libavformat/*.h' '/libavutil/*.h' \
    '/libswresample/*.h' '/libswscale/*.h' '/COPYING.LGPLv2.1' '/LICENSE.md'
  submodule third_party/dav1d '/COPYING'
  touch "$stamp"
fi

# The Lumina side: our top-level CMake (it must sit in the jni root, since
# Telegram's voip/CMakeLists.txt uses paths relative to it), the JNI glue,
# and patches that cut the org.webrtc Java code loose from Telegram's app.
jni="$tg/TMessagesProj/jni"
cp "$root/android/calls-engine/CMakeLists.txt" "$jni/CMakeLists.txt"
rm -rf "$jni/lumina" "$jni/tgnet"
cp -r "$root/android/calls-engine/src" "$jni/lumina"
# Stand-in for the Telegram logging header a few WebRTC files include.
cp -r "$root/android/calls-engine/src/tgnet" "$jni/tgnet"

# The Java side is committed (android/calls-engine/java) so app builds need
# no fetch; it is regenerated here, so a pin bump shows up as a diff.
java="$root/android/calls-engine/java"
rm -rf "$java"
mkdir -p "$java/org/telegram/messenger/voip"
cp -r "$tg/TMessagesProj/src/main/java/org/webrtc" "$java/org/webrtc"
cp "$tg/TMessagesProj/src/main/java/org/telegram/messenger/voip/VideoCapturerDevice.java" \
  "$java/org/telegram/messenger/voip/"
# Telegram-app references in the WebRTC Java code:
# - camera sessions read the stories recorder state: never recording here.
sed -i -E 's/LivePlayer\.recording != null/false/; /import org\.telegram\.ui\.Stories\.LivePlayer;/d' \
  "$java/org/webrtc/Camera1Session.java" "$java/org/webrtc/Camera2Session.java"
# - TextureViewRenderer (Telegram's in-call view) unwraps VoIPService's
#   proxy sink; Lumina renders into a Flutter texture instead.
rm "$java/org/webrtc/TextureViewRenderer.java"
# The Telegram helpers the remaining code calls are small stand-ins in
# android/calls-engine/java-shims.

# Third-party notices shown in Settings → About → Licenses. Components
# whose vendored copy has no license file get it from upstream.
notices="$root/assets/licenses/calls_engine.txt"
mkdir -p "$(dirname "$notices")"
upstream="$out/upstream-licenses"
mkdir -p "$upstream"
fetch_license() { # name url
  [[ -s "$upstream/$1" ]] || curl -fsSL "$2" -o "$upstream/$1"
}
fetch_license webrtc 'https://raw.githubusercontent.com/webrtc-sdk/webrtc/m114_release/LICENSE'
fetch_license usrsctp 'https://raw.githubusercontent.com/sctplab/usrsctp/master/LICENSE.md'
fetch_license crc32c 'https://raw.githubusercontent.com/google/crc32c/main/LICENSE'
{
  echo "# Generated by tool/fetch_calls_engine.sh; do not edit."
  section() { # "names" files...
    local names="$1"
    shift
    echo "=== $names"
    for f in "$@"; do cat "$f"; echo; done
  }
  section "Telegram for Android (calls engine build and JNI glue)" "$tg/LICENSE"
  section "tgcalls" "$jni/tgcalls/LICENSE"
  section "WebRTC" "$upstream/webrtc"
  section "abseil-cpp" "$jni/third_party/absl/LICENSE"
  section "libyuv" "$jni/third_party/libyuv/LICENSE" "$jni/third_party/libyuv/PATENTS"
  section "Opus" "$jni/third_party/xiph/opus/COPYING"
  section "BoringSSL" "$jni/third_party/boringssl/LICENSE"
  section "libvpx" "$jni/third_party/libvpx/LICENSE" "$jni/third_party/libvpx/PATENTS"
  section "OpenH264" "$jni/third_party/openh264/LICENSE"
  section "dav1d" "$jni/third_party/dav1d/COPYING"
  section "FFmpeg (calls engine)" "$jni/third_party/ffmpeg/LICENSE.md" "$jni/third_party/ffmpeg/COPYING.LGPLv2.1"
  section "WebAssembly Micro Runtime" "$jni/third_party/wamr/LICENSE"
  section "libsrtp" "$jni/third_party/libsrtp/LICENSE"
  section "usrsctp" "$upstream/usrsctp"
  section "PFFFT" "$jni/third_party/pffft/LICENSE"
  section "RNNoise" "$jni/voip/rnnoise/COPYING"
  section "crc32c" "$upstream/crc32c"
  section "libevent" "$jni/voip/third_party/libevent/LICENSE"
  section "jni_zero" "$jni/voip/third_party/jni_zero/LICENSE"
} > "$notices"

echo "Calls engine sources ready in $out"
