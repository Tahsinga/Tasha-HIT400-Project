// test_asset_copy.dart
// Quick test to verify asset loading logic works
import 'dart:io';
import 'dart:convert';

void main() async {
  print('[TEST] Starting asset copy simulation...\n');

  // Simulate app documents directory (use temp for testing)
  final tempDir = Directory.systemTemp;
  final appDir = Directory('${tempDir.path}/tasha_test_books');
  
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
  print('[TEST] Using test app directory: ${appDir.path}');

  final pdfDir = Directory('${appDir.path}/BooksSource');
  if (!await pdfDir.exists()) {
    await pdfDir.create(recursive: true);
    print('[TEST] Created BooksSource dir: ${pdfDir.path}');
  }

  // Declared assets from pubspec.yaml
  final declaredPdfAssets = <String>[
    'assets/BooksSource/edliz 2020.pdf',
    'assets/BooksSource/Guidelines-for-HIV-Prevention-Testing-and-Treatment-of-HIV-in-Zimbabwe-August-2022-1.pdf',
    'assets/BooksSource/National TB and Leprosy Guidelines_FINAL 2023_Signed.pdf',
    'assets/BooksSource/Zimbabwe Malaria Treatment Guidelines 2015.pdf',
  ];

  // Check if assets exist in the project's assets folder
  final projectDir = Directory.current;
  print('\n[TEST] Current project directory: ${projectDir.path}');
  
  final assetsFolder = Directory('${projectDir.path}/assets/BooksSource');
  print('[TEST] Looking for assets in: ${assetsFolder.path}');

  if (!await assetsFolder.exists()) {
    print('[TEST] ❌ assets/BooksSource folder DOES NOT EXIST');
    print('[TEST] Expected: ${assetsFolder.path}');
    return;
  }

  print('[TEST] ✓ assets/BooksSource folder EXISTS\n');

  // List all files in assets/BooksSource
  final files = assetsFolder.listSync();
  print('[TEST] Files in assets/BooksSource (${files.length} total):');
  for (var f in files) {
    final fileName = f.path.split(Platform.pathSeparator).last;
    if (f is File) {
      final sizeKb = (await f.length()) / 1024;
      print('  ✓ $fileName (${sizeKb.toStringAsFixed(1)} KB)');
    }
  }

  // Simulate copying PDFs
  print('\n[TEST] Simulating asset copy to app documents...');
  int copied = 0;
  for (var assetPath in declaredPdfAssets) {
    final fileName = assetPath.split('/').last;
    final srcPath = '${projectDir.path}/$assetPath';
    final src = File(srcPath);
    
    if (await src.exists()) {
      final dest = File('${pdfDir.path}${Platform.pathSeparator}$fileName');
      if (!await dest.exists()) {
        try {
          await src.copy(dest.path);
          copied++;
          final sizeKb = (await dest.length()) / 1024;
          print('[TEST] ✓ Copied: $fileName (${sizeKb.toStringAsFixed(1)} KB)');
        } catch (e) {
          print('[TEST] ❌ Failed to copy $fileName: $e');
        }
      } else {
        print('[TEST] ⊘ Already exists: $fileName');
      }
    } else {
      print('[TEST] ❌ Source not found: $srcPath');
    }
  }

  // List final results
  print('\n[TEST] Final contents of simulated app documents/BooksSource:');
  final finalFiles = pdfDir.listSync();
  print('[TEST] Found ${finalFiles.length} files:');
  for (var f in finalFiles) {
    if (f is File) {
      final fileName = f.path.split(Platform.pathSeparator).last;
      final sizeKb = (await f.length()) / 1024;
      print('  ✓ $fileName (${sizeKb.toStringAsFixed(1)} KB)');
    }
  }

  print('\n[TEST] ✓ Test complete. Copied $copied books.');
  print('[TEST] Test app documents location: ${appDir.path}');
}
