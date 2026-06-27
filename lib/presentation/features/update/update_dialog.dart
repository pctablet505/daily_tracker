import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_logger.dart';

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;
  final int? fileSize;

  UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    this.fileSize,
  });
}

class UpdateService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest',
      );

      final tagName = response.data['tag_name'] as String;
      final latestVersion = tagName.replaceFirst('v', '');
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (!_isNewerVersion(latestVersion, currentVersion)) {
        return null;
      }

      final assets = (response.data['assets'] as List);
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String).toLowerCase().endsWith('.apk'),
        orElse: () => null,
      );

      if (apkAsset == null) return null;

      return UpdateInfo(
        version: latestVersion,
        changelog: (response.data['body'] ?? 'No changelog available')
            .toString()
            .replaceAll(r'\n', '\n'),
        downloadUrl: apkAsset['browser_download_url'],
        fileSize: apkAsset['size'],
      );
    } catch (e) {
      AppLogger.e('Update check failed', e);
      return null;
    }
  }

  bool _isNewerVersion(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (e) {
      AppLogger.e('Version comparison failed (remote=$remote, current=$current)', e);
      return false;
    }
    return false;
  }

  Future<bool> shouldDownload() async {
    final result = await Connectivity().checkConnectivity();
    return result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile;
  }

  Future<String?> downloadApk(
    String url, {
    required void Function(int received, int total) onProgress,
    int? expectedSize,
    CancelToken? cancelToken,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/update.apk';
      await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );

      // Verify file size if expected size is known
      if (expectedSize != null) {
        final file = File(filePath);
        if (await file.exists()) {
          final actualSize = await file.length();
          if (actualSize != expectedSize) {
            AppLogger.e('APK size mismatch: expected $expectedSize, got $actualSize');
            await file.delete();
            return null;
          }
        }
      }

      return filePath;
    } catch (e) {
      AppLogger.e('Download failed', e);
      return null;
    }
  }
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const UpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  final _cancelToken = CancelToken();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Icon(Icons.system_update, color: colorScheme.primary, size: 32),
      title: Text('Update Available'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.updateInfo.version}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.35,
              ),
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: widget.updateInfo.changelog,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet(
                    p: theme.textTheme.bodyMedium,
                    h1: theme.textTheme.titleLarge,
                    h2: theme.textTheme.titleMedium,
                    listBullet: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0
                    ? '${(_progress * 100).toStringAsFixed(0)}% downloaded'
                    : 'Starting download...',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        if (!_isDownloading)
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Update Now'),
          ),
        if (_isDownloading)
          TextButton(
            onPressed: () {
              _cancelToken.cancel();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updates are only supported on Android')),
      );
      return;
    }

    // Check install permission
    final status = await Permission.requestInstallPackages.status;
    if (status.isDenied) {
      final result = await Permission.requestInstallPackages.request();
      if (!result.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Install permission required to update')),
          );
        }
        return;
      }
    }

    setState(() => _isDownloading = true);

    final service = UpdateService();
    final path = await service.downloadApk(
      widget.updateInfo.downloadUrl,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
      expectedSize: widget.updateInfo.fileSize,
      cancelToken: _cancelToken,
    );

    if (path == null || !mounted) return;

    // Launch system installer using OpenFilex (handles FileProvider content URI on Android 10+)
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open installer: ${result.message}')),
      );
      return;
    }
    if (mounted) Navigator.pop(context);
  }
}
