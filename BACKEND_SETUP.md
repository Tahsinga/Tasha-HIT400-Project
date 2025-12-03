# Tasha Bot — Backend Architecture Setup

## What Changed

Your app now uses a **secure backend architecture**:

- ✅ **OpenAI API key on backend only** (not in Flutter app)
- ✅ **Backend handles chunking, batching, and retries**
- ✅ **App communicates via secure HTTP + app-level auth**
- ✅ **Better performance & reliability**

## Quick Start

### 1. Backend Setup (Python)

```bash
cd backend/
pip install -r requirements.txt
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Backend runs at: `http://localhost:8000`

### 2. Flutter App Configuration

Open the app's Settings screen and enter:

- **Backend URL**: `http://localhost:8000` (or your server URL)
- **App Auth Token**: `your-app-secret-token-here` (can be anything for local dev)

The app will save these in `SharedPreferences` and use them for all API calls.

### 3. Test the connection

- Open the app and navigate to Chat (RAG) page
- Try asking a question — the app will use your backend!
- Check the Python backend logs for `[RagService]` and `[EmbeddingService]` messages

## Architecture

```
┌─────────────────────────┐
│   Flutter App (Dart)    │
│  - UI                   │
│  - Chunking             │
│  - Local VectorDB       │
└────────────┬────────────┘
             │ HTTP + Bearer Token
             ▼
┌─────────────────────────┐
│  Python FastAPI Backend │
│  - OpenAI API Key       │
│  - Rate Limiting        │
│  - Batch Processing     │
│  - Response Streaming   │
└────────────┬────────────┘
             │ OPENAI_API_KEY (env var)
             ▼
┌─────────────────────────┐
│   OpenAI API            │
│  - GPT-4o-mini          │
│  - Embeddings           │
└─────────────────────────┘
```

## Key Files

### Backend

- `backend/main.py` — FastAPI server with all endpoints
- `backend/requirements.txt` — Python dependencies
- `backend/.env` — Environment variables (add your OpenAI key here)

### Flutter

- `lib/services/backend_client.dart` — HTTP client for backend
- `lib/services/embedding_service.dart` — Uses backend embeddings
- `lib/services/rag_service.dart` — Uses backend RAG endpoint
- `lib/services/backend_config.dart` — Configuration manager

## Backend Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Health check |
| `/process_chunk` | POST | Process single chunk with OpenAI |
| `/embeddings` | POST | Get embeddings for texts |
| `/rag/answer` | POST | Answer question using chunks (RAG) |
| `/train/book` | POST | Generate Q/A pairs for training |

## Environment Variables

**Backend (.env):**
```
OPENAI_API_KEY=sk-your-real-openai-key
```

**Flutter (Settings screen):**
```
Backend URL: http://localhost:8000 (or your production URL)
App Auth Token: your-app-secret-token
```

## Security Best Practices

✅ **Never put OpenAI key in the app** — it's on the backend only
✅ **Use app-level auth tokens** — validate requests on backend
✅ **Rate limiting** — enforce limits per user/minute
✅ **Logging** — audit all API calls
✅ **HTTPS** — use in production (set `https://` URL)
✅ **Environment variables** — never commit secrets

## Troubleshooting

### "Connection refused" / "Backend not found"
- Make sure Python backend is running: `python -m uvicorn main:app --reload`
- Check backend URL in Settings matches where it's running (default: `http://localhost:8000`)

### "Unauthorized" error
- Make sure App Auth Token matches in both Settings and backend (or in `.env` if deploying)
- Update backend `.env` with a real app token if needed

### "Rate limit exceeded"
- Wait 1 minute before retrying
- Adjust `REQUESTS_PER_MINUTE` and `REQUESTS_PER_HOUR` in `main.py` if needed

### "OpenAI timeout"
- Your text chunks are too large or OpenAI is slow
- Try smaller chunks (< 2000 chars each)
- Retry with fewer chunks

### Backend errors in logs
- Check Python backend logs for `[ERROR]` messages
- Ensure `OPENAI_API_KEY` is set correctly in `.env`
- Make sure `requirements.txt` packages are installed

## Next Steps

1. ✅ **Run backend locally** to test
2. ✅ **Configure Flutter app** with backend URL/token
3. ✅ **Test chat** and verify no UI freezes
4. 📦 **Deploy backend** (Railway, Render, AWS Lambda, etc.)
5. 🔒 **Enable HTTPS** and proper auth for production
6. 📊 **Monitor** API calls and costs

## Performance Gains

With this architecture:
- ✅ **No UI freezes** — heavy OpenAI calls happen on backend
- ✅ **Better answers** — backend can batch/optimize requests
- ✅ **Cheaper** — backend can combine requests, cache responses
- ✅ **Safer** — no API keys in reverse-engineered app
- ✅ **Scalable** — backend can handle rate limits, retries

## Questions?

Check the backend `README.md` for more details or the logs for debugging.

Happy coding! 🚀
