import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/constants.dart';
import '../models/all_models_freezed.dart';

class TrainingServer {
  Future<void> uploadImage(
    File imageFile,
    String label,
    BoundingBox box,
  ) async {
    final imageBytes = await imageFile.readAsBytes();
    final response = await http.post(
      Uri.parse('${AppConstants.serverBaseUrl}${AppConstants.uploadEndpoint}'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'filename': imageFile.path.split(Platform.pathSeparator).last,
        'image': base64Encode(imageBytes),
        'annotations': [
          {
            'x': box.x,
            'y': box.y,
            'width': box.width,
            'height': box.height,
            'label': label,
          },
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Upload failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse(AppConstants.serverBaseUrl),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } on IOException {
      return false;
    }
  }
}
