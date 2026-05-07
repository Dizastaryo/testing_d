# SeeU - Flutter Social Network App

## Project Overview
SeeU - социальная сеть с BLE-сканером на Flutter. Подключена к Go бэкенду (API).

## Tech Stack
- **Framework:** Flutter 3.x, Dart >=3.0.0
- **State Management:** Riverpod (flutter_riverpod + riverpod_annotation + riverpod_generator)
- **Navigation:** GoRouter
- **Networking:** Dio
- **BLE:** flutter_blue_plus
- **UI:** phosphor_flutter (иконки), google_fonts, flutter_animate, shimmer

## Architecture
```
lib/
  core/
    api/          — API client & endpoints
    design/       — UI kit: SeeUButton, SeeUCard, SeeUInput, tokens.dart
    models/       — Data models (User, Post, Story, Comment, Notification)
    providers/    — Riverpod providers (auth, feed, story, chat, user, notification)
    theme/        — app_theme.dart (light + dark)
  features/       — Screens by feature (auth, chat, explore, feed, onboarding, post, profile, settings, stories, reels, services)
  widgets/        — Shared widgets
  services/       — Account session, chip control, user resolver
```

## Design Conventions
- **Colors:** Orange (#FF5A3C) primary + milky white background
- **Language:** All UI text in Russian
- **Icons:** Phosphor icons (`PhosphorIconsBold`, `PhosphorIconsRegular`)
- **Design system:** Use `SeeU*` widgets from `core/design/`
- **Theme:** Support both light and dark themes via `app_theme.dart`

## Development Rules
- Run `flutter analyze` after editing Dart files — fix all errors and warnings
- Run `flutter test` before committing (if tests exist)
- **НИКАКИХ МОКОВ НА ФРОНТЕ** — все данные берутся с бэкенда через API. Никаких MockService, fake numbers, hardcoded counts. Для тестовых данных используй seed SQL файлы и добавляй в базу через бэкенд.
- **NEVER modify `.github/` directory** — only adapt code to match the workflow
- Keep bottom nav bar, scanner page, orange + milky white color scheme
- Prefer editing existing files over creating new ones
- Use Riverpod for all state management (no setState for shared state)
- Code must build as unsigned IPA via `.github/workflows/dart.yml` (Flutter 3.41.6, xcodebuild, no codesign)

## Bottom Navigation (6 items)
1. Лента (Feed) → `/feed`
2. Интересное (Explore) → `/explore`
3. Сервисы (orange center button) → `/services` (Music, Video, Library)
4. Рилсы (Reels viewer) → `/reels`
5. Сканер (Scanner) → `/scanner`
6. Профиль (Profile) → `/profile`

## Content Creation
- From Profile: "+" button in header → modal (post, reel, story)
- From Feed: swipe right → camera → publish

## Common Commands
```bash
flutter analyze          # Check for errors
flutter run -d chrome    # Run in Chrome
flutter run              # Run on connected device
flutter pub get          # Get dependencies
flutter pub run build_runner build --delete-conflicting-outputs  # Generate Riverpod code
```

## ESP32 BLE Tag Config
- Device name: `ESP32C3_TAG`
- Broadcast data: `DEVICE_0001`
