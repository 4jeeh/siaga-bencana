import '../../core/network/api_envelope.dart';
import '../events/event_dto.dart';
import 'report_dto.dart';

String reportError(Object error) => error is ApiErrorEnvelope ? error.message : 'Respons laporan tidak valid. Coba lagi.';

class ReportListState {
  List<ReportDto> items = [];
  PageDto? page;
  ReportFeedMetaDto? meta;
  DateTime? lastLoadedAt;
  String? error, loadMoreError;
  bool initialLoading = false, refreshing = false, loadingMore = false, zoneRequired = false;
  bool get empty => lastLoadedAt != null && items.isEmpty && error == null;
  int _request = 0;

  void clear() {
    _request++;
    items = []; page = null; meta = null; lastLoadedAt = null;
    error = loadMoreError = null;
    initialLoading = refreshing = loadingMore = zoneRequired = false;
  }

  Future<void> load(Future<ReportFeedDto> Function(int offset) fetch, void Function() changed,
      {bool more = false, int? minimumZoneVersion}) async {
    if (more && (page?.nextOffset == null || loadingMore || refreshing || initialLoading)) return;
    final request = ++_request;
    initialLoading = !more && lastLoadedAt == null;
    refreshing = !more && !initialLoading;
    loadingMore = more;
    error = loadMoreError = null;
    zoneRequired = false;
    changed();
    try {
      final feed = await fetch(more ? page!.nextOffset! : 0);
      if (request != _request) return;
      if (minimumZoneVersion != null && (feed.meta.zoneVersion ?? minimumZoneVersion) < minimumZoneVersion) {
        throw const ApiErrorEnvelope(code: 'STALE_ZONE', message: 'Data untuk zona terbaru belum tersedia.');
      }
      final seen = <String>{};
      items = [if (more) ...items, ...feed.items].where((report) => seen.add(report.id)).toList();
      page = feed.page; meta = feed.meta; lastLoadedAt = DateTime.now().toUtc();
    } catch (failure) {
      if (request != _request) return;
      zoneRequired = failure is ApiErrorEnvelope && failure.code == 'ZONE_REQUIRED';
      if (more) { loadMoreError = reportError(failure); } else { error = reportError(failure); }
    } finally {
      if (request == _request) { initialLoading = refreshing = loadingMore = false; changed(); }
    }
  }
}
