#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_HOME:?Configura ANDROID_HOME}"
: "${ANDROID_NDK_HOME:?Configura ANDROID_NDK_HOME}"
test -f android/keystore.properties || { echo 'Falta la configuración privada de firma Controles'; exit 1; }
rustup toolchain install 1.99.0 --profile minimal
rustup target add --toolchain 1.99.0 aarch64-linux-android
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"
(cd src/OpenGMK && cargo +1.99.0 ndk -t arm64-v8a --platform 29 build -p gm8emulator --lib --release --locked)
(cd android && gradle --no-daemon :app:testReleaseUnitTest :app:assembleRelease -Pandroid.onlyEnableUnitTestForTheTestedBuildType=false -PcontrolsBuild=true -PtargetAbi=arm64-v8a)
