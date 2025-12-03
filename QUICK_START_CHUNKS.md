# 🎯 QUICK-START: See Chunks Reaching OpenAI

## ✅ I've Added Complete Logging

**3 files modified** to show chunks flowing through system:
- ✅ `lib/services/rag_service.dart` — shows chunks retrieved + normalized
- ✅ `lib/services/backend_client.dart` — shows chunks sent to backend
- ✅ `backend/main.py` — shows chunks received + sent to OpenAI

---

## 🚀 Steps to See It Working

### Step 1: Set Real OpenAI Key
```powershell
# Copy and paste this with YOUR real OpenAI key
$env:OPENAI_API_KEY = "sk-proj-REPLACE_WITH_YOUR_REAL_KEY"
```

**Where to find your key:**
- Go to https://platform.openai.com/api/keys
- Click "Create new secret key"
- Copy the full key (starts with `sk-proj-`)

### Step 2: Start Backend
```powershell
cd "C:\Users\TASHINGA\Desktop\PROJECT\TashaProject\tasha\backend"
python -m uvicorn main:app --reload
```

**You should see:**
```
INFO:     Uvicorn running on http://127.0.0.1:8000
Press CTRL+C to quit
```

### Step 3: Configure App
1. Open Tasha app in Flutter
2. Go to **Settings** tab
3. Set:
   - **Backend URL:** `http://localhost:8000`
   - **App Auth Token:** `test-app-token`

### Step 4: Open a Book
Click any medical book (e.g., "edliz 2020.txt")
- Wait 2-3 seconds for silent indexing
- Watch console for: `[VectorDB] Indexed book: edliz 2020`

### Step 5: Ask a Question
1. Go to **Chat** tab
2. Type a question:
   - "Tell me about TB prevention strategies"
   - "What are key antibiotic treatments?"
   - "How do I treat malaria?"

3. **WATCH CONSOLE** ← THIS IS KEY

---

## 📺 What You'll See in Console

### Level 1: Frontend Retrieves Chunks
```
[RagService][Retrieve] query="Tell me about TB prevention strategies" book=<all> topK=3
  #1 score=0.8542 book=edliz 2020 preview=TB preventive therapy includes...
  #2 score=0.7821 book=edliz 2020 preview=Antibiotic resistance is a major...
  #3 score=0.6543 book=National TB Guidelines preview=Key prevention strategies...
```

### Level 2: Frontend Normalizes & Counts
```
[RagService] ✅ NORMALIZED CHUNKS READY FOR OPENAI:
  Chunk[0] book="edliz 2020" page=15 text_length=845 preview="TB preventive therapy..."
  Chunk[1] book="edliz 2020" page=22 text_length=912 preview="Antibiotic resistance..."
  Chunk[2] book="National TB Guidelines" page=8 text_length=756 preview="Key prevention..."
✅ TOTAL TEXT CHARACTERS BEING SENT TO OPENAI: 2513 chars (from 3 chunks)
```

### Level 3: HTTP Client Sends to Backend
```
[BackendClient] 📤 RAG REQUEST - Sending 3 chunks to backend for question: "Tell me about TB prevention strategies?"
  📦 Chunk[0] book="edliz 2020" page=15 len=845 preview="TB preventive therapy..."
  📦 Chunk[1] book="edliz 2020" page=22 len=912 preview="Antibiotic resistance..."
  📦 Chunk[2] book="National TB Guidelines" page=8 len=756 preview="Key prevention..."
[BackendClient] ✅ TOTAL CHARS BEING SENT TO OPENAI: 2513 bytes
[BackendClient] POST /rag/answer success
[BackendClient] ✅ RAG RESPONSE RECEIVED: answer_length=312
```

### Level 4: Backend Receives Chunks (in backend console)
```
[RAG_ANSWER] 📥 RECEIVED FROM FRONTEND:
  Question: "Tell me about TB prevention strategies?"
  Chunk count: 3
  Total chars: 2513
  📦 Chunk[0] book="edliz 2020" page=15 len=845 preview="TB preventive therapy..."
  📦 Chunk[1] book="edliz 2020" page=22 len=912 preview="Antibiotic resistance..."
  📦 Chunk[2] book="National TB Guidelines" page=8 len=756 preview="Key prevention..."

[RAG_ANSWER] 📤 SENDING TO OPENAI:
  Model: gpt-4o-mini
  Max tokens: 1200
  System prompt length: 412 chars
  User message length: 3050 chars

[RAG_ANSWER] ✅ RESPONSE FROM OPENAI:
  Answer length: 312 chars
  Full answer: {"answer": "TB prevention strategies include: 1) Isoniazid preventive therapy for high-risk groups... 2) Contact investigation... 3) BCG vaccination..."}
```

### Level 5: App Displays Answer
```
App chat screen shows:

TB prevention strategies include:
• Isoniazid preventive therapy for high-risk groups, particularly those with diabetes
• Contact investigation and treatment of TB contacts
• BCG vaccination in high-burden settings
• Regular TB screening and symptom monitoring
```

---

## ✅ What This Proves

If you see ALL these logs:
- ✅ Chunks ARE retrieved from your books
- ✅ Chunks ARE normalized correctly  
- ✅ Chunks ARE sent to backend via HTTP
- ✅ Backend RECEIVES the chunks
- ✅ Backend SENDS chunks to OpenAI
- ✅ OpenAI RESPONDS with book-specific answer
- ✅ **App displays specific medical information, NOT generic response**

**Result: Bot now answers questions about your medical books!**

---

## ❌ If Something Fails

| Missing Log | Problem | Fix |
|----------|---------|-----|
| No `[RagService][Retrieve]` | Book not indexed | Open a book first, wait 3 sec |
| `topK=0` in retrieve | No chunks found | Check book was indexed |
| No `[BackendClient]` logs | Backend not running | Run `python -m uvicorn main:app --reload` |
| No `[RAG_ANSWER] 📥 RECEIVED` | Backend not connecting | Check Backend URL in Settings |
| No `[RAG_ANSWER] 📤 SENDING` | Backend error | Check backend console for error |
| No `✅ RESPONSE FROM OPENAI` | OpenAI key invalid | Check key is real, not placeholder |
| Generic answer in app | System prompt not working | Verify chunks ARE being sent |

---

## 📝 Files to Check

- **App logs:** VS Code Debug Console (when running Flutter)
- **Backend logs:** Terminal where you ran `python -m uvicorn main:app --reload`
- **Verify chunks sent:** Look for 📤 📥 ✅ emojis in logs

---

## 🎯 Summary

**Before:** Generic "I don't have access" response
**After:** "TB prevention strategies include isoniazid therapy, contact investigation, BCG vaccination..."

**You'll be able to see exactly where chunks go:**
Frontend → HTTP Client → Backend → OpenAI → Response → App

**No more mystery. Complete visibility.**

