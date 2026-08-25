import 'package:flutter/material.dart';
import '../controllers/paging_controller.dart';
import '../theme/app_colors.dart';

typedef ItemWidgetBuilder<T> = Widget Function(BuildContext context, T item, int index);
typedef ItemKeyExtractor<T> = Key Function(T item);

class PaginatedListView<T> extends StatelessWidget {
  final PagingController<T> controller;
  final ItemWidgetBuilder<T> itemBuilder;
  final ItemKeyExtractor<T> itemKey;
  final Widget? emptyWidget;
  final IndexedWidgetBuilder? skeletonBuilder;
  final EdgeInsetsGeometry padding;
  final Widget? separator;

  const PaginatedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.itemKey,
    this.emptyWidget,
    this.skeletonBuilder,
    this.padding = const EdgeInsets.all(16),
    this.separator = const SizedBox(height: 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          if (skeletonBuilder != null) {
            return ListView.separated(
              padding: padding,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, _) => separator ?? const SizedBox(height: 12),
              itemBuilder: (ctx, index) => skeletonBuilder!(ctx, index),
            );
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (controller.items.isEmpty && controller.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  const Text(
                    'Failed to load items',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.error ?? 'An unexpected error occurred.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: controller.retry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.items.isEmpty) {
          return emptyWidget ??
              const Center(
                child: Text('No items found.'),
              );
        }

        final itemsCount = controller.items.length;
        final hasFooter = controller.isFetchingNextPage ||
            controller.error != null ||
            (!controller.hasMore && itemsCount > 0);

        final totalListItems = itemsCount + (hasFooter ? 1 : 0);

        return ListView.builder(
          controller: controller.scrollController,
          padding: padding,
          itemCount: totalListItems,
          itemBuilder: (context, index) {
            // Render list item
            if (index < itemsCount) {
              final item = controller.items[index];
              final childWidget = itemBuilder(context, item, index);
              final keyedWidget = KeyedSubtree(
                key: itemKey(item),
                child: childWidget,
              );

              if (separator != null && index < itemsCount - 1) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    keyedWidget,
                    separator!,
                  ],
                );
              }
              return keyedWidget;
            }

            // Render Footer Widget (Loading, Error/Retry, or No More Items)
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: _buildFooterState(context, isDark),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFooterState(BuildContext context, bool isDark) {
    if (controller.isFetchingNextPage) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading more...',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      );
    }

    if (controller.error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Could not load more items',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: controller.retry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Tap to Retry', style: TextStyle(fontSize: 13)),
          ),
        ],
      );
    }

    if (!controller.hasMore) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: (isDark ? AppColors.darkSurface : AppColors.lightSurfaceContainer).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '• End of List (No more items) •',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
