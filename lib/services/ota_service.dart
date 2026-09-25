import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class OTAService {
  static final OTAService _instance = OTAService._internal();
  factory OTAService() => _instance;
  OTAService._internal();

  final _db = FirebaseDatabase.instance.ref();
  final Dio _dio = Dio();

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final snapshot = await _db.child('app_updates/android').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final latestVersion = data['latest_version'] as String;
        final downloadUrl = data['download_url'] as String;

        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, downloadUrl);
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking for updates: $e");
    }
  }

  bool _isNewerVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  void _showUpdateDialog(BuildContext context, String newVersion, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B2A3B),
          title: const Text('Update Available!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            'Version $newVersion is available. Would you like to download and install it now?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Later', style: TextStyle(color: Colors.white54)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF55D6BE)),
              onPressed: () {
                Navigator.of(context).pop();
                _downloadAndInstall(context, url);
              },
              child: const Text('Update Now', style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstall(BuildContext context, String url) async {
    // Show a downloading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          backgroundColor: Color(0xFF1B2A3B),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF55D6BE)),
              SizedBox(height: 16),
              Text("Downloading update...", style: TextStyle(color: Colors.white)),
            ],
          ),
        );
      },
    );

    try {
      final dir = await getExternalStorageDirectory();
      final savePath = "${dir!.path}/app-update.apk";

      await _dio.download(url, savePath);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close download dialog
      }

      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        debugPrint("Error opening APK: ${result.message}");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close download dialog
      }
      debugPrint("Download error: $e");
    }
  }
}
