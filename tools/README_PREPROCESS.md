Steps to preprocess PDFs into chunks and embeddings (manual helper):

1. Convert PDF to text (use `pdftotext` or a Python library like `pdfminer.six`).
2. Clean text and split into chunks of ~300-500 words with ~20% overlap.
3. For each chunk, compute an embedding (use OpenAI embeddings API or an offline model).
4. Insert each chunk and its embedding into the app database using the `VectorDB.insertChunk` utility. You can write a small Dart or Python script to do this, or add an import utility in the app.

Minimal Dart snippet (example):

// load chunk text and embedding
await VectorDB.insertChunk('MyBook', 1, 3, chunkText, embeddingList);

Note: embeddings produced by OpenAI are floats; the `VectorDB` stores them as blobs of float64 values.
