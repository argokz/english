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
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

PostgreSQL: use port 5440, password from plan (see `.env.example`). Enable pgvector: `CREATE EXTENSION IF NOT EXISTS vector;` (done in migration).

## Flutter setup

```bash
cd app
flutter pub get
```

Set backend URL in `lib/core/constants.dart` (`kBaseUrl`). For Android emulator use `http://10.0.2.2:8000`.

Run:

```bash
flutter run
```

## OAuth

1. Create OAuth 2.0 credentials in Google Cloud Console (Web application).
2. Add redirect URI: `http://localhost:8000/auth/google/callback` (and your production URL).
3. Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in backend `.env`.
4. For mobile deep link after login, backend redirects to `englishapp://auth#access_token=...`. The app is configured for `englishapp` scheme on Android and iOS.

## Project structure

- `backend/`: FastAPI app (routers: auth, decks, cards, ai; services: auth, fsrs, gemini; PostgreSQL + pgvector).
- `app/`: Flutter app (screens: login, home, deck, add word, generate words, similar words, study, settings; API client, auth provider).
