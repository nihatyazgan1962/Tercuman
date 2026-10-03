import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const TranslatorApp());
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akıllı Tercüman Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      home: const TranslatorHomePage(),
    );
  }
}

class TranslationHistoryItem {
  final String sourceText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  final DateTime timestamp;

  TranslationHistoryItem({
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
    required this.timestamp,
  });
}

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({super.key});

  @override
  State<TranslatorHomePage> createState() => _TranslatorHomePageState();
}

class _TranslatorHomePageState extends State<TranslatorHomePage> {
  // Desteklenen Diller
  final Map<String, String> _languages = {
    'Türkçe': 'tr',
    'İngilizce': 'en',
    'Almanca': 'de',
    'Fransızca': 'fr',
    'İspanyolca': 'es',
    'İtalyanca': 'it',
    'Rusça': 'ru',
    'Arapça': 'ar',
    'Japonca': 'ja',
    'Korece': 'ko',
    'Çince': 'zh',
  };

  // TTS Dil Eşleşmeleri
  final Map<String, String> _ttsLocales = {
    'tr': 'tr-TR',
    'en': 'en-US',
    'de': 'de-DE',
    'fr': 'fr-FR',
    'es': 'es-ES',
    'it': 'it-IT',
    'ru': 'ru-RU',
    'ar': 'ar-SA',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'zh': 'zh-CN',
  };

  String _selectedSourceLang = 'Türkçe';
  String _selectedTargetLang = 'İngilizce';

  final TextEditingController _inputController = TextEditingController();
  String _translatedText = '';
  bool _isLoading = false;

  // TTS & STT
  late FlutterTts _flutterTts;
  late stt.SpeechToText _speech;
  bool _isListening = false;

  // Çeviri Geçmişi & Favoriler
  final List<TranslationHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  void _initSpeech() {
    _speech = stt.SpeechToText();
  }

  Future<void> _speak(String text, String langCode) async {
    if (text.trim().isEmpty) return;
    String locale = _ttsLocales[langCode] ?? 'en-US';
    await _flutterTts.setLanguage(locale);
    await _flutterTts.speak(text);
  }

  Future<void> _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) => setState(() => _isListening = false),
      );

      if (available) {
        setState(() => _isListening = true);
        String srcCode = _languages[_selectedSourceLang] ?? 'tr';
        String localeId = _ttsLocales[srcCode] ?? 'tr-TR';

        _speech.listen(
          localeId: localeId,
          onResult: (val) {
            setState(() {
              _inputController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _translateText() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen çevrilecek bir metin girin.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final srcCode = _languages[_selectedSourceLang] ?? 'tr';
    final targetCode = _languages[_selectedTargetLang] ?? 'en';

    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(query)}&langpair=$srcCode|$targetCode',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translated = data['responseData']['translatedText'];
        setState(() {
          _translatedText = translated ?? 'Çeviri bulunamadı.';
          if (translated != null && translated.toString().isNotEmpty) {
            _history.insert(
              0,
              TranslationHistoryItem(
                sourceText: query,
                translatedText: translated,
                sourceLang: _selectedSourceLang,
                targetLang: _selectedTargetLang,
                timestamp: DateTime.now(),
              ),
            );
          }
        });
      } else {
        setState(() {
          _translatedText = 'Hata: Sunucu yanıt vermedi (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _translatedText = 'Bağlantı hatası: Lütfen internet bağlantınızı kontrol edin.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _swapLanguages() {
    setState(() {
      final temp = _selectedSourceLang;
      _selectedSourceLang = _selectedTargetLang;
      _selectedTargetLang = temp;

      if (_translatedText.isNotEmpty && !_translatedText.startsWith('Hata')) {
        _inputController.text = _translatedText;
        _translatedText = '';
      }
    });
  }

  void _copyToClipboard(String text) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Panoya kopyalandı!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _speech.stop();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate_rounded, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text(
              'Akıllı Tercüman',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF6C63FF)),
            tooltip: 'Hakkında',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.info, color: Color(0xFF6C63FF)),
                      SizedBox(width: 8),
                      Text('Hakkında', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: const Text(
                    'Yazgan İletişim',
                    style: TextStyle(fontSize: 16),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Tamam', style: TextStyle(color: Color(0xFF6C63FF))),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Dil Seçim Çubuğu
              _buildLanguageBar(),
              const SizedBox(height: 16),

              // 2. Giriş Alanı
              _buildInputCard(),
              const SizedBox(height: 16),

              // 3. Çevir Butonu
              _buildTranslateButton(),
              const SizedBox(height: 20),

              // 4. Çeviri Sonucu
              if (_translatedText.isNotEmpty) _buildResultCard(),

              // 5. Çeviri Geçmişi Listesi
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 28),
                _buildHistoryHeader(),
                const SizedBox(height: 12),
                _buildHistoryList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildDropdown(_selectedSourceLang, (val) {
            if (val != null) setState(() => _selectedSourceLang = val);
          }),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.swap_horiz_rounded, size: 24),
              color: const Color(0xFF6C63FF),
              onPressed: _swapLanguages,
              tooltip: 'Dilleri Değiştir',
            ),
          ),
          _buildDropdown(_selectedTargetLang, (val) {
            if (val != null) setState(() => _selectedTargetLang = val);
          }),
        ],
      ),
    );
  }

  Widget _buildDropdown(String current, ValueChanged<String?> onChanged) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: current,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6C63FF)),
        items: _languages.keys.map((lang) {
          return DropdownMenuItem(
            value: lang,
            child: Text(
              lang,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _inputController,
            maxLines: 4,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Metin yazın veya mikrofona konuşun...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded),
                      color: _isListening ? Colors.red : const Color(0xFF6C63FF),
                      onPressed: _listen,
                      tooltip: 'Ses Tanıma (STT)',
                    ),
                    if (_inputController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.volume_up_outlined),
                        color: const Color(0xFF6C63FF),
                        onPressed: () => _speak(
                          _inputController.text,
                          _languages[_selectedSourceLang]!,
                        ),
                        tooltip: 'Dinle (TTS)',
                      ),
                  ],
                ),
                if (_inputController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _inputController.clear();
                        _translatedText = '';
                      });
                    },
                    tooltip: 'Temizle',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslateButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _translateText,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 2,
      ),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.translate_rounded),
                SizedBox(width: 8),
                Text('Çevir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_selectedTargetLang ÇEVİRİSİ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6C63FF),
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20, color: Color(0xFF6C63FF)),
                    onPressed: () => _copyToClipboard(_translatedText),
                    tooltip: 'Kopyala',
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 20, color: Color(0xFF6C63FF)),
                    onPressed: () => _speak(
                      _translatedText,
                      _languages[_selectedTargetLang]!,
                    ),
                    tooltip: 'Seslendir (TTS)',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            _translatedText,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: _translatedText.startsWith('Hata') ||
                      _translatedText.startsWith('Bağlantı')
                  ? Colors.red
                  : const Color(0xFF1E293B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Son Çeviriler',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        TextButton(
          onPressed: () => setState(() => _history.clear()),
          child: const Text('Temizle', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _history[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item.sourceLang} → ${item.targetLang}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C63FF),
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.grey),
                    onPressed: () => _copyToClipboard(item.translatedText),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.sourceText,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                item.translatedText,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
            ],
          ),
        );
      },
    );
  }
}
