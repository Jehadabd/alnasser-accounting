import 'package:lzma/lzma.dart';

void main() {
  try {
    final input = [1, 2, 3, 4, 5];
    // Attempt 1: Top-level function
    // final compressed = encode(input); 
    // print('Top-level encode found');

    // Attempt 2: Static method on class
    final compressed2 = lzma.encode(input);
    print('lzma.encode found');
    
  } catch (e) {
    print('Error: $e');
  }
}
