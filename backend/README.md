# Backend Setup

## Quick Start

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Set up environment variables:**
   ```bash
   cp .env.example .env
   # Edit .env and add your OPENAI_API_KEY
   ```

3. **Run the server:**
   ```bash
   python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

4. **Test health endpoint:**
   ```bash
   curl http://localhost:8000/health
   ```

## Endpoints

- `POST /process_chunk` — Process a single chunk with OpenAI
- `POST /embeddings` — Generate embeddings for texts
- `POST /rag/answer` — Answer a question using chunks (RAG)
- `POST /train/book` — Generate Q/A pairs for a book
- `GET /health` — Health check

## Authentication

All endpoints (except `/health`) require:
```
Authorization: Bearer YOUR_APP_TOKEN
```

Replace `YOUR_APP_TOKEN` with a token from your auth system (Firebase, JWT, etc.).

## Rate Limiting

- 60 requests/minute per user
- 1000 requests/hour per user
- Enforced via simple in-memory store (use Redis in production)

## Security Best Practices

✅ **NEVER commit `.env` with real keys**
✅ OpenAI API key stored on server only
✅ All requests require app-level auth token
✅ Rate limiting prevents abuse
✅ Logging for audit trail

## Deployment

For production:
- Use a managed service (Railway, Render, AWS Lambda)
- Set `OPENAI_API_KEY` as an environment variable
- Use Redis for rate limiting instead of in-memory
- Enable HTTPS and CORS properly
- Set up proper auth validation (Firebase, JWT)
- Use a production ASGI server (Gunicorn + Uvicorn)

Example production command:
```bash
gunicorn -w 4 -k uvicorn.workers.UvicornWorker main:app
```

## Troubleshooting

**"OPENAI_API_KEY not set"** — Add your key to `.env` or environment variables.

**"Rate limit exceeded"** — Wait 1 minute and retry, or increase limits in `main.py`.

**"Timeout"** — OpenAI took >30s. Retry with fewer/smaller chunks.
