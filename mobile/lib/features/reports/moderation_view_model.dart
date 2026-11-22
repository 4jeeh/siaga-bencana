import 'package:flutter/foundation.dart';

import '../../core/network/api_envelope.dart';
import '../../core/session/session_coordinator.dart';
import '../zone/zone_view_model.dart';
import 'report_repository.dart';
import 'report_list_state.dart';
import 'report_dto.dart';

class ModerationViewModel extends ChangeNotifier {
  ModerationViewModel(this.repository, this.session, this.zone) : _generation = session.generation {
    _wasAdmin = admin;
    session.addListener(_sessionChanged);
  }
  final ReportRepository repository;
  final SessionCoordinator session;
  final ZoneViewModel zone;
  Future<void> Function()? refreshReports;
  int _generation, _panel = 0;
  bool _wasAdmin = false;
  final review = ReportListState();
  String? reviewStatusFilter;
  bool get admin => session.user?.role == 'admin' && session.canNavigate;
  Future<void> loadReview({bool more = false}) async {
    if (admin) await review.load((offset) => repository.fetchReports(scope: 'review', status: reviewStatusFilter, offset: offset), notifyListeners, more: more);
  }
  void filterReview(String? status) { reviewStatusFilter = status; review.clear(); loadReview(); }
  ReportDto? panelReport;
  Object? _panelOwner;
  String? _panelId;
  Object? get panelOwner => _panelOwner;
  List<VerificationDto> verifications = [];
  String? photoUrl, photoError, panelError, verificationsError, actionError, conflictMessage;
  String draftReason = '';
  bool panelLoading = false, verificationsLoading = false, actionBusy = false, decisionDialogOpen = false;
  bool _photoRetried = false, photoIsSimulated = false;
  int photoRevision = 0;
  bool get canAudit => panelReport?.isPrivate == true && (admin || panelReport?.reporterId == session.user?.id);
  bool get canClaim => admin && !panelLoading && panelError == null && panelReport?.isPrivate == true && panelReport?.status == 'pending' && panelReport?.reporterId != session.user?.id;
  bool get canDecide => admin && !panelLoading && panelError == null && panelReport?.isPrivate == true && panelReport?.status == 'in_review' && panelReport?.reviewerId == session.user?.id && panelReport?.reporterId != session.user?.id;
  int get reasonLength => draftReason.trim().runes.length;
  bool get validReason => reasonLength >= 10 && reasonLength <= 500;
  void setReason(String value) { if (!actionBusy) { draftReason = value; notifyListeners(); } }
  void _resetPanel() {
    _panel++; _panelOwner = null; _panelId = null;
    panelReport = null; verifications = []; photoUrl = photoError = panelError = verificationsError = actionError = conflictMessage = null;
    draftReason = ''; photoIsSimulated = _photoRetried = panelLoading = verificationsLoading = actionBusy = decisionDialogOpen = false;
  }
  void clear() { review.clear(); reviewStatusFilter = null; _resetPanel(); notifyListeners(); }
  void _sessionChanged() {
    final reset = _generation != session.generation || (_wasAdmin && !admin);
    _generation = session.generation;
    _wasAdmin = admin;
    if (reset) clear();
  }
  void closePanel() { _resetPanel(); notifyListeners(); }
  Future<void> openPanel(ReportDto initial, {bool forceRefresh = false}) => openId(initial.id, initial: initial, forceRefresh: forceRefresh);
  Future<void> openId(String id, {ReportDto? initial, bool forceRefresh = false}) async {
    if (!forceRefresh || _panelId != id) {
      _resetPanel();
      _panelOwner = Object();
      _panelId = id;
    }
    final request = ++_panel;
    panelReport = initial; panelLoading = true; panelError = verificationsError = null;
    verifications = [];
    notifyListeners();
    try {
      final result = await repository.fetchReportDetail(id);
      if (request != _panel) return;
      panelReport = result.data; panelLoading = false; verificationsLoading = canAudit; notifyListeners();
      if (!result.data.hasPhoto) { photoUrl = photoError = null; }
      await Future.wait([
        if (result.data.hasPhoto && photoUrl == null && photoError == null) _loadPhoto(id, request),
        if (canAudit) _loadAudit(id, request),
      ]);
    } catch (error) {
      if (request == _panel) { panelError = reportError(error); panelReport = null; }
    } finally { if (request == _panel) { panelLoading = false; notifyListeners(); } }
  }
  Future<void> _loadAudit(String id, int request) async {
    try {
      final result = await repository.fetchVerifications(id);
      if (request == _panel) verifications = result.items;
    } catch (error) { if (request == _panel) verificationsError = reportError(error); }
    finally { if (request == _panel) { verificationsLoading = false; notifyListeners(); } }
  }
  Future<void> _loadPhoto(String id, int request) async {
    try {
      final data = await repository.fetchPhotoUrl(id);
      if (request == _panel) { photoUrl = data.url; photoIsSimulated = data.isSimulated; photoRevision++; }
    } catch (_) { if (request == _panel) photoError = 'Foto tidak dapat dimuat.'; }
    finally { if (request == _panel) notifyListeners(); }
  }
  Future<void> refreshPhotoUrlOnce({int? revision}) async {
    final report = panelReport;
    if (report == null || photoUrl == null || (revision != null && revision != photoRevision)) return;
    photoUrl = null;
    if (_photoRetried) { photoError = 'Foto tidak dapat dimuat.'; notifyListeners(); return; }
    _photoRetried = true; notifyListeners(); await _loadPhoto(report.id, _panel);
  }
  Future<void> claimActiveReport() => _act(null);
  Future<void> submitDecision(String outcome) => _act(outcome);
  Future<void> _act(String? outcome) async {
    if (actionBusy || (outcome == null ? !canClaim : !canDecide || !validReason || !['verified', 'rejected'].contains(outcome))) return;
    final report = panelReport!;
    final request = _panel;
    final generation = _generation;
    actionBusy = true; actionError = conflictMessage = null; notifyListeners();
    var conflict = false;
    try {
      if (outcome == null) { await repository.claimReport(report.id, report.version!); }
      else { await repository.decideReport(report.id, report.version!, outcome, draftReason); }
      if (request == _panel) draftReason = '';
    } catch (error) {
      if (request != _panel) return;
      conflict = error is ApiErrorEnvelope && error.statusCode == 409;
      actionError = reportError(error);
      if (conflict) conflictMessage = 'Laporan berubah. Memuat status terbaru…';
      if (!conflict && !(error is ApiErrorEnvelope && error.code == 'NETWORK_ERROR')) { actionBusy = false; notifyListeners(); return; }
    }
    if (generation != _generation) return;
    final lists = Future.wait([loadReview(), if (refreshReports != null) refreshReports!()]);
    if (request != _panel) { await lists; return; }
    decisionDialogOpen = false;
    final refreshed = openPanel(report, forceRefresh: true);
    final active = _panel;
    await Future.wait<void>([refreshed, lists.then<void>((_) {})]);
    if (active != _panel) return;
    actionBusy = false;
    final latest = panelReport;
    if (conflict) {
      conflictMessage = latest == null
          ? 'Konflik. Gagal memuat status terbaru.'
          : 'Konflik. Status: ${reportStatusLabels[latest.status]}, versi ${latest.version}, reviewer_id: ${latest.reviewerId ?? "belum ada"}.';
    }
    notifyListeners();
  }
  @override
  void dispose() { review.clear(); _resetPanel(); _generation++; session.removeListener(_sessionChanged); super.dispose(); }
}
