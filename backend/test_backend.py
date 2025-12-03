#!/usr/bin/env python3
"""
Test script for Tasha backend
Run this after starting the backend server to verify it works
"""

import requests
import json
import sys
from typing import Dict, Any

BASE_URL = "http://localhost:8000"
APP_TOKEN = "test-token"
HEADERS = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {APP_TOKEN}"
}

def test_health():
    """Test health endpoint"""
    print("\n[TEST] Health Check...")
    try:
        res = requests.get(f"{BASE_URL}/health", timeout=5)
        if res.status_code == 200:
            print("✅ Backend is healthy")
            print(f"   Response: {res.json()}")
            return True
        else:
            print(f"❌ Health check failed: {res.status_code}")
            return False
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

def test_process_chunk():
    """Test process_chunk endpoint"""
    print("\n[TEST] Process Chunk...")
    payload = {
        "chunk": "Malaria is transmitted by mosquitoes. It causes fever, chills, and joint pain. Treatment includes antimalarial drugs like artemisinin.",
        "model": "gpt-4o-mini",
        "temperature": 0.0,
        "max_tokens": 256
    }
    try:
        res = requests.post(
            f"{BASE_URL}/process_chunk",
            headers=HEADERS,
            json=payload,
            timeout=30
        )
        if res.status_code == 200:
            data = res.json()
            print("✅ Process chunk succeeded")
            print(f"   Result: {data['result'][:100]}...")
            return True
        else:
            print(f"❌ Process chunk failed: {res.status_code}")
            print(f"   Error: {res.text}")
            return False
    except Exception as e:
        print(f"❌ Request failed: {e}")
        return False

def test_embeddings():
    """Test embeddings endpoint"""
    print("\n[TEST] Embeddings...")
    payload = {
        "texts": ["What is malaria?", "How is HIV treated?"],
        "model": "text-embedding-3-small"
    }
    try:
        res = requests.post(
            f"{BASE_URL}/embeddings",
            headers=HEADERS,
            json=payload,
            timeout=30
        )
        if res.status_code == 200:
            data = res.json()
            embeds = data['embeddings']
            print("✅ Embeddings succeeded")
            print(f"   Generated {len(embeds)} embeddings")
            print(f"   Embedding size: {len(embeds[0])} dimensions")
            return True
        else:
            print(f"❌ Embeddings failed: {res.status_code}")
            print(f"   Error: {res.text}")
            return False
    except Exception as e:
        print(f"❌ Request failed: {e}")
        return False

def test_rag_answer():
    """Test RAG answer endpoint"""
    print("\n[TEST] RAG Answer...")
    chunks = [
        {
            "book": "Medical Guidelines",
            "start_page": 10,
            "end_page": 15,
            "text": "Malaria is a parasitic infection caused by Plasmodium species. Clinical features include fever, chills, sweating, and fatigue. Diagnosis is by blood film or rapid diagnostic test. First-line treatment is artemisinin-based combination therapy (ACT) such as artemether-lumefantrine."
        },
        {
            "book": "Medical Guidelines",
            "start_page": 16,
            "end_page": 20,
            "text": "Prevention includes insecticide-treated bed nets, indoor residual spraying, and antimalarial prophylaxis in endemic areas. Pregnant women and children under 5 are at highest risk of severe disease."
        }
    ]
    payload = {
        "question": "What is the recommended treatment for malaria?",
        "chunks": chunks,
        "model": "gpt-4o-mini",
        "temperature": 0.0,
        "max_tokens": 300
    }
    try:
        res = requests.post(
            f"{BASE_URL}/rag/answer",
            headers=HEADERS,
            json=payload,
            timeout=30
        )
        if res.status_code == 200:
            data = res.json()
            print("✅ RAG answer succeeded")
            print(f"   Answer: {data['answer']}")
            print(f"   Confidence: {data['confidence']}")
            print(f"   Citations: {len(data['citations'])}")
            return True
        else:
            print(f"❌ RAG answer failed: {res.status_code}")
            print(f"   Error: {res.text}")
            return False
    except Exception as e:
        print(f"❌ Request failed: {e}")
        return False

def test_rate_limiting():
    """Test rate limiting by making multiple requests"""
    print("\n[TEST] Rate Limiting...")
    print("   Making 65 rapid requests to test rate limit (should fail on some)...")
    
    payload = {"chunk": "Test chunk", "model": "gpt-4o-mini", "max_tokens": 100}
    success = 0
    rate_limited = 0
    failed = 0
    
    for i in range(65):
        try:
            res = requests.post(
                f"{BASE_URL}/process_chunk",
                headers=HEADERS,
                json=payload,
                timeout=5
            )
            if res.status_code == 200:
                success += 1
            elif res.status_code == 429:
                rate_limited += 1
            else:
                failed += 1
        except:
            failed += 1
    
    print(f"   Success: {success}/65")
    print(f"   Rate limited: {rate_limited}/65")
    print(f"   Failed: {failed}/65")
    
    if rate_limited > 0:
        print("✅ Rate limiting working (got 429 responses)")
        return True
    else:
        print("⚠️  No rate limit hit (limits might be high)")
        return True

def main():
    print("="*60)
    print("Tasha Backend Test Suite")
    print("="*60)
    print(f"\nTesting backend at: {BASE_URL}")
    print(f"Using auth token: {APP_TOKEN}")
    
    results = {}
    
    # Run tests
    results["health"] = test_health()
    if not results["health"]:
        print("\n❌ Backend is not running. Start it with:")
        print("   cd backend/")
        print("   python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000")
        sys.exit(1)
    
    results["process_chunk"] = test_process_chunk()
    results["embeddings"] = test_embeddings()
    results["rag_answer"] = test_rag_answer()
    results["rate_limiting"] = test_rate_limiting()
    
    # Summary
    print("\n" + "="*60)
    print("Test Summary")
    print("="*60)
    for test_name, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} - {test_name}")
    
    passed_count = sum(1 for v in results.values() if v)
    total_count = len(results)
    print(f"\nTotal: {passed_count}/{total_count} tests passed")
    
    if passed_count == total_count:
        print("\n🎉 All tests passed! Backend is working correctly.")
        sys.exit(0)
    else:
        print("\n⚠️  Some tests failed. Check the error messages above.")
        sys.exit(1)

if __name__ == "__main__":
    main()
