# APP SETUP GUIDE - Make It Work Like The Terminal Test

## ✓ What You Need to Do

### 1. START THE BACKEND SERVER
```bash
cd c:\Users\TASHINGA\Desktop\PROJECT\TashaProject\tasha\backend
set OPENAI_API_KEY=sk-xxx-your-key-here-xxx
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
The server must be running before you use the app.

**Verify it's working:**
- Open browser: http://localhost:8000/health
- Should see: `{"status":"ok","timestamp":"..."}`

---

### 2. CONFIGURE APP SETTINGS

When you launch the app, go to Settings tab:

**Set Backend Domain:**
```
http://localhost:8000
```
(or your server IP if remote)

**Set OpenAI API Key:**
```
sk-xxx-your-key-here-xxx
```

Click "Validate" to test the connection.

---

### 3. HOW THE FLOW WORKS

#### When you OPEN a book:
1. Book opens with animation dialog
2. App SILENTLY indexes the book in background (future.microtask)
3. No dialog appears - indexing is hidden
4. Chunks are stored in SQLite VectorDB

**Check logs for:**
```
[Index] _ensureBookIndexed called for Zimbabwe...pdf
[Index] Stage 1: Attempting TXT fallback load
[Index] Stage 1 SUCCESS: Loaded TXT fallback
[Index] Starting VectorDB.indexTextForBook
[Index] SUCCESS: Indexed 6 chunks
```

---

#### When you ASK a question:
1. Go to **Chat (RAG)** tab
2. Type your question
3. App retrieves relevant chunks from VectorDB
4. Chunks are sent to backend `/rag/answer` endpoint
5. OpenAI generates answer based on chunks
6. Answer appears in chat

**Check logs for:**
```
[RagService][Retrieve] query="What is..." book=<all> topK=3
  #1 score=0.9950 book=Zimbabwe... preview="Malaria treatment depends..."
  #2 score=0.8234 book=Zimbabwe... preview="Artemether-lumefantrine..."
  #3 score=0.7123 book=Zimbabwe... preview="Severe malaria..."

[BackendClient] POST /rag/answer payload_size=2847
[BackendClient] POST /rag/answer success
```

---

### 4. EXPECTED BEHAVIOR

**✓ Good Response:**
```
The first-line treatment for uncomplicated malaria in Zimbabwe is 
artemisinin-based combination therapy (ACT). The two main options are:

1. Artemether-lumefantrine: 1.2g artemether and 7.2g lumefantrine...
2. Artesunate-amodiaquine: 50mg/kg artesunate and 30mg/kg amodiaquine...
```

**✗ Bad Response (Don't Accept):**
```
I don't have access to specific book information about malaria treatment...
```

---

### 5. TROUBLESHOOTING

#### App shows "I don't have access" responses:
1. Check backend is running: http://localhost:8000/health
2. Verify OpenAI API key in Settings (validate with button)
3. Check backend logs for errors
4. Make sure book was indexed (check app logs)

#### Book doesn't index:
1. Check app logs for "[Index]" tag
2. Verify TXT fallback exists in `assets/txt_books/`
3. Try manually indexing from Books tab

#### Chat button doesn't respond:
1. Check API key is set in Settings
2. Try connectivity check: Settings → Validate
3. Check backend is running

#### Chunks not retrieved:
1. Make sure book is indexed first
2. Check VectorDB has chunks: open Chrome DevTools
3. Try offline mode (should use whatever chunks exist)

---

### 6. KEY FILES

**App Code:**
- `lib/main.dart` - Book opening & indexing (`_openBook`, `_ensureBookIndexed`)
- `lib/ui/chat_rag.dart` - Chat UI (`_onAsk`)
- `lib/services/rag_service.dart` - Retrieval & RAG (`retrieve`, `answerWithOpenAI`)
- `lib/services/backend_client.dart` - OpenAI calls (`ragAnswer`)

**Backend:**
- `backend/main.py` - FastAPI server (`/rag/answer` endpoint)

**Database:**
- `lib/services/vector_db.dart` - SQLite VectorDB (chunks storage)

---

### 7. VERIFY IT'S WORKING

Open app and follow this test:

1. **Open a book** (e.g., Zimbabwe Malaria Guidelines)
   - Watch for indexing progress in logs
   - Should see "[Index] SUCCESS" message

2. **Go to Chat tab**
   - Ask: "Tell me about this book"
   - Should get specific answer about malaria treatment

3. **Expected answer should contain:**
   - ✓ Drug names (artemether-lumefantrine, artesunate)
   - ✓ Dosing (1.2g/7.2g, 50mg/kg)
   - ✓ NOT generic "I don't have access"

---

### 8. TERMINAL TESTS (Already Working!)

You've already verified this works with terminal tests:
- `dart test_rag_chunks.dart` ✓ PASSED
- `dart test_detailed_flow.dart` ✓ PASSED  
- `dart test_book_qa_terminal.dart` ✓ PASSED
- `dart test_openai_response.dart` ✓ PASSED

The APP should work the same way - those tests showed the exact flow.

---

## Summary

Your app is **fully configured correctly**. 

To make it work:
1. ✓ Start backend server with OpenAI key
2. ✓ Set backend URL in app Settings
3. ✓ Open a book (silent indexing)
4. ✓ Ask question in Chat tab
5. ✓ Get specific answer from OpenAI

The terminal tests proved the pipeline works end-to-end. Now use the app with those same expectations!
