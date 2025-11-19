import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // Required for Web Microphone access
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // For MediaType
import 'package:speech_frontend/controller/soniox_controller.dart';
import 'package:speech_frontend/view/widgets/custom_input_chip.dart'
    show HoverChip;

// =====================================================
// 1️⃣ MODELS
// =====================================================

class ConversationEntry {
  String original;
  String translation;
  String langCode;
  String speaker;
  int endMs;

  ConversationEntry({
    required this.original,
    required this.translation,
    required this.langCode,
    required this.speaker,
    required this.endMs,
  });
}

class EntityItem {
  final String text;
  final String label;
  final double confidence;
  final int start;
  final int end;

  EntityItem({
    required this.text,
    required this.label,
    required this.confidence,
    required this.start,
    required this.end,
  });

  factory EntityItem.fromJson(Map<String, dynamic> json) {
    return EntityItem(
      text: json['text'] ?? '',
      label: json['label'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      start: json['start'] ?? 0,
      end: json['end'] ?? 0,
    );
  }
}

// =====================================================
// 2️⃣ MAIN WIDGETS
// =====================================================

class PulsingMicIcon extends StatefulWidget {
  final bool isListening;
  final double size;

  const PulsingMicIcon({
    super.key,
    required this.isListening,
    this.size = 24.0,
  });

  @override
  State<PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.isListening) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingMicIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening != oldWidget.isListening) {
      if (widget.isListening) {
        _animationController.repeat(reverse: true);
      } else {
        _animationController.stop();
        _animationController.reset();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Icon(
        widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: widget.isListening ? Colors.red : Colors.blue.shade700,
        size: widget.size,
      ),
    );
  }
}

class LiveTranslatorView extends StatefulWidget {
  const LiveTranslatorView({super.key});

  @override
  State<LiveTranslatorView> createState() => _LiveTranslatorViewState();
}

class _LiveTranslatorViewState extends State<LiveTranslatorView> {
  // --- Controllers ---
  late SonioxController _translationController;
  final TextEditingController _editController = TextEditingController();

  // --- State ---
  bool _isRecording = false;
  bool _isPaused = false;
  bool _enableDiarization = true;
  bool _isEditListening = false;
  bool _isProcessingText = false;
  bool _hasText = false;

  // --- NER Data (Comprehensive) ---
  Map<String, dynamic> _comprehensiveNerData = {};

  // --- Subscriptions ---
  late StreamSubscription _nerSubscription;

  // --- Audio Recording State ---
  html.MediaRecorder? _mediaRecorder;
  html.MediaStream? _mediaStream;
  List<html.Blob> _audioChunks = [];

  // --- Configuration ---
  final Map<String, String> _sourceLanguages = {
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'hi': 'Hindi',
    'ml': 'Malayalam',
  };

  // 🔗 API ENDPOINTS
  final String _voiceEditApiUrl =
      "https://voicebackend.oxzygen.com/api/process-audio-command";
  // final String _textEditApiUrl = "https://voicebackend.oxzygen.com/api/process-text-command";
  final String _textEditApiUrl =
      "http://localhost:8000/api/process-text-command";
  // =====================================================
  // 3️⃣ LIFECYCLE
  // =====================================================

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _editController.addListener(() {
      setState(() {
        _hasText = _editController.text.trim().isNotEmpty;
      });
    });
  }

  void _initializeControllers() {
    _translationController = SonioxController();

    _nerSubscription = _translationController.nerStream.listen((newData) {
      setState(() {
        _comprehensiveNerData = _mergeNerData(_comprehensiveNerData, newData);
      });
    });
  }

  @override
  void dispose() {
    _translationController.dispose();
    _nerSubscription.cancel();
    _editController.dispose();
    _mediaRecorder?.stop();
    _mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  // =====================================================
  // 4️⃣ NER DATA PROCESSING
  // =====================================================

  Map<String, dynamic> _mergeNerData(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;

    final merged = Map<String, dynamic>.from(existing);

    final categories = [
      'medications',
      'diseases',
      'diagnostic_procedures',
      'therapeutic_procedures',
      'symptoms_raw',
      'dates',
      'times',
      'durations',
      'frequencies',
      'ages',
      'dosages',
      'administrations',
      'lab_values',
      'masses',
      'heights',
      'weights',
      'volumes',
      'distances',
      'biological_structures',
      'areas',
      'biological_attributes',
      'clinical_events',
      'outcomes',
      'severities',
      'activities',
      'sex',
      'occupations',
      'family_history',
      'personal_background',
      'history',
      'colors',
      'shapes',
      'textures',
      'detailed_descriptions',
      'qualitative_concepts',
      'quantitative_concepts',
      'nonbiological_locations',
      'subjects',
      'coreferences',
      'other_events',
      'other_entities',
    ];

    for (final category in categories) {
      if (incoming.containsKey(category)) {
        final existingList = (merged[category] as List?) ?? [];
        final incomingList = (incoming[category] as List?) ?? [];

        final existingTexts = existingList
            .map((e) => (e is Map ? e['text'] : '').toString().toLowerCase())
            .toSet();

        final newItems = incomingList.where((item) {
          final text = (item is Map ? item['text'] : '')
              .toString()
              .toLowerCase();
          return !existingTexts.contains(text);
        }).toList();

        merged[category] = [...existingList, ...newItems];
      }
    }

    _mergeStructuredData(merged, incoming, 'prescriptions', 'medication');
    _mergeStructuredData(merged, incoming, 'symptoms', 'symptom');
    _mergeStructuredData(merged, incoming, 'procedures', 'procedure');
    _mergeStructuredData(merged, incoming, 'follow_ups', 'event');

    if (incoming.containsKey('total_entities')) {
      merged['total_entities'] = incoming['total_entities'];
    }
    if (incoming.containsKey('entity_count_by_category')) {
      merged['entity_count_by_category'] = incoming['entity_count_by_category'];
    }

    return merged;
  }

  void _mergeStructuredData(
    Map<String, dynamic> merged,
    Map<String, dynamic> incoming,
    String key,
    String uniqueField,
  ) {
    if (!incoming.containsKey(key)) return;

    final existingList = (merged[key] as List?) ?? [];
    final incomingList = (incoming[key] as List?) ?? [];

    final itemMap = <String, Map<String, dynamic>>{};

    for (final item in existingList) {
      if (item is Map<String, dynamic>) {
        final id = item[uniqueField]?.toString() ?? '';
        if (id.isNotEmpty) itemMap[id] = item;
      }
    }

    for (final item in incomingList) {
      if (item is Map<String, dynamic>) {
        final id = item[uniqueField]?.toString() ?? '';
        if (id.isNotEmpty) {
          if (itemMap.containsKey(id)) {
            final existing = itemMap[id]!;
            final existingFields = existing.values
                .where((v) => v != null)
                .length;
            final incomingFields = item.values.where((v) => v != null).length;
            if (incomingFields > existingFields) {
              itemMap[id] = item;
            }
          } else {
            itemMap[id] = item;
          }
        }
      }
    }
    merged[key] = itemMap.values.toList();
  }

  // =====================================================
  // 5️⃣ CONTROL ACTIONS
  // =====================================================

  void _onStart() {
    _translationController.dispose();
    _nerSubscription.cancel();

    _initializeControllers();

    final langCodes = _sourceLanguages.keys.toList();
    _translationController.start(
      sourceLanguages: langCodes,
      enableSpeakerDiarization: _enableDiarization,
    );

    setState(() {
      _isRecording = true;
      _isPaused = false;
      _comprehensiveNerData = {};
    });
  }

  void _onStop() {
    _translationController.stop();
    _stopEditRecording();
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
  }

  void _onPause() {
    _translationController.pause();
    setState(() => _isPaused = true);
  }

  void _onResume() {
    _translationController.resume();
    setState(() => _isPaused = false);
  }

  // =====================================================
  // 6️⃣ EDITING FUNCTIONS (VOICE & TEXT)
  // =====================================================

  void _toggleEditRecording() {
    if (_isEditListening) {
      _stopEditRecording();
    } else {
      _startEditRecording();
    }
  }

  Future<void> _startEditRecording() async {
    if (_isRecording && !_isPaused) {
      _translationController.pause();
    }

    try {
      _mediaStream = await html.window.navigator.mediaDevices!.getUserMedia({
        'audio': {'sampleRate': 16000, 'channelCount': 1},
      });

      _mediaRecorder = html.MediaRecorder(_mediaStream!, {
        'mimeType': 'audio/webm',
      });
      _audioChunks = [];

      _mediaRecorder!.addEventListener('dataavailable', (event) {
        final data = (event as dynamic).data;
        if (data != null && data.size > 0) {
          _audioChunks.add(data);
        }
      });

      _mediaRecorder!.addEventListener('stop', (event) {
        final audioBlob = html.Blob(_audioChunks, 'audio/webm');
        _sendAudioToBackend(audioBlob);

        _mediaStream?.getTracks().forEach((track) => track.stop());
        _mediaStream = null;
        _mediaRecorder = null;

        if (_isRecording) {
          _translationController.resume();
        }
      });

      _mediaRecorder!.start();
      setState(() => _isEditListening = true);
    } catch (e) {
      debugPrint('Error starting microphone: $e');
      _showEditConfirmation("Error: Could not start microphone.");
      if (_isRecording) {
        _translationController.resume();
      }
    }
  }

  void _stopEditRecording() {
    if (_mediaRecorder != null && _mediaRecorder!.state == 'recording') {
      _mediaRecorder!.stop();
    }
    setState(() => _isEditListening = false);
  }

  Future<void> _sendAudioToBackend(html.Blob audioBlob) async {
    _showEditConfirmation("Processing audio command...", duration: 5000);

    try {
      var uri = Uri.parse(_voiceEditApiUrl);
      var request = http.MultipartRequest("POST", uri);

      request.fields['context'] = json.encode(_comprehensiveNerData);

      final reader = html.FileReader();
      reader.readAsArrayBuffer(audioBlob);
      await reader.onLoad.first;

      final audioBytes = reader.result as List<int>;

      request.files.add(
        http.MultipartFile.fromBytes(
          'audio',
          audioBytes,
          filename: 'audio.webm',
          contentType: MediaType('audio', 'webm'),
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _handleEditResponse(responseData);
      } else {
        _showEditConfirmation("Error: Server returned ${response.statusCode}");
      }
    } catch (e) {
      _showEditConfirmation("Error: ${e.toString()}");
    }
  }

  Future<void> _sendTextToBackend() async {
    final text = _editController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isProcessingText = true;
    });
    _editController.clear();
    _showEditConfirmation("Processing text command...", duration: 2000);

    try {
      final uri = Uri.parse(_textEditApiUrl);
      final body = jsonEncode({
        "command": text,
        "context": _comprehensiveNerData,
      });

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _handleEditResponse(responseData);
      } else {
        print("Server Error: ${response.body}");
        _showEditConfirmation("Error: Server returned ${response.statusCode}");
      }
    } catch (e) {
      print("Network Error: $e");
      _showEditConfirmation("Error: ${e.toString()}");
    } finally {
      setState(() {
        _isProcessingText = false;
      });
    }
  }

  void _handleEditResponse(Map<String, dynamic> responseData) {
    final answer = responseData['answer'] ?? 'Entities updated';

    final dataOnly = Map<String, dynamic>.from(responseData);
    dataOnly.remove('answer');

    setState(() {
      _comprehensiveNerData = dataOnly;
    });

    _showEditConfirmation(answer);
  }

  void _showEditConfirmation(String message, {int duration = 2000}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(milliseconds: duration),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(100, 20, 100, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _removeItem(String categoryKey, Map<String, dynamic> itemToRemove) {
    setState(() {
      if (_comprehensiveNerData.containsKey(categoryKey)) {
        final List list = _comprehensiveNerData[categoryKey];
        list.remove(itemToRemove);
        _comprehensiveNerData['total_entities'] =
            (_comprehensiveNerData['total_entities'] ?? 1) - 1;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Item Removed"),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  // =====================================================
  // ✨ HELPER: Get text regardless of JSON key
  // =====================================================
  String _getSmartDisplayText(Map<String, dynamic> item) {
    // 1. Try standard 'text' key
    if (item['text'] != null && item['text'].toString().isNotEmpty) {
      return item['text'].toString();
    }
    // 2. Try 'medication' (Common LLM output for prescriptions)
    if (item['medication'] != null &&
        item['medication'].toString().isNotEmpty) {
      return item['medication'].toString();
    }

    // 3. Try 'symptom' (Common LLM output for symptoms)
    if (item['symptom'] != null && item['symptom'].toString().isNotEmpty) {
      return item['symptom'].toString();
    }

    // 4. Try 'procedure'
    if (item['procedure'] != null && item['procedure'].toString().isNotEmpty) {
      return item['procedure'].toString();
    }

    // 5. Try 'word' (Raw HuggingFace output)
    if (item['word'] != null && item['word'].toString().isNotEmpty) {
      return item['word'].toString();
    }

    // 6. Try 'value' (Generic fallback)
    if (item['value'] != null && item['value'].toString().isNotEmpty) {
      return item['value'].toString();
    }

    return ''; // Return empty string if no text found
  }

  // =====================================================
  // 7️⃣ UI BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprehensive Medical NER'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      backgroundColor: const Color(0xFFF0F2F5),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1800),
          child: Column(
            children: [
              _buildConfigPanel(),
              _buildControls(),
              _buildStats(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 1, child: _buildConversationLog()),
                    Expanded(flex: 1, child: _buildComprehensiveNerPanel()),
                  ],
                ),
              ),
              _buildEditInputPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Enable Speaker Diarization'),
            value: _enableDiarization,
            onChanged: _isRecording
                ? null
                : (val) => setState(() => _enableDiarization = val),
            activeThumbColor: Colors.blue.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(_isRecording ? 'Stop' : 'Start'),
            onPressed: _isRecording ? _onStop : _onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording
                  ? Colors.red.shade700
                  : Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            label: Text(_isPaused ? 'Resume' : 'Pause'),
            onPressed: _isRecording ? (_isPaused ? _onResume : _onPause) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final totalEntities = _comprehensiveNerData['total_entities'] ?? 0;
    final categoryCount =
        (_comprehensiveNerData['entity_count_by_category'] as Map?)?.length ??
        0;

    if (totalEntities == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            'Extracted $totalEntities entities across $categoryCount categories',
            style: TextStyle(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationLog() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.fromLTRB(16, 0, 8, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Conversation',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<ConversationEntry>>(
              key: ValueKey(_translationController.hashCode),
              stream: _translationController.conversationStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isRecording) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Listening...'),
                        ] else ...[
                          Icon(
                            Icons.mic_none,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          const Text('Press Start to begin'),
                        ],
                      ],
                    ),
                  );
                }
                final log = snapshot.data!;
                return ListView.builder(
                  itemCount: log.length,
                  itemBuilder: (context, index) =>
                      _buildConversationBubble(log[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComprehensiveNerPanel() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.fromLTRB(8, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Medical Entities (41 Types)',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: _comprehensiveNerData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isRecording
                              ? 'Listening for medical terms...'
                              : 'Start recording to extract entities',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStructuredSection(),
                        const Divider(height: 24),
                        _buildCategorizedEntities(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredSection() {
    final prescriptions =
        (_comprehensiveNerData['prescriptions'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final symptoms =
        (_comprehensiveNerData['symptoms'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final procedures =
        (_comprehensiveNerData['procedures'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final followUps =
        (_comprehensiveNerData['follow_ups'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final diseases =
        (_comprehensiveNerData['diseases'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final anatomy =
        (_comprehensiveNerData['biological_structures'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STRUCTURED DATA',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),

        if (prescriptions.isNotEmpty)
          _buildEntitySection(
            '💊 Prescriptions',
            Colors.blue,
            prescriptions,
            (item) =>
                '${item['medication']} ${item['dosage'] ?? ''} ${item['frequency'] ?? ''}'
                    .trim(),
            'prescriptions',
          ),

        if (symptoms.isNotEmpty)
          _buildEntitySection(
            '🩺 Symptoms',
            Colors.red,
            symptoms,
            (item) => '${item['symptom']} ${item['duration'] ?? ''}'.trim(),
            'symptoms',
          ),

        if (diseases.isNotEmpty)
          _buildEntitySection(
            '🦠 Diseases',
            Colors.red.shade700,
            diseases,
            (item) => item['text'] ?? '',
            'diseases',
          ),

        if (anatomy.isNotEmpty)
          _buildEntitySection(
            '🫀 Anatomy',
            Colors.pink,
            anatomy,
            (item) => item['text'] ?? '',
            'biological_structures',
          ),

        if (procedures.isNotEmpty)
          _buildEntitySection(
            '🔬 Procedures',
            Colors.purple,
            procedures,
            (item) => '${item['procedure']} (${item['procedure_type']})',
            'procedures',
          ),

        if (followUps.isNotEmpty)
          _buildEntitySection(
            '📅 Follow-ups',
            Colors.orange,
            followUps,
            (item) => '${item['event']} ${item['timeframe'] ?? ''}'.trim(),
            'follow_ups',
          ),
      ],
    );
  }

  Widget _buildCategorizedEntities() {
    final categories = [
      {
        'key': 'medications',
        'title': 'Medications',
        'icon': '💊',
        'color': Colors.blue,
      },
      {
        'key': 'symptoms_raw',
        'title': 'Symptoms',
        'icon': '🤒',
        'color': Colors.red,
      },
      {
        'key': 'diseases',
        'title': 'Diseases',
        'icon': '🦠',
        'color': Colors.red.shade700,
      },
      {
        'key': 'lab_values',
        'title': 'Lab Values',
        'icon': '🧪',
        'color': Colors.cyan,
      },
      {
        'key': 'biological_structures',
        'title': 'Anatomy',
        'icon': '🫀',
        'color': Colors.pink,
      },
      {
        'key': 'dosages',
        'title': 'Dosages',
        'icon': '💉',
        'color': Colors.green,
      },
      {
        'key': 'durations',
        'title': 'Durations',
        'icon': '⏱️',
        'color': Colors.indigo,
      },
      {
        'key': 'frequencies',
        'title': 'Frequencies',
        'icon': '🔄',
        'color': Colors.teal,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ALL EXTRACTED ENTITIES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        ...categories.map((cat) {
          final entities =
              (_comprehensiveNerData[cat['key']] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          if (entities.isEmpty) return const SizedBox.shrink();
          return _buildEntitySection(
            '${cat['icon']} ${cat['title']}',
            cat['color'] as Color,
            entities,
            (item) => _getSmartDisplayText(item),
            cat['key'] as String,
          );
        }),
      ],
    );
  }

  Widget _buildEntitySection(
    String title,
    Color color,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) textBuilder,
    String categoryKey,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: items.map((item) {
              final text = textBuilder(item);
              return HoverChip(
                text: text,
                color: color,
                onDelete: () => _removeItem(categoryKey, item),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationBubble(ConversationEntry entry) {
    final isSpeakerA = (entry.speaker == '1');
    final bubbleColor = isSpeakerA ? Colors.blue.shade50 : Colors.green.shade50;
    final alignment = isSpeakerA
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            'Speaker ${entry.speaker}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.original,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (entry.translation != '...') ...[
                  const Divider(height: 12, thickness: 1),
                  Text(
                    entry.translation,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Translating...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 8️⃣ EDIT INPUT PANEL
  // =====================================================

  Widget _buildEditInputPanel() {
    return FractionallySizedBox(
      widthFactor: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _editController,
                  onSubmitted: (_) => _sendTextToBackend(),
                  decoration: InputDecoration(
                    hintText: _isEditListening
                        ? 'Recording audio command...'
                        : 'Type to edit (e.g. "Add Dolo", "Remove fever") or use mic...',
                    hintStyle: TextStyle(
                      color: _isEditListening
                          ? Colors.red.withOpacity(0.7)
                          : Colors.grey.shade500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    enabled: !_isEditListening && !_isProcessingText,
                  ),
                ),
              ),
            ),
            if (_isProcessingText)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_hasText && !_isEditListening)
              IconButton(
                icon: const Icon(Icons.send_rounded),
                color: Colors.blue.shade700,
                tooltip: 'Send text command',
                onPressed: _sendTextToBackend,
              ),
            Container(
              height: 24,
              width: 1,
              color: Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            IconButton(
              icon: PulsingMicIcon(isListening: _isEditListening),
              tooltip: 'Record audio command',
              onPressed: _isProcessingText ? null : _toggleEditRecording,
            ),
          ],
        ),
      ),
    );
  }
}
