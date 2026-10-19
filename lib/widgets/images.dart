import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/app_store.dart';
import '../data/images.dart';
import 'common.dart';

/// Pick a photo (gallery, or the camera on a phone), already made smaller.
/// Null when cancelled.
Future<XFile?> pickImageFile(BuildContext context, {double maxSide = 1600}) async {
  ImageSource? source = ImageSource.gallery;
  if (!kIsWeb) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return null;
  }
  try {
    return await ImagePicker()
        .pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: 82);
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not open the photos.');
    return null;
  }
}

/// Pick a photo, shrink it and upload it (with a "Uploading" dialog).
/// Returns its address, or null when cancelled or it failed (a message is
/// shown).
Future<String?> pickAndUploadImage(BuildContext context, {double maxSide = 1600}) async {
  final file = await pickImageFile(context, maxSide: maxSide);
  if (file == null || !context.mounted) return null;

  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Text('Uploading image...'),
        ]),
      ),
    ),
  );
  try {
    final url = await uploadImage(file);
    nav.pop();
    return url;
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, e.toString());
    return null;
  }
}

/// A picture from the web, with a spinner while loading and an icon when it
/// can't be shown.
class NetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  const NetImage(this.url,
      {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius = 10});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          loadingBuilder: (context, child, p) => p == null
              ? child
              : Container(
                  width: width,
                  height: height,
                  color: const Color(0xFFEEF1F6),
                  alignment: Alignment.center,
                  child: const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
          errorBuilder: (context, _, __) => Container(
            width: width,
            height: height,
            color: const Color(0xFFEEF1F6),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
          ),
        ),
      );
}

/// The picture in a popup over the page, zoomable, with "Open in new tab".
void openImage(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(alignment: Alignment.topRight, children: [
        Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url,
                errorBuilder: (context, _, __) =>
                    const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filledTonal(
            tooltip: 'Open in new tab',
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
                .catchError((_) => false),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      ]),
    ),
  );
}

/// A small clickable picture (opens full screen); [onRemove] shows an ×.
class ImageThumb extends StatelessWidget {
  final String url;
  final double size;
  final VoidCallback? onRemove;
  const ImageThumb({super.key, required this.url, this.size = 96, this.onRemove});

  @override
  Widget build(BuildContext context) => Stack(children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => openImage(context, url),
          child: NetImage(thumbUrl(url, width: (size * 3).round()), width: size, height: size),
        ),
        if (onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
      ]);
}

/// My profile picture with a camera button to change or remove it.
class EditableAvatar extends StatelessWidget {
  final double size;
  const EditableAvatar({super.key, this.size = 80});

  Future<void> _change(BuildContext context) async {
    final store = AppStore.instance;
    var action = 'new';
    if (store.photoUrl.isNotEmpty) {
      final a = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Change photo'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text('Remove photo', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ]),
        ),
      );
      if (a == null) return;
      action = a;
    }
    if (action == 'remove') {
      store.setPhoto('');
      return;
    }
    if (!context.mounted) return;
    final url = await pickAndUploadImage(context, maxSide: 600);
    if (url == null) return;
    store.setPhoto(url);
    if (context.mounted) showSnack(context, 'Profile photo updated');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppStore.instance,
        builder: (context, _) => Stack(clipBehavior: Clip.none, children: [
          myAvatar(size: size),
          Positioned(
            right: -2,
            bottom: -2,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _change(context),
                child: Tooltip(
                  message: 'Change photo',
                  child: Padding(
                    padding: EdgeInsets.all(size > 70 ? 7 : 4),
                    child: Icon(Icons.photo_camera_rounded,
                        size: size > 70 ? 18 : 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
}
