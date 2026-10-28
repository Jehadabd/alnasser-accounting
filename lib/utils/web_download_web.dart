import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadFileInBrowser(Uint8List bytes, String fileName, {String mimeType = 'application/octet-stream'}) {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}

void downloadUrlInBrowser(String url, String fileName) {
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
}
