import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> downloadTextFileImpl({
  required String filename,
  required String content,
  required String contentType,
}) async {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: contentType),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(objectUrl);
}
