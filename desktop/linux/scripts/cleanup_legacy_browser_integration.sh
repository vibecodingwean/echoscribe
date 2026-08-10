#!/usr/bin/env bash
set -euo pipefail

host_manifest="de.echoscribe.nativehost.json"
legacy_manifests=(
  "$HOME/.config/google-chrome/NativeMessagingHosts/$host_manifest"
  "$HOME/.config/chromium/NativeMessagingHosts/$host_manifest"
  "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/$host_manifest"
  "$HOME/.config/microsoft-edge/NativeMessagingHosts/$host_manifest"
  "$HOME/.mozilla/native-messaging-hosts/$host_manifest"
  "$HOME/.librewolf/native-messaging-hosts/$host_manifest"
)

removed=0
for manifest in "${legacy_manifests[@]}"; do
  if [ -e "$manifest" ] || [ -L "$manifest" ]; then
    rm -f -- "$manifest"
    removed=$((removed + 1))
  fi
done

printf 'Removed %d obsolete EchoScribe browser Native Messaging manifest(s).\n' "$removed"
