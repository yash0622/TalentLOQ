import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';
import '../services/token_storage_service.dart';
import '../theme/app_colors.dart';
import 'platform_file_saver.dart';

class DocumentViewerHelper {
  /// Open and view a document seamlessly on both Web and Native platforms.
  /// - Automatically injects Auth Bearer headers and query token.
  /// - Detects images and presents a full-featured interactive zoom viewer in-app.
  /// - Opens PDFs and documents via Chrome tab on Web and native viewers on Mobile.
  static Future<void> viewDocument(
    BuildContext context, {
    required String? fileUrl,
    required String docTitle,
    String? filename,
  }) async {
    final cleanUrl = fileUrl?.trim();
    if (cleanUrl == null || cleanUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$docTitle is not uploaded yet.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Loading $docTitle...')),
            ],
          ),
          duration: const Duration(milliseconds: 1400),
        ),
      );
    }

    try {
      final dio = ApiClient.instance.dio;
      final tokenStorage = TokenStorageService();
      final accessToken = await tokenStorage.getAccessToken();

      // Normalize endpoint
      String endpoint = cleanUrl;
      if (!endpoint.startsWith('http') && !endpoint.startsWith('/')) {
        endpoint = '/$endpoint';
      }

      // Fetch short-lived download token for browser tabs if available
      String? downloadToken;
      try {
        final tokenRes = await dio.get('/api/v1/files/token');
        if (tokenRes.statusCode == 200 && tokenRes.data is Map) {
          downloadToken = tokenRes.data['download_token'] as String?;
        }
      } catch (_) {}

      // Build authenticated URL for browser tab opening
      final baseUrl = dio.options.baseUrl.endsWith('/')
          ? dio.options.baseUrl.substring(0, dio.options.baseUrl.length - 1)
          : dio.options.baseUrl;
      String fullUrl = endpoint.startsWith('http') ? endpoint : '$baseUrl$endpoint';
      final effectiveToken = downloadToken ?? accessToken;
      if (effectiveToken != null && effectiveToken.isNotEmpty) {
        final sep = fullUrl.contains('?') ? '&' : '?';
        fullUrl = '$fullUrl${sep}token=$effectiveToken';
      }

      // 1. Fetch file bytes with auth header
      final response = await dio.get<List<int>>(
        endpoint,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'ngrok-skip-browser-warning': 'true'},
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        final bytes = Uint8List.fromList(response.data!);
        final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
        final lowerName = (filename ?? docTitle).toLowerCase();

        final isImage = contentType.startsWith('image/') ||
            lowerName.endsWith('.jpg') ||
            lowerName.endsWith('.jpeg') ||
            lowerName.endsWith('.png') ||
            lowerName.endsWith('.webp') ||
            (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) || // JPEG magic bytes
            (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47); // PNG magic bytes

        if (context.mounted) {
          if (isImage) {
            // Show high-resolution interactive in-app viewer for marksheets / images
            _showImageViewerDialog(
              context,
              docTitle: docTitle,
              filename: filename ?? '$docTitle.jpg',
              imageBytes: bytes,
              externalUrl: fullUrl,
            );
            return;
          }

          // PDF or other documents
          if (kIsWeb) {
            // On Web, open directly in a new tab with Chrome's native PDF reader
            final uri = Uri.tryParse(fullUrl);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return;
            }
          } else {
            // On Native platforms (Android, Windows, etc.)
            String ext = 'pdf';
            if (lowerName.contains('.') && !lowerName.endsWith('.')) {
              final parsed = lowerName.split('.').last.replaceAll(RegExp(r'[^a-z0-9]'), '');
              if (parsed.isNotEmpty && parsed.length <= 5) {
                ext = parsed;
              }
            } else if (contentType.isNotEmpty) {
              if (contentType.contains('pdf')) {
                ext = 'pdf';
              } else if (contentType.contains('wordprocessingml') || contentType.contains('docx')) {
                ext = 'docx';
              } else if (contentType.contains('msword')) {
                ext = 'doc';
              } else if (contentType.contains('sheet') || contentType.contains('xlsx')) {
                ext = 'xlsx';
              } else if (contentType.contains('presentation') || contentType.contains('pptx')) {
                ext = 'pptx';
              } else if (contentType.contains('text/plain')) {
                ext = 'txt';
              }
            }

            final opened = await platformSaveAndOpenFile(
              bytes: bytes,
              title: docTitle,
              extension: ext,
            );
            if (opened) {
              return;
            }

            // Fallback to url_launcher if platform saver fails
            final uri = Uri.tryParse(fullUrl);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DOC VIEWER ERROR] $e');
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $docTitle. File may not be available on server.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  static void _showImageViewerDialog(
    BuildContext context, {
    required String docTitle,
    required String filename,
    required Uint8List imageBytes,
    required String externalUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 750),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.lightPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppColors.lightPrimary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              docTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              filename,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open in new tab',
                        icon: const Icon(Icons.open_in_new_rounded, size: 20),
                        onPressed: () {
                          final uri = Uri.tryParse(externalUrl);
                          if (uri != null) {
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),

                // Interactive Image View Area
                Expanded(
                  child: Container(
                    color: const Color(0xFF121214),
                    alignment: Alignment.center,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      panEnabled: true,
                      child: Center(
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Text(
                                'Unable to render image format.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Footer hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF18181C) : const Color(0xFFF5F5F7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pinch or scroll to zoom · Drag to pan',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Open / Save', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          final uri = Uri.tryParse(externalUrl);
                          if (uri != null) {
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
