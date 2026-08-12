import 'package:archive/archive_io.dart';
import 'dart:io';

void main() {
  try {
    // Check if BZip2Encoder is available
    final encoder = BZip2Encoder();
    print('BZip2Encoder is available');
    
    final data = [1, 2, 3, 4, 5];
    final compressed = encoder.encode(data);
    print('Compressed size: ${compressed.length}');
    
  } catch (e) {
    print('Error: $e');
  }
}
