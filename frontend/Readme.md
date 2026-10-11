# Frontend - Pre-Consultation Agent

Flutter-based user interface for the hospital-owned, voice-based pre-consultation and triage system.

## Purpose

This Flutter application provides the interface for:

- **Kiosk Mode**: Patient-facing voice interaction terminal
- **Doctor Interface**: Healthcare worker dashboard for reviewing consultations
- **Session Management**: Monitoring and managing patient queues

## Features

- **Multilingual Support**: Kinyarwanda and English voice interaction
- **Voice Input/Output**: Audio recording and playback for patient consultations
- **Real-time Translation**: Display translations for both languages
- **Doctor Dashboard**: Review patient summaries and triage recommendations
- **Queue Management**: Track waiting patients and consultation status
- **Cross-platform**: Runs on Android, iOS, Web, and Desktop (for kiosk deployment)

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK
- Android Studio / Xcode (for mobile deployment)
- Backend API running (see backend/README.md)

### Setup

1. **Install Dependencies**

   ```bash
   flutter pub get
   ```

2. **Configure API Endpoint**

   Update the API base URL in `lib/services/` to point to your backend server.

3. **Run the Application**

   ```bash
   # For development (hot reload enabled)
   flutter run

   # For specific platform
   flutter run -d chrome        # Web
   flutter run -d windows       # Windows desktop
   flutter run -d android       # Android device/emulator
   ```

## Project Structure

```
frontend/
├── lib/
│   ├── main.dart              # Application entry point
│   ├── screens/               # UI screens
│   │   ├── kiosk/            # Patient kiosk interface
│   │   └── doctor/           # Healthcare worker dashboard
│   └── services/              # API integration services
├── assets/
│   └── translations/          # i18n files
│       ├── en.json           # English translations
│       └── rw.json           # Kinyarwanda translations
└── README.md
```

## Build for Production

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Windows Desktop (for kiosk)
flutter build windows --release
```

## Translation Files

Translation files are located in `assets/translations/`:

- `en.json`: English text
- `rw.json`: Kinyarwanda text

These files support the bilingual voice interface for the consultation system.

## Development Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)

## System Description

### Text-to-Speech (TTS)

- **ElevenLabs API**: The frontend uses the ElevenLabs Text-to-Speech API with the "Keza — Rwandan Diaspora" voice (multilingual v2) to generate natural-sounding speech in both Kinyarwanda and English.
- **Integration**: The TTS service is implemented in `lib/services/tts_service.dart`, using the `http` package for API calls and `audioplayers` for playback.
- **API Key**: The ElevenLabs API key is loaded from the `.env` file in the frontend directory.

### Audio Handling

- **Recording**: Audio input is managed using the `record` package, supporting all major platforms (Web, Android, iOS, Windows, macOS, Linux).
- **Permissions**: Microphone access is handled via the `permission_handler` package for mobile and desktop, and via browser APIs for web.
- **Encoding**: Audio is recorded in platform-appropriate formats (WAV for web, AAC/M4A for mobile/macOS, WAV for Windows/Linux).
- **Cross-Platform**: Platform-specific logic is abstracted in `audio_service.dart` and its conditional imports (`audio_service_io.dart` for mobile/desktop, `audio_service_stub.dart` for web).

### Backend Integration

- **API Communication**: The frontend communicates with the backend using the `http` package, with API endpoints configured in `lib/services/`.
- **File Uploads**: Audio files are uploaded as multipart form data, with platform-specific implementations for file access and upload.
- **Session Management**: The frontend manages session state and interacts with backend endpoints for starting sessions, submitting audio, and retrieving results.
