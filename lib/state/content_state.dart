import "dart:async";
import "dart:typed_data";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:echoscribe/models/transcription_item.dart";
import "package:echoscribe/models/enums.dart";

class ContentState extends ChangeNotifier {
  OutputMode _outputMode = OutputMode.transcription;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isGeneratingImage = false;

  final ValueNotifier<String> currentTranscript = ValueNotifier("");
  final ValueNotifier<String> sourceTranscript = ValueNotifier("");
  final ValueNotifier<String> currentSummary = ValueNotifier("");
  final ValueNotifier<Uint8List?> currentImageBytes = ValueNotifier(null);

  String get currentTranscriptValue => currentTranscript.value;
  String get sourceTranscriptValue => sourceTranscript.value;
  String get currentSummaryValue => currentSummary.value;

  String? _activeHistoryId;
  final List<TranscriptionItem> _history = <TranscriptionItem>[];

  final ValueNotifier<Duration> recordDuration = ValueNotifier(Duration.zero);
  final ValueNotifier<String> logText = ValueNotifier("");
  Timer? _timer;

  OutputMode get outputMode => _outputMode;
  bool get isSummaryMode => _outputMode == OutputMode.summary;
  void setOutputMode(OutputMode mode) {
    _outputMode = mode;
    notifyListeners();
  }

  bool get isRecording => _isRecording;
  void setRecording(bool value) { _isRecording = value; notifyListeners(); }

  bool get isTranscribing => _isTranscribing;
  void setTranscribing(bool value) { _isTranscribing = value; notifyListeners(); }

  bool get isGeneratingImage => _isGeneratingImage;
  void setGeneratingImage(bool value) { _isGeneratingImage = value; notifyListeners(); }

  void setCurrentTranscript(String text, {bool isSource = false}) {
    currentTranscript.value = text;
    if (isSource) sourceTranscript.value = text;
    notifyListeners(); // Still notify for general state changes if needed
  }

  void setSourceTranscript(String text) {
    sourceTranscript.value = text;
    notifyListeners();
  }

  void setCurrentSummary(String text) {
    currentSummary.value = text;
    notifyListeners();
  }

  void setCurrentImageBytes(Uint8List? bytes) {
    currentImageBytes.value = bytes;
    notifyListeners();
  }

  void clearTranscription() {
    currentTranscript.value = "";
    sourceTranscript.value = "";
    currentSummary.value = "";
    currentImageBytes.value = null;
    logText.value = "";
    notifyListeners();
  }

  void appendLogLine(String line) {
    if (logText.value.isEmpty) {
      logText.value = line;
    } else {
      logText.value = "${logText.value}\n$line";
    }
  }

  void clearLog() {
    logText.value = "";
  }

  Future<void> addToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  String? get activeHistoryId => _activeHistoryId;
  void setActiveHistory(String? id) {
    _activeHistoryId = id;
    notifyListeners();
  }

  List<TranscriptionItem> get history => List.unmodifiable(_history);

  void addHistory(TranscriptionItem item) {
    _history.insert(0, item);
    notifyListeners();
  }

  void updateActiveHistory({String? transcript, String? summary, String? mode, String? text, DateTime? createdAt, Duration? duration, String? language}) {
    if (_activeHistoryId == null) return;
    final idx = _history.indexWhere((e) => e.id == _activeHistoryId);
    if (idx == -1) return;
    final current = _history[idx];
    _history[idx] = current.copyWith(
      transcript: transcript ?? current.transcript,
      summary: summary ?? current.summary,
      mode: mode ?? current.mode,
      text: text ?? current.text,
      createdAt: createdAt ?? current.createdAt,
      duration: duration ?? current.duration,
      language: language ?? current.language,
    );
    notifyListeners();
  }

  void deleteHistoryItem(String id) {
    _history.removeWhere((e) => e.id == id);
    if (_activeHistoryId == id) _activeHistoryId = null;
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _activeHistoryId = null;
    notifyListeners();
  }

  void startTimer() {
    recordDuration.value = Duration.zero;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      recordDuration.value += const Duration(seconds: 1);
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    recordDuration.dispose();
    logText.dispose();
    currentTranscript.dispose();
    sourceTranscript.dispose();
    currentSummary.dispose();
    currentImageBytes.dispose();
    super.dispose();
  }
}
