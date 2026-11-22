import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

enum ReportPhotoSource { camera, gallery }

class ProcessedReportPhoto {
  const ProcessedReportPhoto({required this.bytes, required this.width, required this.height, required this.byteLength});
  final Uint8List bytes;
  final int width, height, byteLength;
}

class PhotoProcessingFailure implements Exception {
  const PhotoProcessingFailure(this.message);
  final String message;
}

ProcessedReportPhoto compressReportPhotoBytes(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null || decoded.width < 1 || decoded.height < 1 || decoded.width * decoded.height > 16000000) {
      throw const PhotoProcessingFailure('Foto tidak valid atau melebihi 16 megapiksel.');
    }
    var image = img.bakeOrientation(decoded);
    if (image.width > 1024 || image.height > 1024) {
      image = image.width >= image.height ? img.copyResize(image, width: 1024) : img.copyResize(image, height: 1024);
    }
    image.exif.clear();
    final bytes = img.encodeJpg(image, quality: 75, chroma: img.JpegChroma.yuv420);
    if (bytes.length > 2097152) throw const PhotoProcessingFailure('Foto terkompresi melebihi 2 MiB.');
    return ProcessedReportPhoto(bytes: bytes, width: image.width, height: image.height, byteLength: bytes.length);
  } on PhotoProcessingFailure {
    rethrow;
  } catch (_) {
    throw const PhotoProcessingFailure('Foto tidak dapat diproses. Pilih foto lain.');
  }
}

abstract interface class ReportPhotoService {
  Future<ProcessedReportPhoto?> pickAndCompress(ReportPhotoSource source);
}

class ImagePickerReportPhotoService implements ReportPhotoService {
  @override
  Future<ProcessedReportPhoto?> pickAndCompress(ReportPhotoSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source == ReportPhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024, maxHeight: 1024, imageQuality: 75);
      if (file == null) return null;
      return await compute(compressReportPhotoBytes, await file.readAsBytes());
    } on PlatformException catch (error) {
      throw PhotoProcessingFailure(error.code.contains('denied') ? 'Izin kamera atau galeri ditolak.' : 'Kamera atau galeri tidak tersedia.');
    } on PhotoProcessingFailure {
      rethrow;
    } catch (_) {
      throw const PhotoProcessingFailure('Foto tidak dapat dibaca.');
    }
  }
}
