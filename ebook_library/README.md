# E-Book Library

## Overview
The E-Book Library is a Flutter application that allows users to manage and read their e-books in PDF format. The app provides features for searching, bookmarking, and interacting with a chatbot for querying information about the books.

## Features
- **PDF Viewer**: Read and navigate through PDF documents.
- **Search Functionality**: Quickly find books by title.
- **Bookmarking**: Save your favorite books for easy access.
- **Chatbot Integration**: Ask questions about the books and get responses.

## Project Structure
```
ebook_library
├── android                # Android-specific files
│   └── app
│       └── build.gradle   # Gradle build configuration for the Android app
├── ios                    # iOS-specific files
│   └── Runner
├── lib                    # Main application code
│   ├── main.dart          # Entry point of the Flutter application
│   ├── services           # Service classes for various functionalities
│   │   ├── vector_db.dart # Vector database operations
│   │   ├── embedding_service.dart # Embedding generation
│   │   ├── rag_service.dart # Retrieval-augmented generation
│   │   └── index_worker.dart # Background indexing tasks
│   ├── widgets            # UI components
│   │   ├── book_card.dart # Widget for displaying book cards
│   │   ├── pdf_viewer_page.dart # Widget for PDF viewing
│   │   └── chat_dialog.dart # Chatbot interaction dialog
│   └── models             # Data models
│       └── index.dart     # Data structures for book data
├── test                   # Test files
│   └── widget_test.dart   # Widget tests for the application
├── pubspec.yaml           # Flutter project configuration
├── analysis_options.yaml   # Dart analysis options
└── README.md              # Project documentation
```

## Setup Instructions
1. Clone the repository:
   ```
   git clone <repository-url>
   ```
2. Navigate to the project directory:
   ```
   cd ebook_library
   ```
3. Install dependencies:
   ```
   flutter pub get
   ```
4. Run the application:
   ```
   flutter run
   ```

## Usage
- Open the app to view your library of e-books.
- Use the search bar to find specific titles.
- Tap on a book card to open the PDF viewer.
- Bookmark your favorite books for quick access.
- Interact with the chatbot for assistance with your books.

## Contributing
Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.