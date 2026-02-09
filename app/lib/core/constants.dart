/// Backend base URL. For Android emulator use 10.0.2.2:8000, for iOS simulator use localhost:8000.
const String kBaseUrl = 'http://localhost:8000';

/// Web OAuth client ID (same as backend GOOGLE_CLIENT_ID). Required for native Google Sign-In to get id_token.
const String kGoogleWebClientId = '921560413163-0pfj2uuhb4jonoklf9ivjjj05rvran9a.apps.googleusercontent.com';

const String kStorageKeyAccessToken = 'access_token';
const String kStorageKeyUserId = 'user_id';
const String kStorageKeyEmail = 'email';
const String kStorageKeyName = 'name';
