import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_colors.dart';

/// Widget that defers loading PDF bytes until the user explicitly taps "View PDF".
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
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(widget.icon, color: AppColors.lightPrimary),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.title)),
              ],
            ),
            content: SelectableText('Brochure / Document URL:\n$url'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        try {
          await OpenFilex.open(url);
        } catch (_) {
          if (mounted) {
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(widget.title),
                content: Text('Document location:\n$url'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
        }
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
