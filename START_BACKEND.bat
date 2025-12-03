@echo off
REM Start Tasha Backend Server
REM This script sets the OpenAI key and starts the FastAPI backend

cd /d "C:\Users\TASHINGA\Desktop\PROJECT\TashaProject\tasha\backend"

REM Set OpenAI API Key (replace with your real key)
set OPENAI_API_KEY=sk-test-key

REM Start backend server
echo Starting Tasha Backend Server...
echo Backend will be available at:
echo   Local:     http://localhost:8000
echo   Network:   http://YOUR-COMPUTER-IP:8000
echo.
echo Press Ctrl+C to stop the server
echo.

python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

pause
