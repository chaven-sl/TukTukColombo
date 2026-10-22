# Android setup (debug builds)

Prototype v0.03A. Produces a **debug** APK for owner playtesting. No release
signing, no Play Store configuration, no store keystore.

## Toolchain (macOS, all from official sources)

| Item | Version | Where |
|---|---|---|
| Godot editor | 4.7.2 stable (standard, not .NET) | `/Applications/Godot.app` |
| Export templates | 4.7.2.stable (checksum-verified) | `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` |
| JDK | OpenJDK 17 (`brew install openjdk@17`) | `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` |
| Android SDK | command-line tools only (no Android Studio) | `~/Library/Android/sdk` |
| SDK packages | `platform-tools`, `build-tools;35.0.1`, `platforms;android-35`, `cmdline-tools;latest`, `cmake;3.10.2.4988404`, `ndk;28.1.13356709` | via `sdkmanager` |

Editor Settings → Export → Android: *Java SDK Path* = the JDK above, *Android
SDK Path* = `~/Library/Android/sdk`, *Debug Keystore* = Godot's generated
debug keystore (`androiddebugkey`, standard debug password). These are
per-machine editor settings — nothing machine-specific is stored in the
project. The tools scripts locate everything themselves and honour
`GODOT`, `JAVA_HOME`, `ANDROID_HOME` overrides.

Fresh machine, in order:

```bash
brew install openjdk@17
# Download "Command line tools only" for macOS from developer.android.com/studio,
# verify its SHA, unzip to ~/Library/Android/sdk/cmdline-tools/latest
yes | ~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --licenses
~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmake;3.10.2.4988404" "ndk;28.1.13356709"
# Godot editor → Editor → Manage Export Templates → Download and Install (4.7.2.stable)
```

## Export preset — "Android Debug"

| Setting | Value |
|---|---|
| Package | `com.chavensl.tuktukcolombo` — **provisional development ID**; confirm the final store ID before any public release (it cannot change after publishing) |
| App name / version | TukTuk Colombo · 0.0.3a (code 3) |
| Build | Gradle build (needed to set SDK levels) — min SDK **28** (Android 9), target SDK **35** |
| ABI | `arm64-v8a` only |
| Orientation | sensor landscape (`display/window/handheld/orientation=4`) |
| Renderer | Mobile (Vulkan) |
| Screen | immersive mode |
| Permissions | none |
| Excluded from the PCK | `tests/*`, `docs/*`, `tools/*`, `builds/*` |
| Output | `builds/android/tuktukcolombo-debug.apk` (git-ignored) |

The Gradle project is generated into `android/` (git-ignored) from the
4.7.2 templates by `--install-android-build-template`.

## Scripts

```bash
tools/android_preflight.sh      # PASS/FAIL for every toolchain item
tools/export_android_debug.sh   # preflight → import → export → path, size, SHA-256, manifest summary
tools/android_device_info.sh    # model, Android/API, ABI, SoC, screen, RAM, installed?
tools/install_android_debug.sh  # adb install -r + launch (never uninstalls anything)
tools/android_perf_test.sh 300  # 5-minute deterministic perf test on the phone, pulls JSON
```

## Device (owner steps)

1. Phone: Settings → About phone → tap *Build number* 7× → Developer options →
   enable **USB debugging**.
2. Connect by USB, unlock the phone, accept *Allow USB debugging* (tick
   *Always allow from this computer*).
3. `~/Library/Android/sdk/platform-tools/adb devices` must list the phone as `device`.
4. `tools/export_android_debug.sh && tools/install_android_debug.sh`
5. Optional: `tools/android_perf_test.sh` (keep the screen on, ~6 minutes).

If install reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, an older copy signed
with another key is on the phone. The script will not remove it; uninstall it
yourself only if losing its local save is fine.

Logs: `adb logcat -s godot:V`.
