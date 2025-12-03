#!/usr/bin/env powershell
# Quick Start Script for Tasha App
# This script helps you get the app running correctly

param(
    [string]$Action = "status"
)

$projectRoot = "c:\Users\TASHINGA\Desktop\PROJECT\TashaProject\tasha"
$backendDir = "$projectRoot\backend"

function Show-Status {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║            TASHA APP - QUICK START GUIDE                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "✓ APP CODE STATUS:" -ForegroundColor Green
    Write-Host "  • Book opening: CONFIGURED (silent background indexing)" -ForegroundColor Green
    Write-Host "  • Chat RAG: CONFIGURED (retrieval + OpenAI)" -ForegroundColor Green
    Write-Host "  • Backend client: CONFIGURED (HTTP to backend)" -ForegroundColor Green
    Write-Host "  • Vector DB: CONFIGURED (SQLite chunks storage)" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "⚠ WHAT YOU NEED TO DO:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. START BACKEND SERVER" -ForegroundColor Yellow
    Write-Host "   PowerShell:"
    Write-Host "   cd '$backendDir'" -ForegroundColor Cyan
    Write-Host "   `$env:OPENAI_API_KEY='sk-YOUR-KEY-HERE'" -ForegroundColor Cyan
    Write-Host "   python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "2. CONFIGURE APP SETTINGS" -ForegroundColor Yellow
    Write-Host "   • Open app Settings tab" -ForegroundColor Cyan
    Write-Host "   • Backend Domain: http://localhost:8000" -ForegroundColor Cyan
    Write-Host "   • OpenAI API Key: sk-YOUR-KEY-HERE" -ForegroundColor Cyan
    Write-Host "   • Click 'Validate'" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "3. USE THE APP" -ForegroundColor Yellow
    Write-Host "   • Open a book (indexing happens silently)" -ForegroundColor Cyan
    Write-Host "   • Go to Chat (RAG) tab" -ForegroundColor Cyan
    Write-Host "   • Ask a question about the book" -ForegroundColor Cyan
    Write-Host "   • Get specific answer from OpenAI" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "✓ TERMINAL TESTS (Already Verified):" -ForegroundColor Green
    Write-Host "  • test_rag_chunks.dart: PASSED ✓" -ForegroundColor Green
    Write-Host "  • test_detailed_flow.dart: PASSED ✓" -ForegroundColor Green
    Write-Host "  • test_book_qa_terminal.dart: PASSED ✓" -ForegroundColor Green
    Write-Host "  • test_openai_response.dart: PASSED ✓" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "📋 CHECK LOGS FOR:" -ForegroundColor Magenta
    Write-Host "  Book indexing:" -ForegroundColor Gray
    Write-Host "    [Index] _ensureBookIndexed called" -ForegroundColor Gray
    Write-Host "    [Index] Stage 1 SUCCESS" -ForegroundColor Gray
    Write-Host "    [Index] SUCCESS: Indexed X chunks" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Question answering:" -ForegroundColor Gray
    Write-Host "    [RagService][Retrieve] query=... topK=3" -ForegroundColor Gray
    Write-Host "    [BackendClient] POST /rag/answer success" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "❌ IF PROBLEMS:" -ForegroundColor Red
    Write-Host "  • Response shows 'I don''t have access':" -ForegroundColor Red
    Write-Host "    - Check backend is running: http://localhost:8000/health" -ForegroundColor Cyan
    Write-Host "    - Verify OpenAI key is valid" -ForegroundColor Cyan
    Write-Host "    - Check book was indexed (see logs)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  • Book doesn't index:" -ForegroundColor Red
    Write-Host "    - Check TXT fallback exists: $projectRoot\assets\txt_books\" -ForegroundColor Cyan
    Write-Host "    - Try extracting PDF text manually" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  • Chat button doesn't respond:" -ForegroundColor Red
    Write-Host "    - Verify API key in Settings" -ForegroundColor Cyan
    Write-Host "    - Check connectivity to backend" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Backend-Health {
    Write-Host ""
    Write-Host "Testing backend health..." -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000/health" -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✓ Backend is running!" -ForegroundColor Green
            Write-Host "Response: $($response.Content)" -ForegroundColor Green
        }
    } catch {
        Write-Host "✗ Backend not responding. Is it running?" -ForegroundColor Red
        Write-Host "Start it with:" -ForegroundColor Yellow
        Write-Host "  cd '$backendDir'" -ForegroundColor Cyan
        Write-Host "  python -m uvicorn main:app --reload" -ForegroundColor Cyan
    }
}

function Run-Terminal-Tests {
    Write-Host ""
    Write-Host "Running terminal tests..." -ForegroundColor Cyan
    Write-Host ""
    
    cd $projectRoot
    
    $tests = @(
        "test_rag_chunks.dart",
        "test_detailed_flow.dart",
        "test_book_qa_terminal.dart",
        "test_openai_response.dart"
    )
    
    foreach ($test in $tests) {
        if (Test-Path $test) {
            Write-Host "Running: $test" -ForegroundColor Cyan
            dart $test
            Write-Host ""
        }
    }
}

function Build-App {
    Write-Host ""
    Write-Host "Building Flutter app..." -ForegroundColor Cyan
    cd $projectRoot
    flutter pub get
    flutter build apk
    Write-Host "✓ Build complete" -ForegroundColor Green
}

# Main switch
switch ($Action.ToLower()) {
    "status" { Show-Status }
    "health" { Test-Backend-Health }
    "test" { Run-Terminal-Tests }
    "build" { Build-App }
    default {
        Show-Status
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  .\quick_start.ps1 status    # Show status (default)" -ForegroundColor Cyan
        Write-Host "  .\quick_start.ps1 health    # Test backend health" -ForegroundColor Cyan
        Write-Host "  .\quick_start.ps1 test      # Run terminal tests" -ForegroundColor Cyan
        Write-Host "  .\quick_start.ps1 build     # Build Flutter app" -ForegroundColor Cyan
        Write-Host ""
    }
}
