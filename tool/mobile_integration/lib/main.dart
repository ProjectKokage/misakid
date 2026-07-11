import 'dart:io';

import 'package:flutter/material.dart';
import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';

typedef BundledBackendProbe =
    Future<BundledBackendProbeResult> Function({
      required String dictionaryPath,
      required String wordListPath,
    });

typedef BundledOpenJtalkProbe =
    Future<BundledBackendProbeResult> Function({
      required String dictionaryPath,
    });

final class BundledBackendProbeResult {
  const BundledBackendProbeResult({
    required this.backend,
    required this.input,
    required this.phonemes,
  });

  final BackendInfo backend;
  final String input;
  final String phonemes;
}

Future<BundledBackendProbeResult> probeBundledBackend({
  required String dictionaryPath,
  required String wordListPath,
}) async {
  final wordListBytes = await File(wordListPath).readAsBytes();
  final backend = await MecabJapaneseCutletBackend.openBundled(
    dictionaryPath: dictionaryPath,
    wordListBytes: wordListBytes,
  );
  try {
    const input = '日本語です';
    final result = JapaneseCutletEngine(backend: backend).convert(input);
    if (result.tokens != null) {
      throw StateError('Cutlet mode unexpectedly returned token details.');
    }
    return BundledBackendProbeResult(
      backend: backend.info,
      input: input,
      phonemes: result.phonemes,
    );
  } finally {
    backend.close();
  }
}

Future<BundledBackendProbeResult> probeBundledOpenJtalk({
  required String dictionaryPath,
}) async {
  final backend = await OpenJtalkFrontendBackend.openBundled(
    dictionaryPath: dictionaryPath,
  );
  try {
    const input = '日本語です';
    final result = JapanesePyopenjtalkEngine(backend: backend).convert(input);
    if (result.tokens == null) {
      throw StateError('Open JTalk mode unexpectedly returned no tokens.');
    }
    return BundledBackendProbeResult(
      backend: backend.info,
      input: input,
      phonemes: result.phonemes,
    );
  } finally {
    backend.close();
  }
}

void main() {
  runApp(const MobileIntegrationApp());
}

class MobileIntegrationApp extends StatelessWidget {
  const MobileIntegrationApp({
    super.key,
    this.probe = probeBundledBackend,
    this.openJtalkProbe = probeBundledOpenJtalk,
  });

  final BundledBackendProbe probe;
  final BundledOpenJtalkProbe openJtalkProbe;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Misakid mobile integration',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MobileIntegrationHome(probe: probe, openJtalkProbe: openJtalkProbe),
    );
  }
}

class MobileIntegrationHome extends StatefulWidget {
  const MobileIntegrationHome({
    required this.probe,
    required this.openJtalkProbe,
    super.key,
  });

  final BundledBackendProbe probe;
  final BundledOpenJtalkProbe openJtalkProbe;

  @override
  State<MobileIntegrationHome> createState() => _MobileIntegrationHomeState();
}

class _MobileIntegrationHomeState extends State<MobileIntegrationHome> {
  final _dictionaryController = TextEditingController();
  final _wordListController = TextEditingController();
  final _openJtalkDictionaryController = TextEditingController();
  var _status = 'Provide external resource paths to probe the bundled asset.';
  var _busy = false;

  @override
  void dispose() {
    _dictionaryController.dispose();
    _wordListController.dispose();
    _openJtalkDictionaryController.dispose();
    super.dispose();
  }

  Future<void> _probeOpenJtalk() async {
    final dictionaryPath = _openJtalkDictionaryController.text.trim();
    if (dictionaryPath.isEmpty) {
      setState(() {
        _status = 'The Open JTalk dictionary path is required.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Opening bundled Open JTalk asset…';
    });
    try {
      final result = await widget.openJtalkProbe(
        dictionaryPath: dictionaryPath,
      );
      if (!mounted) return;
      setState(() {
        _status =
            'G2P ready: ${result.backend.name} ${result.backend.version}\n'
            '${result.input} → ${result.phonemes}';
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Probe failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _probe() async {
    final dictionaryPath = _dictionaryController.text.trim();
    final wordListPath = _wordListController.text.trim();
    if (dictionaryPath.isEmpty || wordListPath.isEmpty) {
      setState(() {
        _status = 'Both absolute resource paths are required.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Opening bundled native asset…';
    });
    try {
      final result = await widget.probe(
        dictionaryPath: dictionaryPath,
        wordListPath: wordListPath,
      );
      if (!mounted) return;
      setState(() {
        _status =
            'G2P ready: ${result.backend.name} ${result.backend.version}\n'
            '${result.input} → ${result.phonemes}';
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Probe failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Misakid native-asset probe')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Text(
            'UniDic 3.1.0 and the pinned ja_words.txt remain external. '
            'Enter materialized absolute paths on the device.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('dictionaryPath'),
            controller: _dictionaryController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'UniDic directory path',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('wordListPath'),
            controller: _wordListController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'ja_words.txt path',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('probeButton'),
            onPressed: _busy ? null : _probe,
            child: Text(_busy ? 'Opening…' : 'Probe bundled backend'),
          ),
          const SizedBox(height: 28),
          TextField(
            key: const Key('openJtalkDictionaryPath'),
            controller: _openJtalkDictionaryController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Open JTalk dictionary path',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('openJtalkProbeButton'),
            onPressed: _busy ? null : _probeOpenJtalk,
            child: Text(_busy ? 'Opening…' : 'Probe Open JTalk backend'),
          ),
          const SizedBox(height: 16),
          SelectableText(_status, key: const Key('status')),
        ],
      ),
    );
  }
}
