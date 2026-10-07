import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Processing status for individual document card scans.
enum DocumentScanStatus {
  idle,
  processing,
  success,
  error,
}

/// State representing an active or completed scan for a document slot.
class DocumentScanState {
  final DocumentScanStatus status;
  final String stageText;
  final String? errorMessage;
  final String? lastFilePath;
  final String? lastFileName;

  const DocumentScanState({
    required this.status,
    this.stageText = 'Parsing document…',
    this.errorMessage,
    this.lastFilePath,
    this.lastFileName,
  });

  DocumentScanState copyWith({
    DocumentScanStatus? status,
    String? stageText,
    String? errorMessage,
    String? lastFilePath,
    String? lastFileName,
  }) {
    return DocumentScanState(
      status: status ?? this.status,
      stageText: stageText ?? this.stageText,
      errorMessage: errorMessage ?? this.errorMessage,
      lastFilePath: lastFilePath ?? this.lastFilePath,
      lastFileName: lastFileName ?? this.lastFileName,
    );
  }
}

/// In-card scoped document scanning overlay with top-to-bottom laser sweep,
/// pulsing border, stage label, completion transition, and error state.
class DocumentCardScanOverlay extends StatefulWidget {
  final DocumentScanStatus status;
  final String stageText;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final bool isDark;

  const DocumentCardScanOverlay({
    super.key,
    required this.status,
    required this.stageText,
    this.errorMessage,
    this.onRetry,
    this.onDismiss,
    required this.isDark,
  });

  @override
  State<DocumentCardScanOverlay> createState() => _DocumentCardScanOverlayState();
}

class _DocumentCardScanOverlayState extends State<DocumentCardScanOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _sweepController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.status == DocumentScanStatus.processing) {
      _sweepController.repeat();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(DocumentCardScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == DocumentScanStatus.processing) {
      if (!_sweepController.isAnimating) _sweepController.repeat();
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_sweepController.isAnimating) _sweepController.stop();
      if (_pulseController.isAnimating) _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      liveRegion: true,
      label: _buildAccessibilityLabel(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = constraints.maxHeight;

          if (widget.status == DocumentScanStatus.success) {
            return _buildSuccessOverlay();
          }

          if (widget.status == DocumentScanStatus.error) {
            return _buildErrorOverlay();
          }

          // Processing status (looping sweep + shimmer)
          return AnimatedBuilder(
            animation: Listenable.merge([_sweepController, _pulseController]),
            builder: (context, child) {
              final pulseValue = reduceMotion ? 0.5 : _pulseController.value;
              final sweepProgress = reduceMotion ? 0.5 : _sweepController.value;
              final currentY = sweepProgress * cardHeight;

              return Container(
                decoration: BoxDecoration(
                  color: (widget.isDark ? AppColors.darkSurface : Colors.white)
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.lightPrimary.withValues(
                      alpha: reduceMotion ? 0.35 : 0.25 + 0.35 * pulseValue,
                    ),
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Gradient pulse tint
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.lightPrimary.withValues(
                                alpha: 0.03 + 0.05 * pulseValue,
                              ),
                              AppColors.primaryLightBg.withValues(
                                alpha: 0.05 + 0.06 * pulseValue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Top-to-bottom laser beam & glow trail (skipped if prefers-reduced-motion)
                    if (!reduceMotion) ...[
                      // Soft glow trail behind beam
                      Positioned(
                        top: currentY - 20,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.lightPrimary.withValues(alpha: 0.0),
                                AppColors.lightPrimary.withValues(alpha: 0.12),
                                AppColors.lightPrimary.withValues(alpha: 0.28),
                                AppColors.lightPrimary.withValues(alpha: 0.12),
                                AppColors.lightPrimary.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Bright laser scan line
                      Positioned(
                        top: currentY,
                        left: 0,
                        right: 0,
                        height: 2.2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.lightPrimary,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.lightPrimary.withValues(alpha: 0.75),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Centered cycling status badge with micro-spinner
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? const Color(0xFF1E2235)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(
                              color: AppColors.lightPrimary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.lightPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Text(
                                    reduceMotion ? 'Scanning…' : widget.stageText,
                                    key: ValueKey<String>(widget.stageText),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: widget.isDark ? Colors.white : AppColors.lightTextPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: (widget.isDark ? const Color(0xFF102619) : const Color(0xFFF0FDF4))
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF143322) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Verified successfully!',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: (widget.isDark ? const Color(0xFF291515) : const Color(0xFFFEF2F2))
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.errorMessage ?? 'Verification failed',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onDismiss != null) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: widget.onDismiss,
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close_rounded, size: 15, color: AppColors.error),
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: widget.onRetry,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Retry Scan',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _buildAccessibilityLabel() {
    switch (widget.status) {
      case DocumentScanStatus.processing:
        return 'Scanning document: ${widget.stageText}';
      case DocumentScanStatus.success:
        return 'Document scan completed and verified successfully';
      case DocumentScanStatus.error:
        return 'Document scan failed: ${widget.errorMessage ?? "Error"}';
      case DocumentScanStatus.idle:
        return 'Document idle';
    }
  }
}