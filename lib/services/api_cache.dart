import 'package:flutter/foundation.dart';

/// In-memory cache entry with timestamp and TTL.
class _CacheEntry {
  final dynamic data;
  final DateTime cachedAt;
  final Duration ttl;

  _CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().difference(cachedAt) > ttl;
}

/// In-memory API response cache with stale-while-revalidate pattern.
///
/// Usage:
/// ```dart
/// final data = await ApiCache.instance.getOrFetch(
///   '/drives?page=1&limit=20',
///   () => _apiClient.dio.get('/drives?page=1&limit=20'),
/// );
/// ```
class ApiCache {
  ApiCache._();
  static final ApiCache instance = ApiCache._();

  final Map<String, _CacheEntry> _cache = {};
  static const Duration defaultTtl = Duration(minutes: 3);

  /// Returns cached data immediately if available (even if stale).
  /// If expired or missing, calls [fetchFn], updates the cache, and returns fresh data.
  /// If cached but expired, returns stale data AND triggers a background refetch.
  Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetchFn, {
    Duration ttl = defaultTtl,
    void Function(T freshData)? onRefresh,
  }) async {
    final entry = _cache[key];

    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }

    if (entry != null && entry.isExpired) {
      // Stale-while-revalidate: return stale data, refresh in background
      _backgroundRefetch(key, fetchFn, ttl, onRefresh);
      return entry.data as T;
    }

    // No cached data — must fetch synchronously
    final freshData = await fetchFn();
    _cache[key] = _CacheEntry(data: freshData, cachedAt: DateTime.now(), ttl: ttl);
    return freshData;
  }

  /// Puts data directly into the cache.
  void put<T>(String key, T data, {Duration ttl = defaultTtl}) {
    _cache[key] = _CacheEntry(data: data, cachedAt: DateTime.now(), ttl: ttl);
  }

  /// Invalidate a specific cache key.
  void invalidate(String key) {
    _cache.remove(key);
    debugPrint('[ApiCache] Invalidated: $key');
  }

  /// Invalidate all cache entries whose key starts with [prefix].
  void invalidatePrefix(String prefix) {
    final keysToRemove = _cache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keysToRemove) {
      _cache.remove(k);
    }
    if (keysToRemove.isNotEmpty) {
      debugPrint('[ApiCache] Invalidated ${keysToRemove.length} entries with prefix: $prefix');
    }
  }

  /// Clear the entire cache.
  void clearAll() {
    _cache.clear();
    debugPrint('[ApiCache] Cleared all cache entries');
  }

  Future<void> _backgroundRefetch<T>(
    String key,
    Future<T> Function() fetchFn,
    Duration ttl,
    void Function(T freshData)? onRefresh,
  ) async {
    try {
      final freshData = await fetchFn();
      _cache[key] = _CacheEntry(data: freshData, cachedAt: DateTime.now(), ttl: ttl);
      onRefresh?.call(freshData);
      debugPrint('[ApiCache] Background refresh completed: $key');
    } catch (e) {
      debugPrint('[ApiCache] Background refresh failed: $key — $e');
    }
  }
}
