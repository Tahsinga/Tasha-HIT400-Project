# ✅ BACKEND ARCHITECTURE: Why & How

## Your Questions Answered

### 1. "Why do I need a local server?"

**Short Answer:** You don't! The backend should be deployed to a **cloud server**, not local.

### 2. "How will the phone reach it?"

**The Problem:**
```
❌ Phone CANNOT reach http://localhost:8000
   └─ "localhost" only exists on the computer running it
   └─ Phone has its own network, doesn't have "localhost"
```

**The Solution:**
```
✅ Deploy backend to cloud (AWS, Heroku, Railway, etc.)
   ├─ Backend gets public URL: https://tasha-backend.railway.app
   └─ Phone can reach it from anywhere
```

### 3. "Method Not Allowed" Error

**The Issue:**
- App tried to use `/embeddings` endpoint
- Got `{"detail":"Method Not Allowed"}` (HTTP 405)
- **Cause:** Backend auth token format was incorrect

**Fixed Now:** ✅ Backend configured to accept requests

---

## Architecture Explanation

### Current Setup (Development)
```
Phone/Computer ──┐
                 ├──→ Local Backend (http://localhost:8000)
                 │    └─ ONLY works on same computer
                 │    └─ Phone CANNOT reach it

Medical Books ──→ VectorDB (SQLite on phone)
                  └─ Stored locally on phone
```

### Production Setup (What We Need)
```
Phone ──→ INTERNET ──→ Cloud Backend (https://tasha-backend.railway.app)
                       ├─ Receives question + chunks
                       ├─ Sends to OpenAI API
                       └─ Returns answer

Medical Books ──→ VectorDB (SQLite on phone)
                  └─ Stored locally on phone
```

### Why Split Backend & Phone?

| Component | Location | Why |
|-----------|----------|-----|
| **Books + Chunks** | Phone (SQLite) | Fast, offline access, user privacy |
| **OpenAI API Key** | Backend Server | Secure (never exposed to phone) |
| **RAG Logic** | Backend Server | Centralized, can update without app update |
| **Embeddings** | Phone (for now) | Fast, but can move to backend later |

---

## Deployment Options (Choose One)

### Option 1: **Railway** ⭐ Recommended (Free)
```bash
# 1. Go to railway.app
# 2. Click "Deploy Now" 
# 3. Connect GitHub
# 4. Deploy main.py with requirements.txt
# 5. Get public URL: https://your-app.railway.app
```

**Advantages:**
- ✅ Free tier
- ✅ Auto-deploys from GitHub
- ✅ Public HTTPS URL
- ✅ Easy to set OpenAI key as env variable

### Option 2: **Heroku**
```bash
heroku create tasha-backend
git push heroku main
heroku config:set OPENAI_API_KEY=sk-proj-...
```

### Option 3: **AWS EC2**
```bash
# Launch Ubuntu instance
# Install Python, FastAPI, Uvicorn
# Run: python -m uvicorn main:app --host 0.0.0.0 --port 8000
# Get public IP
```

### Option 4: **Keep Local for Now** (Testing Only)
If testing on same WiFi network as computer:
```
Backend on computer: 192.168.1.100:8000  (your computer's IP)
Phone connects to:   http://192.168.1.100:8000
```

---

## How to Configure App for Cloud Backend

### In Flutter App Settings:
```
Backend URL: https://tasha-backend.railway.app  (or your cloud URL)
App Auth Token: test-app-token
OpenAI API Key: (optional - backend has it)
```

### Backend Running Now:

✅ **LOCAL (testing on same network):**
```
http://0.0.0.0:8000  (listens on all interfaces)
```

**To connect phone on same WiFi:**
1. Find your computer's IP: `ipconfig` → IPv4 Address (e.g., 192.168.1.100)
2. In app settings: `http://192.168.1.100:8000`

---

## Current Backend Status

✅ **Backend Running on 0.0.0.0:8000**
- Listening on all network interfaces
- Ready for local network testing
- Can be deployed to cloud anytime

### Endpoints Available:
```
POST /health                  - Health check
POST /process_chunk          - Process single chunk
POST /embeddings             - Get text embeddings
POST /rag/answer             - Answer question with RAG
POST /train/book             - Generate Q&A pairs
```

### Test Endpoints:

**Health Check:**
```powershell
Invoke-WebRequest http://localhost:8000/health
```

**RAG Answer (with chunks):**
```powershell
$body = @{
    question = "Tell me about TB"
    chunks = @(
        @{text = "TB is treated with isoniazid"; book = "edliz"; start_page = "10"; end_page = "10"}
    )
} | ConvertTo-Json

Invoke-WebRequest -Uri 'http://localhost:8000/rag/answer' `
  -Method POST `
  -Headers @{'Content-Type'='application/json'; 'Authorization'='Bearer test-app-token'} `
  -Body $body
```

---

## Next Steps

### Phase 1: Test Locally (Now)
1. ✅ Backend running on `0.0.0.0:8000`
2. Test on phone via WiFi: `http://YOUR-COMPUTER-IP:8000`
3. Verify chunks reach OpenAI
4. Verify bot answers questions

### Phase 2: Deploy to Cloud (Later)
1. Choose cloud provider (Railway recommended)
2. Deploy `backend/main.py` + `requirements.txt`
3. Set env variable: `OPENAI_API_KEY=sk-proj-YOUR-KEY`
4. Update app settings to use cloud URL
5. Test from anywhere (no need for WiFi)

### Phase 3: Production
1. Get real domain: `tasha-backend.mycompany.com`
2. Enable HTTPS (auto with Railway)
3. Monitor API usage
4. Scale as needed

---

## File Structure for Deployment

```
backend/
├── main.py              ← FastAPI app
├── requirements.txt     ← Dependencies
└── .env                 ← Env variables (don't commit)

.gitignore
└── .env                 ← Keep secret!
```

**Deploy to Railway:**
1. Push to GitHub
2. Railway auto-detects Python
3. Sets port automatically
4. Done! ✅

---

## Why This Architecture?

### Benefits:
1. **Security** — API key never touches phone
2. **Flexibility** — Update backend without app updates
3. **Scalability** — Backend can handle multiple phones
4. **Offline** — Phone still works if backend down (fallback to local DB)
5. **Fast** — Chunks computed on phone, only send to backend when needed

### Phone Responsibilities:
- ✅ Extract text from PDFs/TXT
- ✅ Create chunks (1000 words each)
- ✅ Store in SQLite VectorDB
- ✅ Retrieve relevant chunks for question
- ✅ Display answer to user

### Backend Responsibilities:
- ✅ Receive question + chunks from phone
- ✅ Format prompt for OpenAI
- ✅ Call OpenAI API (secure)
- ✅ Return answer to phone

---

## Summary

| Before | After |
|--------|-------|
| ❌ App connected to local server only | ✅ Backend on 0.0.0.0:8000 (all interfaces) |
| ❌ Phone couldn't reach localhost | ✅ Phone can reach via IP on WiFi |
| ❌ No plan for production | ✅ Deploy to Railway for production |
| ❌ API key exposed in app | ✅ API key secure on backend |

**Next: Update app to use cloud URL (or local IP for testing)**

