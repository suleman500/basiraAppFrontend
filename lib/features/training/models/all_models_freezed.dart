import 'package:flutter/foundation.dart';

@immutable
class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.label = '',
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String label;

  BoundingBox copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? label,
  }) {
    return BoundingBox(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      label: label ?? this.label,
    );
  }
}

@immutable
class TrainingImageItem {
  const TrainingImageItem({
    required this.id,
    required this.path,
    this.boxes = const [],
  });

  final String id;
  final String path;
  final List<BoundingBox> boxes;

  TrainingImageItem copyWith({
    String? id,
    String? path,
    List<BoundingBox>? boxes,
  }) {
    return TrainingImageItem(
      id: id ?? this.id,
      path: path ?? this.path,
      boxes: boxes ?? this.boxes,
    );
  }
}

@immutable
class TrainingCenterState {
  const TrainingCenterState({
    this.images = const [],
    this.selectedImageId,
    this.status = 'Ready to train',
  });

  final List<TrainingImageItem> images;
  final String? selectedImageId;
  final String status;

  TrainingCenterState copyWith({
    List<TrainingImageItem>? images,
    String? selectedImageId,
    String? status,
  }) {
    return TrainingCenterState(
      images: images ?? this.images,
      selectedImageId: selectedImageId ?? this.selectedImageId,
      status: status ?? this.status,
    );
  }
}
