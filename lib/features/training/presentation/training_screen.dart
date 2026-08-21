import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/all_models_freezed.dart';
import '../services/training_server.dart';
import 'training_functions.dart';

enum EditMode { move, resize }

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  static const _background = Color(0xff0f0f1a);
  static const _surface = Color(0xff181827);
  static const _blue = Color(0xff2e86ab);
  static const _green = Color(0xff4caf50);
  static const _orange = Color(0xffe67e22);

  final ImagePicker _picker = ImagePicker();
  final TrainingServer _server = TrainingServer();
  final Map<String, TextEditingController> _coordinateControllers = {};
  final TextEditingController _customClassController = TextEditingController();
  TrainingCenterState _state = const TrainingCenterState();
  bool _isHighContrast = true;
  bool _isBoxInteracting = false;
  bool _isHandleDragging = false;
  bool _isUploading = false;
  EditMode _editMode = EditMode.move;
  BoundingBox? _gestureStartBox;
  final Set<String> _uploadedImageIds = <String>{};

  @override
  void dispose() {
    _customClassController.dispose();
    for (final controller in _coordinateControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage(imageQuality: 80);
    if (!mounted || images.isEmpty) return;
    final selectedLabel = sanitizeLabel(_customClassController.text);

    final newItems = images.map((image) {
      return TrainingImageItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${image.name}',
        path: image.path,
        boxes: [
          BoundingBox(
            x: .18,
            y: .2,
            width: .48,
            height: .42,
            label: selectedLabel,
          ),
        ],
      );
    }).toList();

    setState(() {
      _state = _state.copyWith(
        images: [..._state.images, ...newItems],
        selectedImageId: newItems.first.id,
        status: 'تمت إضافة ${newItems.length} صورة إلى الجلسة',
      );
    });
  }

  void _selectImage(TrainingImageItem image) {
    setState(() {
      final selectedImage = image.boxes.isEmpty ? _addDefaultBox(image) : image;
      final images = _state.images
          .map((item) => item.id == selectedImage.id ? selectedImage : item)
          .toList();
      _state = _state.copyWith(
        images: images,
        selectedImageId: selectedImage.id,
      );
    });
  }

  TrainingImageItem _addDefaultBox(TrainingImageItem image) {
    final label = sanitizeLabel(_customClassController.text);
    return image.copyWith(
      boxes: [
        BoundingBox(
          x: .18,
          y: .2,
          width: .48,
          height: .42,
          label: label.isEmpty ? 'object' : label,
        ),
      ],
    );
  }

  void _deleteImage(TrainingImageItem image) {
    final images = _state.images.where((item) => item.id != image.id).toList();
    setState(() {
      _uploadedImageIds.remove(image.id);
      _state = _state.copyWith(
        images: images,
        selectedImageId: images.isEmpty ? null : images.first.id,
        status: 'تم حذف الصورة من الجلسة',
      );
    });
  }

  void _updateCustomLabel(String rawLabel) {
    _updateCurrentBoxLabel(sanitizeLabel(rawLabel));
  }

  void _updateCurrentBoxLabel(String label, [TrainingImageItem? image]) {
    final selectedImage = image ?? _selectedImage;
    if (selectedImage == null || selectedImage.boxes.isEmpty) return;
    final box = selectedImage.boxes.first.copyWith(label: label);
    _replaceSelected(selectedImage.copyWith(boxes: [box]));
  }

  void _replaceSelected(TrainingImageItem replacement) {
    final images = _state.images
        .map((image) => image.id == replacement.id ? replacement : image)
        .toList();
    setState(() => _state = _state.copyWith(images: images));
  }

  void _updateCoordinate(String field, String rawValue) {
    final value = double.tryParse(rawValue);
    final image = _selectedImage;
    if (value == null || value < 0 || value > 1 || image == null || image.boxes.isEmpty) {
      return;
    }

    final box = image.boxes.first;
    final updated = switch (field) {
      'x' => box.copyWith(x: value.clamp(0.0, 1.0 - box.width).toDouble()),
      'y' => box.copyWith(y: value.clamp(0.0, 1.0 - box.height).toDouble()),
      'width' => box.copyWith(width: value.clamp(0.05, 1.0 - box.x).toDouble()),
      'height' => box.copyWith(height: value.clamp(0.05, 1.0 - box.y).toDouble()),
      _ => box,
    };
    _replaceBox(updated);
  }

  void _beginBoxInteraction({bool handle = false}) {
    final image = _selectedImage;
    if (image == null || image.boxes.isEmpty) return;

    setState(() {
      _isBoxInteracting = true;
      _isHandleDragging = handle;
      _gestureStartBox = image.boxes.first;
      _state = _state.copyWith(
        status: handle ? 'اسحب المقبض لتحريك المربع' : 'كبّر المربع بإصبعين',
      );
    });
  }

  void _endBoxInteraction() {
    if (!_isBoxInteracting) return;
    setState(() {
      _isBoxInteracting = false;
      _isHandleDragging = false;
      _gestureStartBox = null;
    });
  }

  void _moveBox(Offset delta, Size previewSize) {
    final image = _selectedImage;
    if (image == null || image.boxes.isEmpty) return;

    final box = image.boxes.first;
    final nextX = (box.x + delta.dx / previewSize.width)
        .clamp(0.0, 1.0 - box.width)
        .toDouble();
    final nextY = (box.y + delta.dy / previewSize.height)
        .clamp(0.0, 1.0 - box.height)
        .toDouble();
    _replaceBox(box.copyWith(x: nextX, y: nextY));
  }

  void _resizeBox(double scale) {
    final image = _selectedImage;
    final startBox = _gestureStartBox;
    if (image == null || image.boxes.isEmpty || startBox == null) return;

    final width = (startBox.width * scale).clamp(0.05, 0.95).toDouble();
    final height = (startBox.height * scale).clamp(0.05, 0.95).toDouble();
    final x = startBox.x.clamp(0.0, 1.0 - width).toDouble();
    final y = startBox.y.clamp(0.0, 1.0 - height).toDouble();
    _replaceBox(image.boxes.first.copyWith(
      x: x,
      y: y,
      width: width,
      height: height,
    ));
  }

  void _replaceBox(BoundingBox box) {
    final image = _selectedImage;
    if (image == null || image.boxes.isEmpty) return;

    _replaceSelected(image.copyWith(boxes: [box]));
    _syncCoordinateControllers(box);
  }

  void _syncCoordinateControllers(BoundingBox box) {
    final values = <String, double>{
      'x': box.x,
      'y': box.y,
      'width': box.width,
      'height': box.height,
    };
    for (final entry in values.entries) {
      final controller = _coordinateControllers[entry.key];
      if (controller == null) continue;
      final text = entry.value.toStringAsFixed(2);
      controller.value = controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  Future<void> _uploadAllImages() async {
    final images = _state.images;
    if (images.isEmpty) {
      setState(() => _state = _state.copyWith(status: 'اختر صورة واحدة على الأقل للرفع'));
      return;
    }

    setState(() => _isUploading = true);
    try {
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        setState(() => _state = _state.copyWith(status: 'Uploading ${index + 1} of ${images.length}...'));
        final box = image.boxes.first;
        final label = sanitizeLabel(box.label);
        await _server.uploadImage(File(image.path), label, box.copyWith(label: label));
        _uploadedImageIds.add(image.id);
      }
      if (!mounted) return;
      setState(() => _state = _state.copyWith(
        status: 'Images uploaded to Roboflow. Please review and train on the Roboflow website.',
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _state = _state.copyWith(status: 'فشل رفع الصور: $error'));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  TrainingImageItem? get _selectedImage {
    TrainingImageItem? selectedImage;
    for (final image in _state.images) {
      if (image.id == _state.selectedImageId) {
        selectedImage = image;
        break;
      }
      if (selectedImage == null && _state.selectedImageId == null) {
        selectedImage = image;
      }
    }
    selectedImage ??= _state.images.isEmpty ? null : _state.images.first;
    if (selectedImage == null || selectedImage.boxes.isNotEmpty) {
      return selectedImage;
    }

    final updatedImage = _addDefaultBox(selectedImage);
    _state = _state.copyWith(
      images: _state.images
          .map((image) => image.id == updatedImage.id ? updatedImage : image)
          .toList(),
    );
    return updatedImage;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _isHighContrast ? Colors.white : Colors.white70;
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _blue,
        brightness: Brightness.dark,
        primary: _blue,
        surface: _surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        labelStyle: TextStyle(color: foreground),
        hintStyle: const TextStyle(color: Colors.white54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _isHighContrast ? Colors.white54 : Colors.white24),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('مدرّب الرؤية الذكي'),
            leading: const BackButton(),
            actions: [
              IconButton(
                onPressed: () => setState(() => _isHighContrast = !_isHighContrast),
                icon: Icon(_isHighContrast ? Icons.contrast : Icons.brightness_6_outlined),
                tooltip: 'تباين عال',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _buildStatusBar(),
              const SizedBox(height: 16),
              _buildSectionTitle('جمع الصور', 'التقط صورة أو اختر عدة صور من المعرض'),
              const SizedBox(height: 10),
              _buildGallery(),
              const SizedBox(height: 16),
              _buildEditModeButtons(),
              const SizedBox(height: 10),
              _buildPreview(_selectedImage),
              const SizedBox(height: 16),
              _buildSectionTitle('التصنيف والمربع', 'كل القيم يجب أن تكون بين 0.0 و 1.0'),
              const SizedBox(height: 10),
              _buildCustomLabelField(),
              const SizedBox(height: 10),
              _buildCoordinateEditor(_selectedImage),
              const SizedBox(height: 16),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditModeButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _editMode = EditMode.move),
            icon: const Icon(Icons.open_with),
            label: const Text('تحريك'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _editMode == EditMode.move
                  ? _blue
                  : const Color(0xff1b1e22),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _editMode = EditMode.resize),
            icon: const Icon(Icons.zoom_out_map),
            label: const Text('تكبير'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _editMode == EditMode.resize
                  ? _blue
                  : const Color(0xff1b1e22),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isUploading ? _orange.withValues(alpha: .2) : _green.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isUploading ? _orange : _green),
      ),
      child: Row(
        children: [
          Icon(_isUploading ? Icons.sync : Icons.check_circle, color: _isUploading ? _orange : _green),
          const SizedBox(width: 10),
          Expanded(child: Text(_state.status, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 112,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisExtent: 112,
              mainAxisSpacing: 8,
            ),
            itemCount: _state.images.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _addImageTile();
              final image = _state.images[index - 1];
              return _imageTile(image);
            },
          ),
        ),
        if (_state.images.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${_state.images.length} صور في الجلسة', style: const TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }

  Widget _addImageTile() {
    return InkWell(
      onTap: _pickImages,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: _blue), borderRadius: BorderRadius.circular(8)),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.add_photo_alternate_outlined, color: _blue), SizedBox(height: 4), Text('إضافة')],
        ),
      ),
    );
  }

  Widget _imageTile(TrainingImageItem image) {
    return GestureDetector(
      onTap: () => _selectImage(image),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(image.path), fit: BoxFit.cover)),
          Positioned(
            top: 2,
            left: 2,
            child: IconButton(
              onPressed: () => _deleteImage(image),
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              tooltip: 'حذف',
            ),
          ),
          if (image.id == _state.selectedImageId)
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.fromBorderSide(const BorderSide(color: _blue, width: 3)), borderRadius: BorderRadius.all(Radius.circular(8))))))
        ],
      ),
    );
  }

  Widget _buildPreview(TrainingImageItem? image) {
    return AspectRatio(
      aspectRatio: 1.35,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10)),
            child: image == null
                ? const Center(child: Text('لم يتم اختيار صورة'))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(image.path), fit: BoxFit.contain),
                      if (image.boxes.isNotEmpty)
                        _boxOverlay(image.boxes.first, previewSize),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _boxOverlay(BoundingBox box, Size previewSize) {
    final borderColor = _isBoxInteracting ? _orange : _green;
    return Positioned(
      left: box.x * previewSize.width,
      top: box.y * previewSize.height,
      width: box.width * previewSize.width,
      height: box.height * previewSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _editMode == EditMode.move ? _beginBoxInteraction : null,
        onLongPressEnd: _editMode == EditMode.move ? (_) => _endBoxInteraction() : null,
        onPanStart: _editMode == EditMode.move ? (_) => _beginBoxInteraction() : null,
        onPanUpdate: _editMode == EditMode.move ? (details) => _moveBox(details.delta, previewSize) : null,
        onPanEnd: _editMode == EditMode.move ? (_) => _endBoxInteraction() : null,
        onScaleStart: _editMode == EditMode.resize ? (_) => _beginBoxInteraction() : null,
        onScaleUpdate: _editMode == EditMode.resize ? (details) => _resizeBox(details.scale) : null,
        onScaleEnd: _editMode == EditMode.resize ? (_) => _endBoxInteraction() : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: borderColor.withValues(alpha: _isBoxInteracting ? .12 : .04),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ColoredBox(
                    color: borderColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      child: Text(box.label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(top: 0, right: 0, child: _buildDragHandle(previewSize)),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle(Size previewSize) {
    return IgnorePointer(
      ignoring: _editMode != EditMode.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _beginBoxInteraction(handle: true),
        onLongPressEnd: (_) => _endBoxInteraction(),
        onPanUpdate: (details) {
          if (_isHandleDragging) _moveBox(details.delta, previewSize);
        },
        onPanEnd: (_) => _endBoxInteraction(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _isBoxInteracting ? _orange : _green,
            borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomLeft: Radius.circular(8)),
          ),
          child: IconButton(
            onPressed: () {},
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.drag_handle, color: Colors.black),
            tooltip: 'تحريك المربع',
          ),
        ),
      ),
    );
  }

  Widget _buildCustomLabelField() {
    return TextField(
      controller: _customClassController,
      onChanged: _updateCustomLabel,
      decoration: const InputDecoration(
        hintText: 'أدخل فئة جديدة',
        labelText: 'فئة مخصصة',
      ),
    );
  }

  Widget _buildCoordinateEditor(TrainingImageItem? image) {
    if (image == null || image.boxes.isEmpty) return const Text('أضف صورة لتحرير المربع.');
    final box = image.boxes.first;
    return Column(
      children: [
        Row(children: [Expanded(child: _coordinateField('مركز X', 'x', box.x)), const SizedBox(width: 8), Expanded(child: _coordinateField('مركز Y', 'y', box.y))]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: _coordinateField('العرض', 'width', box.width)), const SizedBox(width: 8), Expanded(child: _coordinateField('الارتفاع', 'height', box.height))]),
      ],
    );
  }

  Widget _coordinateField(String label, String key, double value) {
    final controller = _coordinateControllers.putIfAbsent(key, () => TextEditingController(text: value.toStringAsFixed(2)));
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (raw) {
        final parsed = double.tryParse(raw ?? '');
        return parsed == null || parsed < 0 || parsed > 1 ? '0.0 - 1.0 فقط' : null;
      },
      onChanged: (raw) => _updateCoordinate(key, raw),
      decoration: InputDecoration(labelText: label, suffixText: '0..1'),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(onPressed: _isUploading ? null : _pickImages, icon: const Icon(Icons.photo_library_outlined), label: const Text('Select images'), style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size.fromHeight(52))),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _isUploading ? null : _uploadAllImages, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Upload All'), style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size.fromHeight(52))),
      ],
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Colors.white70))]);
  }
}
