# ProductOS Flutter — Agent Instructions (canonical)

## User-owned GitHub export

This repository is AMID Offgrid, exported to DimasikBog/AMID-Offgrid.
Use `.github/workflows/mobile.yml` for GitHub checks/builds. The ProductOS
supervisor commands below apply only inside a ProductOS workspace that provides
them. On an ordinary workstation/CI, use the Flutter CLI normally.
Keep native app code in sync across Android and iOS. Never describe an unsigned
iOS app as installable on an iPhone. Private signing keys are excluded from this
export; use an approved secret store for future distribution signing.

`CLAUDE.md` points here. This is a **Flutter** app (Dart), not a web/Node
project. It ships as a real native Android/iOS app; the in-browser preview is
the same code compiled for Flutter web.

## How this sandbox runs the app (do not fight it)

- A supervisor (`/usr/local/bin/flutter-dev.js`) owns port **3000** and runs
  `flutter run -d web-server` behind it. **Never run `flutter run` yourself**
  and never bind anything else to 3000/3001.
- Saving a file under `lib/`, `assets/`, `web/` or `pubspec.yaml` triggers a
  hot restart automatically. A `pubspec.yaml` change runs `flutter pub get`
  and restarts.
- Control it with the `productos-flutter` CLI:
  - `productos-flutter status` — JSON: web preview state, last error, APK state
  - `productos-flutter logs [n]` — last n lines of `/tmp/dev.log` (compile errors land here)
  - `productos-flutter reload` — hot restart now
  - `productos-flutter restart` — pub get + full restart (after native/plugin changes)
  - `productos-flutter apk` — build a release Android APK; waits up to ~100 s. If it
    says "Still building", run `productos-flutter apk wait` (never starts a new build)
- The user installs the APK from `<preview-url>/__productos/android` (QR code).
- iOS builds need macOS + Xcode and cannot be produced in this sandbox. Keep
  `ios/` valid so the project builds on a Mac / CI, but don't promise an IPA.

## Verifying your work

1. `flutter analyze` — must be clean of errors before you finish.
2. `productos-flutter status` — `web` must be `ready` and `lastError` null.
3. Check the preview in the browser (agent-browser on http://localhost:3000).

## Rules

- Dependencies: `flutter pub add <pkg>` (never hand-edit versions you haven't
  checked on pub.dev). Prefer packages that support **android, ios and web**,
  since the preview is web — a mobile-only plugin (e.g. some camera/BLE
  plugins) must be guarded with `kIsWeb` and a web fallback.
- Material 3 (`useMaterial3: true`), responsive layouts (`LayoutBuilder`,
  `MediaQuery`), light + dark themes.
- Structure: `lib/main.dart` (app + routes), `lib/screens/`, `lib/widgets/`,
  `lib/models/`, `lib/services/`. Keep widgets small and `const` where possible.
- State: start with `setState`/`ValueNotifier`; reach for `provider` or
  `riverpod` only when state is shared across screens.
- Native config lives in `android/` and `ios/`; app id is
  `dev.productos.productos_app` until the user picks their own.
- Backend: no ProductOS database/storage provisioning for Flutter. Local data →
  shared_preferences / sqflite (with a web fallback); cloud → Supabase or Firebase
  Flutter SDKs with client-safe keys. Never add Node/npm/Prisma files here.
- In the original ProductOS workspace, preserve its existing
  `android/productos-debug-keystore.b64` so that development installs remain
  updatable there. Do not copy that private key into this GitHub export.
- Don't commit `build/` or `.dart_tool/`.
