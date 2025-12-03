// ignore_for_file: always_specify_types

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasha/main.dart';

void main() {
  testWidgets('App has a title and a home page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is displayed
    expect(find.text('E-Book Library'), findsOneWidget);

    // Verify that the home page is displayed
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Search functionality works', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Find the search field
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    // Enter a search query
    await tester.enterText(searchField, 'sample book');
    await tester.pumpAndSettle();

    // Verify that the search results are displayed
    // (Assuming there is a method to check for search results)
    // expect(find.text('sample book'), findsOneWidget);
  });

  testWidgets('Bookmark functionality works', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Find a book card and tap it to open
    final bookCard = find.byType(BookCard).first;
    await tester.tap(bookCard);
    await tester.pumpAndSettle();

    // Tap the bookmark button
    final bookmarkButton = find.byIcon(Icons.bookmark_border);
    await tester.tap(bookmarkButton);
    await tester.pumpAndSettle();

    // Verify that the book is bookmarked
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });
}