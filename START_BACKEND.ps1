# Start Tasha Backend Server (PowerShell Version)
# This script sets the OpenAI key and starts the FastAPI backend

cd "C:\Users\TASHINGA\Desktop\PROJECT\TashaProject\tasha\backend"

# Set OpenAI API Key (replace with your real key)
$env:OPENAI_API_KEY = "sk-test-key"

Write-Host "Starting Tasha Backend Server..." -ForegroundColor Green
Write-Host ""
Write-Host "Backend will be available at:" -ForegroundColor Yellow
Write-Host "  Local:     http://localhost:8000" -ForegroundColor Cyan
Write-Host "  Network:   http://YOUR-COMPUTER-IP:8000" -ForegroundColor Cyan
Write-Host ""
Write-Host "To find your computer IP, run: ipconfig (look for IPv4 Address)"
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
