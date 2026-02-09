# English Words

Flutter app for learning English vocabulary with spaced repetition (FSRS), backed by FastAPI.

## Features

- **Decks and cards**: Create decks, add words (word, translation, example).
- **Spaced repetition**: Study with Again / Hard / Good / Easy; FSRS on backend.
- **Generate words**: AI-generated word lists by CEFR level (A1–C1) or topic via Gemini.
- **Enrich word**: Get translation and example for a single word via Gemini.
- **Similar words**: Find semantically similar words (pgvector + Gemini embeddings).
- **Auth**: Google OAuth2; JWT stored in Flutter secure storage.

## Stack

- **Backend**: FastAPI, PostgreSQL (with pgvector), Google OAuth2, Gemini API, FSRS.
- **App**: Flutter, Dio, Provider, go_router, flutter_secure_storage, app_links.

## Backend setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
cp .env.example .env
# Edit .env: DATABASE_URL, SECRET_KEY, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GEMINI_API_KEY
```

Create DB and install pgvector, then run migrations:

```bash
python scripts/init_db.py   # creates english_app if needed, runs CREATE EXTENSION vector
alembic upgrade head
```

Alternatively create the DB manually (`createdb -p 5440 english_app`) and run `CREATE EXTENSION vector` in it, then `alembic upgrade head`.

Run:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8007
```

PostgreSQL: use port 5440, password from plan (see `.env.example`). Enable pgvector: `CREATE EXTENSION IF NOT EXISTS vector;` (done in migration).

## Flutter setup

```bash
cd app
flutter pub get
```

Set backend URL in `lib/core/constants.dart` (`kBaseUrl`). For Android emulator use `http://10.0.2.2:8007`.

Run:

```bash
flutter run
```

## OAuth

1. Create OAuth 2.0 credentials in Google Cloud Console (Web application).
2. Add redirect URI: `http://localhost:8007/auth/google/callback` (and your production URL).
3. Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in backend `.env`.
4. For mobile deep link after login, backend redirects to `englishapp://auth#access_token=...`. The app is configured for `englishapp` scheme on Android and iOS.

**Native Google Sign-In (in-app):** The app uses `google_sign_in` and exchanges the Google ID token with the backend (`POST /auth/google/token`). Set `kGoogleWebClientId` in `app/lib/core/constants.dart` to the same value as backend `GOOGLE_CLIENT_ID`. You must create an **Android** (and optionally **iOS**) OAuth client in Google Cloud so the native SDK can sign in; the backend continues to use the **Web** client.

### Google Auth (Android)

For **native "Sign in with Google"** on Android you must create **OAuth 2.0 Client ID (Android)** in [Google Cloud Console](https://console.cloud.google.com/apis/credentials) and provide:

- **Package name**: `com.english.english_words`
- **SHA-1 certificate fingerprint** of the keystore used to sign the app.

**Get SHA-1:**

- **Debug** (development)—easiest: run the script (requires Java):
  ```bash
  ./app/scripts/get_sha1.sh
  ```
  Or manually:
  ```bash
  cd app/android && ./gradlew signingReport
  ```
  Or with keytool:
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
  In the output find the line `SHA1: XX:XX:...`.

- **Release**: use the keystore you use for release builds:
  ```bash
  keytool -list -v -keystore /path/to/your/release.keystore -alias your_alias
  ```

In Google Cloud Console: **APIs & Services → Credentials → Create credentials → OAuth client ID → Android**. Enter package name `com.english.english_words` and the SHA-1.

### Google Auth (iOS)

For native sign-in on iOS: (1) Create an **iOS** OAuth client in Google Cloud with your app **Bundle ID** (see Xcode or `ios/Runner.xcodeproj`). (2) In `app/ios/Runner/Info.plist`, add a second entry under `CFBundleURLTypes` with `CFBundleURLSchemes` = your **reversed Web client ID** (e.g. for `123-abc.apps.googleusercontent.com` use `com.googleusercontent.apps.123-abc`). See [Google Sign-In iOS docs](https://developers.google.com/identity/sign-in/ios).

## Project structure

- `backend/`: FastAPI app (routers: auth, decks, cards, ai; services: auth, fsrs, gemini; PostgreSQL + pgvector).
- `app/`: Flutter app (screens: login, home, deck, add word, generate words, similar words, study, settings; API client, auth provider).
