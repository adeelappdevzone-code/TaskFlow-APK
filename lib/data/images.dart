import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Images are stored on Cloudinary (free plan, no card): the app uploads with
// an unsigned preset and saves only the image address (in a task's links, a
// chat message or the profile). Firebase Storage needs the paid plan.

const kCloudinaryCloud = 'voejff1h';
const kCloudinaryPreset = 'taskflow';

/// Largest file we upload (after the picker has shrunk it).
const kMaxImageBytes = 10 * 1024 * 1024;

/// An address of an uploaded image (ours, or any link to a picture file).
bool isImageUrl(String url) =>
    url.contains('res.cloudinary.com/') ||
    RegExp(r'\.(png|jpe?g|gif|webp)(\?.*)?$', caseSensitive: false).hasMatch(url);

/// A smaller copy for lists (Cloudinary resizes on the fly); other addresses
/// are used as they are.
String thumbUrl(String url, {int width = 480}) {
  const marker = '/image/upload/';
  if (!url.contains('res.cloudinary.com/') || !url.contains(marker)) return url;
  return url.replaceFirst(marker, '${marker}c_limit,w_$width,q_auto,f_auto/');
}

class ImageUploadError implements Exception {
  final String message;
  const ImageUploadError(this.message);
  @override
  String toString() => message;
}

/// Uploads [file] and returns its https address.
Future<String> uploadImage(XFile file, {http.Client? client}) async {
  final bytes = await file.readAsBytes();
  if (bytes.length > kMaxImageBytes) {
    throw const ImageUploadError('The image is too big (max 10 MB).');
  }
  final req = http.MultipartRequest(
      'POST', Uri.parse('https://api.cloudinary.com/v1_1/$kCloudinaryCloud/image/upload'))
    ..fields['upload_preset'] = kCloudinaryPreset
    ..files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: file.name.isEmpty ? 'image.jpg' : file.name));
  final c = client ?? http.Client();
  try {
    final res = await http.Response.fromStream(await c.send(req));
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body is Map && body['secure_url'] is String) {
      return body['secure_url'] as String;
    }
    final msg = body is Map && body['error'] is Map ? body['error']['message'] : null;
    throw ImageUploadError('Upload failed${msg is String ? ': $msg' : ''}.');
  } on ImageUploadError {
    rethrow;
  } catch (_) {
    throw const ImageUploadError('Upload failed. Check your internet and try again.');
  } finally {
    if (client == null) c.close();
  }
}
