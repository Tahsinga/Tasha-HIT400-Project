#!/usr/bin/env python3
"""
Test script: Verify end-to-end RAG + OpenAI flow.
- Sends a sample question + chunks to the backend
- Backend retrieves similar chunks and calls OpenAI
- Verifies response is NOT "no relevant information" or similar
"""

import requests
import json
import time

# Configuration
OPENAI_API_KEY = "sk-proj-your-api-key-here"  # Set via environment variable OPENAI_API_KEY
BACKEND_URL = "http://localhost:8000"
BOOK_NAME = "Zimbabwe Malaria Treatment Guidelines 2015.pdf"

# Sample chunks that might be from the book
SAMPLE_CHUNKS = [
    "Malaria is a parasitic infection transmitted by Anopheles mosquitoes. Treatment depends on the type of malaria parasite and local drug resistance patterns.",
    "First-line treatment for uncomplicated malaria in Zimbabwe: Artemisinin-based combination therapy (ACT). Recommended: artemether-lumefantrine or artesunate-amodiaquine.",
    "Severe malaria treatment: IV artesunate or IV artemether followed by oral ACT when tolerated. Follow-up with complete course of oral anti-malarial.",
    "Pregnancy and malaria: Use safe anti-malarials. First trimester: quinine or ACT. Later trimesters: any ACT. Always treat to prevent severe malaria.",
    "Drug resistance: Chloroquine resistance is widespread. Use ACT-based regimens. Monitor for artemisinin resistance in endemic areas.",
    "Malaria prophylaxis for travelers: Atovaquone-proguanil, doxycycline, or mefloquine depending on destination and resistance patterns.",
]

def test_rag_openai():
    print("=" * 80)
    print("TEST: RAG Pipeline + OpenAI Integration")
    print("=" * 80)
    print()

    # Test 1: Verify backend is reachable
    print("[TEST 1] Checking backend connectivity...")
    try:
        resp = requests.get(f"{BACKEND_URL}/", timeout=5)
        print(f"  ✓ Backend is reachable (status={resp.status_code})")
    except Exception as e:
        print(f"  ✗ Backend NOT reachable: {e}")
        print("  → Make sure backend is running: `python backend/main.py`")
        return

    print()

    # Test 2: Test /embeddings endpoint
    print("[TEST 2] Testing /embeddings endpoint...")
    try:
        payload = {
            "texts": ["treatment for malaria"],
            "model": "text-embedding-3-small"
        }
        resp = requests.post(
            f"{BACKEND_URL}/embeddings",
            json=payload,
            timeout=10
        )
        if resp.status_code == 200:
            data = resp.json()
            print(f"  ✓ /embeddings returned embeddings (dim={len(data.get('embeddings', [[]])[0])})")
        else:
            print(f"  ✗ /embeddings failed (status={resp.status_code}): {resp.text}")
    except Exception as e:
        print(f"  ✗ /embeddings error: {e}")

    print()

    # Test 3: Test RAG answer endpoint
    print("[TEST 3] Testing /rag/answer endpoint...")
    try:
        payload = {
            "question": "What is the first-line treatment for uncomplicated malaria?",
            "chunks": SAMPLE_CHUNKS[:3],  # Send first 3 chunks
            "book_name": BOOK_NAME,
            "openai_api_key": OPENAI_API_KEY
        }
        print(f"  Question: {payload['question']}")
        print(f"  Chunks: {len(payload['chunks'])} sample chunks")
        print(f"  Sending request...")

        resp = requests.post(
            f"{BACKEND_URL}/rag/answer",
            json=payload,
            timeout=30
        )

        if resp.status_code == 200:
            data = resp.json()
            answer = data.get("answer", "")
            print(f"  ✓ /rag/answer succeeded")
            print(f"    Answer length: {len(answer)} chars")
            print(f"    Answer preview: {answer[:200]}...")
            print()

            # Check if answer is generic "no relevant info" response
            no_answer_phrases = [
                "don't have access",
                "cannot find",
                "not available",
                "no relevant",
                "no information",
                "unable to",
                "cannot answer",
            ]
            is_generic = any(phrase.lower() in answer.lower() for phrase in no_answer_phrases)

            if is_generic:
                print(f"  ⚠ WARNING: Answer looks generic/unhelpful (may indicate chunk retrieval issue)")
            else:
                print(f"  ✓ Answer looks specific and helpful ✓")

            print()
            print("  Full Answer:")
            print("  " + "-" * 76)
            for line in answer.split('\n'):
                print(f"  {line}")
            print("  " + "-" * 76)
        else:
            print(f"  ✗ /rag/answer failed (status={resp.status_code})")
            print(f"    Response: {resp.text[:500]}")

    except Exception as e:
        print(f"  ✗ /rag/answer error: {e}")

    print()

    # Test 4: Test with empty chunks (should still return an answer via fallback)
    print("[TEST 4] Testing /rag/answer with NO chunks (fallback test)...")
    try:
        payload = {
            "question": "What is malaria?",
            "chunks": [],  # Empty chunks - should trigger fallback
            "book_name": BOOK_NAME,
            "openai_api_key": OPENAI_API_KEY
        }
        print(f"  Question: {payload['question']}")
        print(f"  Chunks: NONE (testing fallback)")
        print(f"  Sending request...")

        resp = requests.post(
            f"{BACKEND_URL}/rag/answer",
            json=payload,
            timeout=30
        )

        if resp.status_code == 200:
            data = resp.json()
            answer = data.get("answer", "")
            print(f"  ✓ /rag/answer succeeded with fallback")
            print(f"    Answer length: {len(answer)} chars")
            print(f"    Answer preview: {answer[:150]}...")
        else:
            print(f"  ✗ /rag/answer failed (status={resp.status_code})")

    except Exception as e:
        print(f"  ✗ /rag/answer error: {e}")

    print()
    print("=" * 80)
    print("TEST COMPLETE")
    print("=" * 80)
    print()
    print("Summary:")
    print("  1. If all tests pass with specific answers, RAG pipeline is working ✓")
    print("  2. If /rag/answer returns generic 'no relevant info', check:")
    print("     - Backend system prompt (should force answers)")
    print("     - Chunk quality/relevance")
    print("     - OpenAI API key validity")
    print()

if __name__ == "__main__":
    test_rag_openai()
