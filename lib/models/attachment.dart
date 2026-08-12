class Attachment {
  final int? id;
  final String ownerType;
  final int ownerId;
  final String filePath;
  final String fileType;
  final String? extractedText;
  final double? extractionConfidence;
  final DateTime uploadedAt;

  Attachment({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    required this.fileType,
    this.extractedText,
    this.extractionConfidence,
    required this.uploadedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_type': ownerType,
      'owner_id': ownerId,
      'file_path': filePath,
      'file_type': fileType,
      'extracted_text': extractedText,
      'extraction_confidence': extractionConfidence,
      'uploaded_at': uploadedAt.toIso8601String(),
    };
  }

  factory Attachment.fromMap(Map<String, dynamic> map) {
    return Attachment(
      id: map['id'],
      ownerType: map['owner_type'],
      ownerId: map['owner_id'],
      filePath: map['file_path'],
      fileType: map['file_type'],
      extractedText: map['extracted_text'],
      extractionConfidence: (map['extraction_confidence'] as num?)?.toDouble(),
      uploadedAt: DateTime.parse(map['uploaded_at']),
    );
  }
}
