import 'package:flutter/material.dart';
import '../utils/perf_logger.dart';

/// Generic model representing a paginated API response.
class PaginatedResponse<T> {
  final List<T> items;
  final int page;
  final int limit;
  final int totalCount;
  final bool hasMore;

  PaginatedResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.totalCount,
    required this.hasMore,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic item) fromJsonItem,
  ) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PaginatedResponse<T>(
      items: rawItems.map((e) => fromJsonItem(e)).toList(),
      page: json['page'] is int ? json['page'] : 1,
      limit: json['limit'] is int ? json['limit'] : 20,
      totalCount: json['total_count'] is int ? json['total_count'] : 0,
      hasMore: json['has_more'] is bool ? json['has_more'] : false,
    );
  }
}

typedef PageFetchCallback<T> = Future<PaginatedResponse<T>> Function(int page, int limit);

/// Controller managing infinite scroll pagination state, scroll listening, and page fetching.
class PagingController<T> extends ChangeNotifier {
  final PageFetchCallback<T> fetchPage;
  final int pageSize;
  final ScrollController scrollController;
  final String? debugLabel;

  List<T> _items = [];
  int _currentPage = 1;
  int _totalCount = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isFetchingNextPage = false;
  String? _error;

  PagingController({
    required this.fetchPage,
    this.pageSize = 20,
    this.debugLabel,
    ScrollController? scrollController,
  }) : scrollController = scrollController ?? ScrollController() {
    this.scrollController.addListener(_onScroll);
    fetchInitialPage();
  }

  List<T> get items => List.unmodifiable(_items);
  int get currentPage => _currentPage;
  int get totalCount => _totalCount;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  bool get isFetchingNextPage => _isFetchingNextPage;
  String? get error => _error;
  bool get isEmpty => !_isLoading && _items.isEmpty && _error == null;

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final maxScroll = scrollController.position.maxScrollExtent;
    final currentScroll = scrollController.position.pixels;
    
    // Trigger next page fetch when user scrolls within ~200px of the list end
    if (maxScroll - currentScroll <= 200) {
      fetchNextPage();
    }
  }

  Future<void> fetchInitialPage() async {
    final perfTimer = debugLabel != null ? PerfLogger.start(debugLabel!) : null;
    _isLoading = true;
    _isFetchingNextPage = false;
    _error = null;
    _currentPage = 1;
    _items = [];
    _hasMore = true;
    notifyListeners();

    try {
      final response = await fetchPage(_currentPage, pageSize);
      _items = response.items;
      _totalCount = response.totalCount;
      _hasMore = response.hasMore;
      _isLoading = false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
    }
    perfTimer?.stop();
    notifyListeners();
  }

  Future<void> fetchNextPage() async {
    if (_isLoading || _isFetchingNextPage || !_hasMore || _error != null) {
      return;
    }

    _isFetchingNextPage = true;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      final response = await fetchPage(nextPage, pageSize);
      
      _currentPage = nextPage;
      _items = [..._items, ...response.items];
      _totalCount = response.totalCount;
      _hasMore = response.hasMore;
      _isFetchingNextPage = false;
    } catch (e) {
      _error = e.toString();
      _isFetchingNextPage = false;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await fetchInitialPage();
  }

  void retry() {
    _error = null;
    if (_items.isEmpty) {
      fetchInitialPage();
    } else {
      fetchNextPage();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }
}
