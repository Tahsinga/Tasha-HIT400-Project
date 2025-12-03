Render deployment instructions for Tash-Main
=========================================

This file shows the exact steps to deploy the FastAPI backend on Render and how to call it from your mobile app.

1) Prepare repository
- Ensure `backend/main.py` and `backend/requirements.txt` are present (they are).
- I added a `Procfile` that instructs Render to run Gunicorn with Uvicorn workers:
  `web: gunicorn -k uvicorn.workers.UvicornWorker backend.main:app --bind 0.0.0.0:$PORT`

2) Create a Web Service on Render
- Go to https://dashboard.render.com and click "New" -> "Web Service".
- Connect your GitHub account and pick the repo `nyuchi20/Tash-Main` (or the repo you provided).
- Branch: choose `master` (or the branch you want to deploy).
- Environment: `Python 3` (Render will detect Python and install `requirements.txt`).
- Build command (optional):
  ```bash
  pip install -r backend/requirements.txt
  ```
- Start command: the `Procfile` will be used automatically by Render. If you need an explicit start command, use:
  ```bash
  gunicorn -k uvicorn.workers.UvicornWorker backend.main:app --bind 0.0.0.0:$PORT
  ```
- Click "Create Web Service" and wait for the build to finish.

3) Environment variables (important)
- Open the service settings -> Environment -> Environment Variables.
- Add the following variables:
  - `APP_TOKEN` (required): a random strong secret the mobile app will include in `Authorization: Bearer <APP_TOKEN>` when calling the backend. Example: `sN8f4..`.
  - `OPENAI_API_KEY` (optional): your server-side OpenAI API key if you prefer the server to call OpenAI itself. If you set this, the mobile app does NOT need to supply `api_key` on each request.
  - `ALLOWED_ORIGINS` (optional): comma-separated origins allowed for CORS. For quick testing set `*`. For production set your app origin(s), e.g. `https://your-app.example`.

4) Test the service (curl)
- Replace `<SERVICE_URL>` with the Render URL and `<APP_TOKEN>` with your `APP_TOKEN` value.

Health check:
```bash
curl -s https://<SERVICE_URL>/health
```

RAG request test (sample):
```bash
curl -s -X POST https://<SERVICE_URL>/rag/answer \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <APP_TOKEN>" \
  -d '{
    "question": "What is the standard treatment for uncomplicated malaria?",
    "chunks": [
      {"text": "Artemisinin-based combination therapies (ACTs) are the recommended first-line treatment.", "book":"MalariaGuidelines", "start_page":1, "end_page":2}
    ],
    "api_key": "sk-your-openai-key-here"
  }'
```

Notes:
- If you set `OPENAI_API_KEY` on the server, omit the `api_key` field from the request body; the server will use its own key.
- The server expects `Authorization: Bearer <APP_TOKEN>` unless you remove or change that check.

5) Mobile app integration (Dart example)
- Example function to call Render from the mobile app (uses `http` package):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> askRenderRag(
  String serviceUrl,
  String appToken,
  String openAiKey, // optional if server has OPENAI_API_KEY
  String question,
  List<Map<String, dynamic>> chunks,
) async {
  final url = Uri.parse('\$serviceUrl/rag/answer');
  final body = jsonEncode({
    'question': question,
    'chunks': chunks,
    if (openAiKey != null && openAiKey.isNotEmpty) 'api_key': openAiKey,
  });

  final resp = await http.post(url, headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + appToken,
  }, body: body).timeout(const Duration(seconds: 30));

  if (resp.statusCode != 200) {
    throw Exception('Server error: \\${resp.statusCode} \\${resp.body}');
  }
  return jsonDecode(resp.body) as Map<String, dynamic>;
}
```

6) Security recommendations
- Prefer storing the OpenAI API key on the server (`OPENAI_API_KEY`) to avoid shipping user keys.
- Use TLS (Render provides HTTPS).
- Rotate keys and use a short-lifetime token if supporting many users who bring their own keys.

7) Logs & debugging
- Use Render's Logs tab to view stdout/stderr and startup messages.
- If the service fails to start, confirm `requirements.txt` lists needed packages and the `Procfile` command is correct.

If you want, I can:
- Add a `README_RENDER.md` or expand this file and commit it to the repo (done). 
- Patch `lib/services/backend_client.dart` to use the Render URL and `APP_TOKEN` automatically.
