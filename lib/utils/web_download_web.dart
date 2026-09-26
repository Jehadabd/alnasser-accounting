import 'dart:html' as html;
import 'dart:typed_data';

void downloadFileInBrowser(Uint8List bytes, String fileName, {String mimeType = 'application/octet-stream'}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

void downloadUrlInBrowser(String url, String fileName) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
}
