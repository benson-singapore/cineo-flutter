# Repository Guidelines

## Project Structure & Module Organization

Cineo is a Flutter application for local-first media discovery and playback. Code in `lib/` is organized by responsibility:

- `lib/core/`: shared models, theme, demo data, and platform integrations.
- `lib/data/`: remote clients, disk caches, and media repositories.
- `lib/features/`: user-facing areas such as `home`, `search`, `player`, `settings`, `sources`, and `app_lock`.
- `lib/shared/widgets/`: reusable media cards, rails, images, and state views.
- `test/`: unit and widget tests mirroring the relevant feature or layer.
- `assets/branding/`: bundled branding assets; platform runners are in `android/`, `ios/`, and `web/`.

Keep new code inside the owning feature or layer. Add shared abstractions only when used across multiple features.

## Build, Test, and Development Commands

Run `flutter pub get` after dependency changes, then use:

```bash
flutter run                 # Launch on a connected device or emulator
flutter test                # Run the complete test suite
flutter analyze             # Run static analysis and lints
dart format lib test        # Format Dart source and tests
make android                # Build a signed release APK locally
make ios                    # Build an unsigned release IPA locally
```

For focused feedback, run a file directly, such as `flutter test test/mac_cms_client_test.dart`.

## Coding Style & Naming Conventions

Use standard Dart formatting with two-space indentation and `package:flutter_lints/flutter.yaml`. Use `PascalCase` for classes and widgets, `camelCase` for methods, variables, and fields, and `snake_case.dart` for filenames. Prefer small, composable widgets and repository/client boundaries consistent with nearby code. Keep assets declared in `pubspec.yaml` and avoid secrets in source.

## Testing Guidelines

Tests use `flutter_test` for widget and unit tests. Name files with the production file plus `_test.dart`, and place feature tests under `test/features/<feature>/`. Cover parsing, persistence, async states, and user-visible interactions when changing those behaviors. Run focused tests, then `flutter test` and `flutter analyze` before submitting.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commits, commonly `feat(scope): ...`, `fix(scope): ...`, `refactor(scope): ...`, `style(scope): ...`, and `docs(scope): ...`; keep subjects short and imperative. Pull requests should explain the user-visible or architectural change, identify validation commands, link related issues when applicable, and include screenshots or recordings for UI changes. Keep unrelated formatting or generated build output out of the change.

## Configuration & Release Notes

Review `README.md` for TMDB and media-source setup. Version and build-number changes are managed through the root `Makefile` and `scripts/update_version.sh`; coordinate release changes rather than editing generated platform metadata independently.
