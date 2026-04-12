import 'download_text_file_stub.dart'
    if (dart.library.js_interop) 'download_text_file_web.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
  required String contentType,
}) {
  return downloadTextFileImpl(
    filename: filename,
    content: content,
    contentType: contentType,
  );
}
