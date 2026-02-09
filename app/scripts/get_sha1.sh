#!/usr/bin/env bash
# Print SHA-1 fingerprint for Android debug keystore (for Google OAuth Android client).
# Run from repo root: ./app/scripts/get_sha1.sh
# Requires Java (JAVA_HOME or keytool in PATH).

set -e
KEYSTORE="${ANDROID_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"

if ! command -v keytool &>/dev/null; then
  if [[ -n "$JAVA_HOME" && -x "$JAVA_HOME/bin/keytool" ]]; then
    KEYTOOL="$JAVA_HOME/bin/keytool"
  else
    echo "keytool not found. Set JAVA_HOME or add Java to PATH."
    echo "Example: export JAVA_HOME=\$(/usr/libexec/java_home)"
    exit 1
  fi
else
  KEYTOOL=keytool
fi

if [[ ! -f "$KEYSTORE" ]]; then
  echo "Debug keystore not found: $KEYSTORE"
  echo "Build the Android app once with 'flutter run' to create it."
  exit 1
fi

echo "Package name: com.english.english_words"
echo ""
echo "SHA-1 (debug keystore):"
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep -E "^\s*SHA1:" | sed 's/^[[:space:]]*//'
