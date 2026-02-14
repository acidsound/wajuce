# wajuce Install Skill Orchestration

Use this file as an agent playbook.  
Do not re-implement shell logic. Always call the executable scripts in `tool/`.

## Inputs

- `APP_ROOT` (required): absolute path to target Flutter app
- `SOURCE` (optional): `pub` (default) or `path`
- `WAJUCE_PATH` (required only when `SOURCE=path`)
- `TARGET` (optional): `none` (default), `web`, `android`, `ios`, `macos`, `windows`

## Required Execution Order

Run from this repository root:

1. Install:

```bash
dart run tool/install_wajuce.dart --app-root "$APP_ROOT" --source "$SOURCE" --target "$TARGET"
```

2. Verify:

```bash
dart run tool/verify_wajuce.dart --app-root "$APP_ROOT" --target "$TARGET"
```

If `SOURCE=path`, append:

```bash
--wajuce-path "$WAJUCE_PATH"
```

## Windows-Specific Target Guidance

- `TARGET=android` on Windows:
  - Script enforces `flutter doctor -v` Android toolchain status check.
- `TARGET=windows` on Windows:
  - Script enforces `flutter doctor -v` Visual Studio status check.
- `TARGET=ios` or `TARGET=macos`:
  - Must run on macOS host; script hard-fails on non-macOS.

## Agent Output Contract

After running, return:

1. Inputs used (`APP_ROOT`, `SOURCE`, `TARGET`)
2. Install command and verify command (exact)
3. DoD status:
   - `pubspec.yaml` has `wajuce`
   - `flutter pub get` success
   - `flutter pub deps` includes `wajuce`
   - target build check result (or skipped)
4. Failure path (if any): failing command + next corrective action
