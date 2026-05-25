import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Picks an image from a source (camera / gallery). Hoisted to a top-level
/// typedef so [ShareService] tests can substitute the underlying picker
/// without staging a real plugin.
typedef ImageSourcePicker = Future<XFile?> Function(ImageSource source);

/// Hands a list of files to the native share sheet. Hoisted for DI.
typedef FileShareSink = Future<ShareResult> Function(
  List<XFile> files, {
  String? text,
});

/// Requests a runtime permission and returns its post-request status.
typedef PermissionRequester = Future<PermissionStatus> Function(
  Permission permission,
);

/// Returns the current status of a runtime permission (no prompt).
typedef PermissionStatusReader = Future<PermissionStatus> Function(
  Permission permission,
);

/// Single source of truth for share-card IO: camera/gallery pick, share
/// sheet handoff, and camera-permission checks.
///
/// Constructor-injected seams cover every platform call so unit tests can
/// run pure-Dart without staging Android/iOS plugin channels. Default
/// implementations delegate to:
///   * `image_picker.ImagePicker().pickImage(...)`
///   * `share_plus.Share.shareXFiles(...)`
///   * `permission_handler.Permission.camera.request()` / `.status`
class ShareService {
  ShareService({
    ImageSourcePicker? imagePicker,
    FileShareSink? fileShareSink,
    PermissionRequester? permissionRequester,
    PermissionStatusReader? permissionStatusReader,
  })  : _imagePicker = imagePicker ?? _defaultImagePicker,
        _fileShareSink = fileShareSink ?? _defaultFileShareSink,
        _permissionRequester =
            permissionRequester ?? _defaultPermissionRequester,
        _permissionStatusReader =
            permissionStatusReader ?? _defaultPermissionStatusReader;

  final ImageSourcePicker _imagePicker;
  final FileShareSink _fileShareSink;
  final PermissionRequester _permissionRequester;
  final PermissionStatusReader _permissionStatusReader;

  /// Open the platform camera and return the captured image, or `null` if
  /// the user cancelled or the platform denied access. Callers should
  /// gate this on [requestCameraPermission] for graceful denial UX —
  /// this method itself does NOT prompt for permission.
  Future<XFile?> pickFromCamera() => _imagePicker(ImageSource.camera);

  /// Open the gallery picker and return the selected image, or `null` if
  /// the user dismissed without selecting. Gallery picks on Android 13+
  /// route through the system photo picker, which does not require a
  /// runtime media-images permission.
  Future<XFile?> pickFromGallery() => _imagePicker(ImageSource.gallery);

  /// Hand [file] to the native share sheet. Optional [text] is appended
  /// to the share payload (caption / link / promo blurb). The returned
  /// [ShareResult] tells the caller whether the user shared, dismissed,
  /// or hit a platform error.
  Future<ShareResult> share(XFile file, {String? text}) {
    return _fileShareSink(<XFile>[file], text: text);
  }

  /// Prompt the user for camera permission. Returns the post-prompt
  /// status: [PermissionStatus.granted] / [PermissionStatus.denied] /
  /// [PermissionStatus.permanentlyDenied] / etc. Never throws on user
  /// denial — denial is a status, not an exception.
  Future<PermissionStatus> requestCameraPermission() {
    return _permissionRequester(Permission.camera);
  }

  /// Read the current camera-permission status without prompting. Use
  /// this before `pickFromCamera` to decide whether to call
  /// [requestCameraPermission] or jump straight to the picker.
  Future<PermissionStatus> cameraPermissionStatus() {
    return _permissionStatusReader(Permission.camera);
  }

  // --------------------------------------------------------------------
  // Default platform implementations.
  // --------------------------------------------------------------------

  static Future<XFile?> _defaultImagePicker(ImageSource source) {
    return ImagePicker().pickImage(source: source);
  }

  static Future<ShareResult> _defaultFileShareSink(
    List<XFile> files, {
    String? text,
  }) {
    // share_plus 10.x API. (11.x renamed this to `SharePlus.instance.share`
    // with a `ShareParams` builder, but we hold at 10.x because 11.x bumped
    // Dart min above 3.11.4.)
    return Share.shareXFiles(files, text: text);
  }

  static Future<PermissionStatus> _defaultPermissionRequester(
    Permission permission,
  ) {
    return permission.request();
  }

  static Future<PermissionStatus> _defaultPermissionStatusReader(
    Permission permission,
  ) {
    return permission.status;
  }
}
