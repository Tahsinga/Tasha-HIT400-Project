# 📋 Tasha Bot Modernization Checklist

Use this checklist to track your progress through the setup and deployment.

---

## Phase 1: Backend Setup (15 minutes)

### Prerequisites
- [ ] Python 3.8+ installed (`python --version`)
- [ ] OpenAI API key obtained (from https://platform.openai.com/)
- [ ] Terminal/PowerShell open in project root

### Backend Installation
- [ ] Navigate to backend folder: `cd backend/`
- [ ] Install dependencies: `pip install -r requirements.txt`
- [ ] Copy environment template: `cp .env.example .env`
- [ ] Edit `.env` file and add `OPENAI_API_KEY=sk-...`
- [ ] Verify key is set: `python -c "import os; print(os.getenv('OPENAI_API_KEY'))"`

### Backend Verification
- [ ] Start backend: `python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000`
- [ ] See "Uvicorn running on http://0.0.0.0:8000"
- [ ] In new terminal, test: `python test_backend.py`
- [ ] All 5 tests pass ✅

```
✅ PASS - health
✅ PASS - process_chunk
✅ PASS - embeddings
✅ PASS - rag_answer
✅ PASS - rate_limiting
```

---

## Phase 2: Flutter App Update (20 minutes)

### Preparation
- [ ] Read `MIGRATION_GUIDE.md` carefully
- [ ] Have `lib/main.dart` open in editor
- [ ] Backend is still running from Phase 1

### Code Updates
- [ ] Add imports at top of `lib/main.dart`:
  ```dart
  import 'services/backend_config.dart';
  import 'services/backend_client.dart';
  ```
- [ ] Find first `EmbeddingService(key)` instantiation
- [ ] Replace with pattern from `MIGRATION_GUIDE.md`
- [ ] Find first `RagService(embSvc)` instantiation
- [ ] Replace with pattern from `MIGRATION_GUIDE.md`
- [ ] Repeat for all ~5 occurrences in file
- [ ] Remove any direct `trainBookWithOpenAI(..., key)` calls (remove `key` parameter)

### Build Verification
- [ ] Run: `flutter pub get`
- [ ] Run: `flutter analyze` (check for errors)
- [ ] No compilation errors
- [ ] No missing imports or undefined symbols

### Run App
- [ ] Run: `flutter run`
- [ ] App starts without crashing
- [ ] No "BackendConfig not found" errors
- [ ] App loads successfully

---

## Phase 3: Configuration (5 minutes)

### App Settings
- [ ] Open app Settings screen
- [ ] Find "Backend Configuration" section (may need to add)
- [ ] Enter Backend URL: `http://localhost:8000`
- [ ] Enter App Auth Token: `test` (anything works locally)
- [ ] Tap Save / OK
- [ ] Settings persist after restart

### Verification
- [ ] Close and reopen app
- [ ] Check Settings, values still there

---

## Phase 4: Testing (10 minutes)

### Chat Functionality
- [ ] Open Chat (RAG) page
- [ ] Type test question: "What is malaria?"
- [ ] Tap Send / Ask button
- [ ] Get response within 3 seconds
- [ ] **NO UI FREEZE** ✅
- [ ] Response text appears

### Backend Logs
- [ ] Keep backend terminal visible
- [ ] Look for `[RagService]` messages
- [ ] Should see:
  ```
  [RagService] Calling backend RAG for question...
  [RagService] success user=...
  ```
- [ ] No `[ERROR]` messages

### Multiple Questions
- [ ] Ask 5 different questions
- [ ] Each responds in ~2-3 seconds
- [ ] No app freezes at any point
- [ ] All responses make sense

### Offline Functionality
- [ ] (Optional) Stop backend: Ctrl+C in backend terminal
- [ ] Try asking a question in app
- [ ] Should see offline fallback message
- [ ] App doesn't crash
- [ ] Restart backend: `python -m uvicorn main:app --reload`

---

## Phase 5: Advanced Testing (10 minutes)

### Indexing (Training) Books
- [ ] Go to Library page
- [ ] Select a book
- [ ] Tap "Index book" or "Train"
- [ ] Should see progress indicator
- [ ] Completes without freezing
- [ ] Check backend logs for batch processing

### Embeddings
- [ ] Make sure chunks are indexed
- [ ] Ask a question
- [ ] Check backend shows `[EmbeddingService]` logs
- [ ] Embeddings are generated and used

### Rate Limiting
- [ ] Ask 65 questions rapidly (use a loop or spam tap)
- [ ] Some requests should be rate-limited
- [ ] App shows error gracefully
- [ ] Backend logs show `Rate limit exceeded`

---

## Phase 6: Production Preparation (Optional)

### Before Going Live
- [ ] [ ] Create production `.env` file (don't commit!)
- [ ] [ ] Set strong `APP_AUTH_TOKEN`
- [ ] [ ] Review backend logs and costs
- [ ] [ ] Test with real documents
- [ ] [ ] Verify answer quality

### Deployment Choice (Pick One)
- [ ] **Railway:** Recommended for easy deployment
- [ ] **Render:** Good free tier
- [ ] **AWS Lambda:** For advanced users
- [ ] **Your Server:** For full control

### If Using Railway
- [ ] [ ] Create Railway.app account
- [ ] [ ] Install Railway CLI: `npm install -g @railway/cli`
- [ ] [ ] Login: `railway login`
- [ ] [ ] Init: `railway init` (select backend folder)
- [ ] [ ] Add secret: `railway variables add OPENAI_API_KEY=sk-...`
- [ ] [ ] Deploy: `railway up`
- [ ] [ ] Get URL: `railway domains`
- [ ] [ ] Update app Settings with production URL

### Update App for Production
- [ ] [ ] Update Settings:
  - [ ] Backend URL: `https://your-app.railway.app` (or your URL)
  - [ ] App Auth Token: (your production token)
- [ ] [ ] Rebuild app
- [ ] [ ] Test with production backend
- [ ] [ ] Verify no freezing with production server

---

## Phase 7: Monitoring (Ongoing)

### Weekly
- [ ] [ ] Check OpenAI usage/costs: https://platform.openai.com/account/usage
- [ ] [ ] Review backend logs for errors
- [ ] [ ] Ask 10 test questions, verify quality

### Monthly
- [ ] [ ] Optimize prompts if needed
- [ ] [ ] Review rate limit effectiveness
- [ ] [ ] Check for security issues
- [ ] [ ] Update dependencies: `pip install --upgrade -r requirements.txt`

### Cost Management
- [ ] [ ] Set spending limit in OpenAI dashboard
- [ ] [ ] Monitor tokens per request
- [ ] [ ] Consider cheaper models if costs high
- [ ] [ ] Enable caching for popular queries

---

## Troubleshooting Checklist

### Backend Won't Start
- [ ] Check Python: `python --version` (need 3.8+)
- [ ] Check dependencies: `pip list | grep fastapi`
- [ ] Check `.env`: `cat backend/.env` (must have OPENAI_API_KEY)
- [ ] Check port 8000 is free: (no other app using it)

### App Won't Connect
- [ ] Backend is running: `python -m uvicorn main:app --reload`
- [ ] Backend URL in Settings: `http://localhost:8000`
- [ ] Test backend: `python test_backend.py` (all pass)
- [ ] Check Flutter logs: `flutter logs` (look for errors)
- [ ] App auth token is set (can be "test" locally)

### Freezing Still Happens
- [ ] Check `main.dart` updates were applied correctly
- [ ] Look for missed `EmbeddingService(key)` instances
- [ ] Verify `RagService(embSvc, backend)` has both parameters
- [ ] Rebuild: `flutter pub get && flutter run`
- [ ] Check backend is responding: `curl http://localhost:8000/health`

### No Answers Returned
- [ ] Check OpenAI key is valid in `.env`
- [ ] Check backend logs for errors
- [ ] Run `python test_backend.py` to verify setup
- [ ] Try shorter questions first
- [ ] Check chunks are being loaded (debug logs)

### High Costs
- [ ] Reduce `max_tokens` in `backend/main.py` (600 → 300)
- [ ] Use `gpt-4o-mini` (not `gpt-4`)
- [ ] Reduce `topK` chunks (5 → 3)
- [ ] Cache responses for common questions

---

## Success Criteria ✅

Your modernization is **COMPLETE** when:

- ✅ Backend runs locally without errors
- ✅ `test_backend.py` passes all 5 tests
- ✅ Flutter app builds without errors
- ✅ App connects to backend (no "connection refused")
- ✅ Can ask a question and get answer in 2-3 seconds
- ✅ **NO UI FREEZING** during any operation
- ✅ Multiple questions work reliably
- ✅ Backend handles training/indexing smoothly
- ✅ Rate limiting works (some requests blocked after 60/min)
- ✅ Offline fallback works (if backend stops)
- ✅ Logs show `[RagService]` activity

---

## Next Milestones 🎯

### Milestone 1: Local Working ✅
- [ ] Completed all Phases 1-4 above

### Milestone 2: Production Ready
- [ ] Phase 6 choices made
- [ ] Backend deployed to Railway/Render/AWS
- [ ] App configured with production URL
- [ ] Production testing passed

### Milestone 3: Optimized
- [ ] Prompts tuned for medical domain
- [ ] Answer quality verified
- [ ] Costs optimized
- [ ] Monitoring set up

### Milestone 4: Scale
- [ ] Multiple users testing
- [ ] Load testing done
- [ ] Cache implemented
- [ ] Analytics enabled

---

## Resources

📚 **Start here:**
- `COMPLETE_SETUP_GUIDE.md` — Full overview
- `MIGRATION_GUIDE.md` — Updating main.dart
- `BACKEND_SETUP.md` — Backend only

🔧 **Reference:**
- `backend/README.md` — Backend documentation
- `IMPLEMENTATION_SUMMARY.md` — Architecture deep-dive
- `MODERNIZATION_COMPLETE.md` — Full feature summary

🚀 **Deployment:**
- Railway: https://railway.app/
- Render: https://render.com/
- AWS: https://aws.amazon.com/

---

## Questions?

1. **Backend issues?** → Check `backend/README.md`
2. **Flutter issues?** → Check `MIGRATION_GUIDE.md`
3. **General setup?** → Check `COMPLETE_SETUP_GUIDE.md`
4. **Still stuck?** → Review Phase that's failing and check logs

---

**Last Updated:** December 1, 2025
**Status:** Ready for deployment ✅

Good luck! 🚀
