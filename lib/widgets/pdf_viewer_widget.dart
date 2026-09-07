import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';

/// Widget that defers loading PDF bytes until the user explicitly taps "View PDF".
/// Automatically downloads authenticated GridFS PDFs and opens them in the native viewer.
class DeferredPdfViewerCard extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String subtitle;
  final IconData icon;

  const DeferredPdfViewerCard({
    super.key,
    required this.pdfUrl,
    this.title = 'PDF Document Attachment',
    this.subtitle = 'Tap to load & view PDF',
    this.icon = Icons.picture_as_pdf_rounded,
  });

  @override
  State<DeferredPdfViewerCard> createState() => _DeferredPdfViewerCardState();
}

class _DeferredPdfViewerCardState extends State<DeferredPdfViewerCard> {
  bool _isOpening = false;

  Future<void> _handlePdfTap() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    try {
      final url = widget.pdfUrl.trim();
      if (url.isEmpty) {
        throw Exception('No document attachment URL provided.');
      }

      File? localPdfFile;

      // 1. Direct local file on device
      if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('/api/')) {
        final f = File(url);
        if (await f.exists()) {
          localPdfFile = f;
        }
      }

      // 2. Download via ApiClient (handles baseUrl, JWT bearer token, ngrok headers)
      if (localPdfFile == null) {
        final tempDir = Directory.systemTemp;
        String safeName = widget.subtitle.trim();
        if (!safeName.toLowerCase().endsWith('.pdf')) {
          final cleanTitle = widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          safeName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        }
        final tempFile = File('${tempDir.path}/$safeName');

        // Resolve endpoint
        String endpoint = url;
        if (!url.startsWith('http')) {
          if (!url.startsWith('/')) {
            endpoint = '/$url';
          }
        }

        final dio = ApiClient.instance.dio;
        final response = await dio.get<List<int>>(
          endpoint,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'ngrok-skip-browser-warning': 'true'},
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
          await tempFile.writeAsBytes(response.data!);
          localPdfFile = tempFile;
        } else {
          throw Exception('Server returned status ${response.statusCode}');
        }
      }

      // 3. Open with native PDF viewer
      if (await localPdfFile.exists()) {
        final result = await OpenFilex.open(localPdfFile.path);
        if (result.type != ResultType.done && mounted) {
          debugPrint('OpenFilex message: ${result.message}');
          // Fallback to url_launcher if URL is external http(s)
          if (url.startsWith('http')) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        }
      } else {
        throw Exception('Could not save PDF to temporary device cache.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Could not open document: $e')),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _handlePdfTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: AppColors.error, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _isOpening
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : ElevatedButton.icon(
                      onPressed: _handlePdfTap,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                      label: const Text('View PDF', style: TextStyle(fontSize: 12)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
