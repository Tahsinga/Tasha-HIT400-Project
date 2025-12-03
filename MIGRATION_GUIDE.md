# Migration Guide: Update main.dart to Use Backend

## Overview

Replace direct `EmbeddingService(key)` and `RagService(embSvc)` instantiations with backend-based versions.

## Pattern

**Old (Direct OpenAI):**
```dart
final embSvc = EmbeddingService(apiKey);
final rag = RagService(embSvc);
```

**New (Via Backend):**
```dart
final backend = await BackendConfig.getInstance();
final embSvc = EmbeddingService(backend);
final rag = RagService(embSvc, backend);
```

## Changes Needed

Add this import at the top of `main.dart`:

```dart
import 'services/backend_config.dart';
import 'services/backend_client.dart';
```

### Change #1: `_trainActiveBook()` method (line ~870)

```dart
// OLD:
final embSvc = EmbeddingService(key);
final rag = RagService(embSvc);
await rag.trainBookWithOpenAI(bookId, chunks, key);

// NEW:
final backend = await BackendConfig.getInstance();
final embSvc = EmbeddingService(backend);
final rag = RagService(embSvc, backend);
await rag.trainBookWithOpenAI(bookId, chunks);  // No key needed
```

### Change #2: Search/Answer path (line ~2950)

```dart
// OLD:
final embSvc = EmbeddingService(key);
final rag = RagService(embSvc);
final chunks = await rag.retrieve(q, topK: 5);
final res = await rag.answerWithOpenAI(q, chunks, key);

// NEW:
final backend = await BackendConfig.getInstance();
final embSvc = EmbeddingService(backend);
final rag = RagService(embSvc, backend);
final chunks = await rag.retrieve(q, topK: 5);
final res = await rag.answerWithOpenAI(q, chunks);  // No key needed
```

### Change #3: Embedding usage (line ~4376)

```dart
// OLD:
emb = await EmbeddingService(key).embedText(chunkText);

// NEW:
final backend = await BackendConfig.getInstance();
emb = await EmbeddingService(backend).embedText(chunkText);
```

### Change #4: Other RagService calls (line ~4638, ~3311)

Same pattern as above — always get backend from `BackendConfig.getInstance()`.

## Quick Checklist

- [ ] Add imports for `BackendConfig` and `BackendClient`
- [ ] Replace all `EmbeddingService(key)` with `EmbeddingService(backend)`
- [ ] Replace all `RagService(embSvc)` with `RagService(embSvc, backend)`
- [ ] Remove `key` parameter from `trainBookWithOpenAI()` and `answerWithOpenAI()` calls
- [ ] Test build: `flutter pub get && flutter build`
- [ ] Run app and configure backend URL in Settings
- [ ] Test a query to verify backend communication

## Settings Screen Addition

Add a "Backend Settings" section to your Settings UI:

```dart
TextFormField(
  label: "Backend URL",
  initialValue: configData['BACKEND_URL'] ?? 'http://localhost:8000',
  onSaved: (value) async {
    await BackendConfig.setBackendConfig(
      value ?? '',
      configData['APP_AUTH_TOKEN'] ?? ''
    );
  }
),
TextFormField(
  label: "App Auth Token",
  initialValue: configData['APP_AUTH_TOKEN'] ?? '',
  obscureText: true,
  onSaved: (value) async {
    await BackendConfig.setBackendConfig(
      configData['BACKEND_URL'] ?? '',
      value ?? ''
    );
  }
),
```

## Testing

1. Ensure backend is running:
   ```bash
   cd backend/
   python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

2. Run the app and configure Settings with:
   - Backend URL: `http://localhost:8000`
   - App Auth Token: `test-token`

3. Try asking a question to verify the flow works.

## Troubleshooting

- **"No matching declarations"** — Add the imports at the top of main.dart
- **"Backend not found"** — Verify Python server is running and URL is correct
- **"Unauthorized"** — Check app auth token matches (can be anything for local dev)
- **"RagService constructor expects 2 parameters"** — Make sure you pass both `embSvc` and `backend`

That's it! The backend will handle all OpenAI communication safely.
