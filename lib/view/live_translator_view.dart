import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http; // No longer needed
import 'package:speech_frontend/controller/soniox_controller.dart';

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
// 2️⃣ MAIN WIDGET
// =====================================================

class LiveTranslatorView extends StatefulWidget {
  const LiveTranslatorView({super.key});

  @override
  State<LiveTranslatorView> createState() => _LiveTranslatorViewState();
}

class _LiveTranslatorViewState extends State<LiveTranslatorView> {
  // --- Controllers ---
  late SonioxController _translationController;
  // 🛑 REMOVED: _chatSttController
  // 🛑 REMOVED: _chatController

  // --- State ---
  bool _isRecording = false;
  bool _isPaused = false;
  bool _enableDiarization = true;
  // 🛑 REMOVED: _isChatListening

  // --- NER Data (Comprehensive) ---
  Map<String, dynamic> _comprehensiveNerData = {};

  // 🛑 REMOVED: _chatMessages

  // --- Subscriptions ---
  late StreamSubscription _nerSubscription;
  // 🛑 REMOVED: _chatStreamSubscription

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

  // 🛑 REMOVED: _chatApiUrl

  // =====================================================
  // 3️⃣ LIFECYCLE
  // =====================================================

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _translationController = SonioxController();
    // 🛑 REMOVED: _chatSttController

    _nerSubscription = _translationController.nerStream.listen((newData) {
      setState(() {
        _comprehensiveNerData = _mergeNerData(_comprehensiveNerData, newData);
      });
    });

    // 🛑 REMOVED: _chatStreamSubscription
  }

  @override
  void dispose() {
    _translationController.dispose();
    _nerSubscription.cancel();
    // 🛑 REMOVED: chat controller and subscription disposals
    super.dispose();
  }

  // =====================================================
  // 4️⃣ NER DATA PROCESSING
  // =====================================================

  Map<String, dynamic> _mergeNerData(
      Map<String, dynamic> existing, Map<String, dynamic> incoming) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;

    final merged = Map<String, dynamic>.from(existing);

    // Merge entity lists by category
    final categories = [
      'medications', 'diseases', 'diagnostic_procedures', 'therapeutic_procedures',
      'symptoms_raw', 'dates', 'times', 'durations', 'frequencies', 'ages',
      'dosages', 'administrations', 'lab_values', 'masses', 'heights', 'weights',
      'volumes', 'distances', 'biological_structures', 'areas',
      'biological_attributes', 'clinical_events', 'outcomes', 'severities',
      'activities', 'sex', 'occupations', 'family_history', 'personal_background',
      'history', 'colors', 'shapes', 'textures', 'detailed_descriptions',
      'qualitative_concepts', 'quantitative_concepts', 'nonbiological_locations',
      'subjects', 'coreferences', 'other_events', 'other_entities'
    ];

    for (final category in categories) {
      if (incoming.containsKey(category)) {
        final existingList = (merged[category] as List?) ?? [];
        final incomingList = (incoming[category] as List?) ?? [];

        // Create a set of existing texts to avoid duplicates
        final existingTexts = existingList
            .map((e) => (e is Map ? e['text'] : '').toString().toLowerCase())
            .toSet();

        // Add only new items
        final newItems = incomingList.where((item) {
          final text = (item is Map ? item['text'] : '').toString().toLowerCase();
          return !existingTexts.contains(text);
        }).toList();

        merged[category] = [...existingList, ...newItems];
      }
    }

    // Merge structured data (prescriptions, symptoms, procedures, follow_ups)
    _mergeStructuredData(merged, incoming, 'prescriptions', 'medication');
    _mergeStructuredData(merged, incoming, 'symptoms', 'symptom');
    _mergeStructuredData(merged, incoming, 'procedures', 'procedure');
    _mergeStructuredData(merged, incoming, 'follow_ups', 'event');

    // Update statistics
    if (incoming.containsKey('total_entities')) {
      merged['total_entities'] = incoming['total_entities'];
    }
    if (incoming.containsKey('entity_count_by_category')) {
      merged['entity_count_by_category'] = incoming['entity_count_by_category'];
    }

    return merged;
  }

  void _mergeStructuredData(Map<String, dynamic> merged,
      Map<String, dynamic> incoming, String key, String uniqueField) {
    if (!incoming.containsKey(key)) return;

    final existingList = (merged[key] as List?) ?? [];
    final incomingList = (incoming[key] as List?) ?? [];

    // Create map for deduplication
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
          // If item exists, merge with more complete data
          if (itemMap.containsKey(id)) {
            final existing = itemMap[id]!;
            final existingFields = existing.values.where((v) => v != null).length;
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
    // 🛑 REMOVED: chat controller and subscription disposals

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
      // 🛑 REMOVED: _chatMessages.clear();
    });
  }

  void _onStop() {
    _translationController.stop();
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
  // 6️⃣ CHAT FUNCTIONS
  // =====================================================

  // 🛑 REMOVED: All chat functions
  // _onSendChatMessage
  // _onToggleChatListen
  // _onChatResult
  // _processChatCommand
  // _addBotResponse

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
              _buildConfigPanel(), // ✨ MODIFIED to remove languages
              _buildControls(),
              _buildStats(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✨ MODIFIED: Changed to flex: 1
                    Expanded(flex: 1, child: _buildConversationLog()),
                    // ✨ MODIFIED: Changed to flex: 1
                    Expanded(flex: 1, child: _buildComprehensiveNerPanel()),
                    // 🛑 REMOVED: _buildChatPanel()
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // 8️⃣ UI COMPONENTS
  // =====================================================

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
          // 🛑 REMOVED: Language selection Text and Wrap
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
              backgroundColor:
                  _isRecording ? Colors.red.shade700 : Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            icon:
                Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
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
        (_comprehensiveNerData['entity_count_by_category'] as Map?)?.length ?? 0;

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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
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
                          Icon(Icons.mic_none,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('Press Start to begin'),
                        ]
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
      // ✨ MODIFIED: Adjusted margin for 2-column layout
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
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
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
                        Icon(Icons.search,
                            size: 48, color: Colors.grey.shade400),
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
        (_comprehensiveNerData['prescriptions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final symptoms =
        (_comprehensiveNerData['symptoms'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final procedures =
        (_comprehensiveNerData['procedures'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final followUps =
        (_comprehensiveNerData['follow_ups'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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
                      .trim()),
        if (symptoms.isNotEmpty)
          _buildEntitySection(
              '🩺 Symptoms',
              Colors.red,
              symptoms,
              (item) =>
                  '${item['symptom']} ${item['duration'] ?? ''}'.trim()),
        if (procedures.isNotEmpty)
          _buildEntitySection(
              '🔬 Procedures',
              Colors.purple,
              procedures,
              (item) =>
                  '${item['procedure']} (${item['procedure_type']})'),
        if (followUps.isNotEmpty)
          _buildEntitySection(
              '📅 Follow-ups',
              Colors.orange,
              followUps,
              (item) =>
                  '${item['event']} ${item['timeframe'] ?? ''}'.trim()),
      ],
    );
  }

  Widget _buildCategorizedEntities() {
    final categories = [
      {'key': 'medications', 'title': 'Medications', 'icon': '💊', 'color': Colors.blue},
      {'key': 'symptoms_raw', 'title': 'Symptoms', 'icon': '🤒', 'color': Colors.red},
      {'key': 'diseases', 'title': 'Diseases', 'icon': '🦠', 'color': Colors.red.shade700},
      {'key': 'lab_values', 'title': 'Lab Values', 'icon': '🧪', 'color': Colors.cyan},
      {'key': 'biological_structures', 'title': 'Anatomy', 'icon': '🫀', 'color': Colors.pink},
      {'key': 'dosages', 'title': 'Dosages', 'icon': '💉', 'color': Colors.green},
      {'key': 'durations', 'title': 'Durations', 'icon': '⏱️', 'color': Colors.indigo},
      {'key': 'frequencies', 'title': 'Frequencies', 'icon': '🔄', 'color': Colors.teal},
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
              (_comprehensiveNerData[cat['key']] as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (entities.isEmpty) return const SizedBox.shrink();
          return _buildEntitySection(
            '${cat['icon']} ${cat['title']}',
            cat['color'] as Color,
            entities,
            (item) => item['text'] ?? '',
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
              return Chip(
                label: Text(text, style: const TextStyle(fontSize: 12)),
                backgroundColor: color.withOpacity(0.1),
                labelStyle: TextStyle(color: Colors.indigo),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 🛑 REMOVED: _buildChatPanel()
  // 🛑 REMOVED: _buildChatInput()

  Widget _buildConversationBubble(ConversationEntry entry) {
    final isSpeakerA = (entry.speaker == '1');
    final bubbleColor = isSpeakerA ? Colors.blue.shade50 : Colors.green.shade50;
    final alignment =
        isSpeakerA ? CrossAxisAlignment.start : CrossAxisAlignment.end;

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
                      fontSize: 14, fontWeight: FontWeight.w500),
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
}