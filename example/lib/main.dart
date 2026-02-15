import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wajuce/wajuce.dart';
import 'package:wav/wav.dart'; // For loading wav files
import 'clock_processor.dart';
import 'oscilloscope_painter.dart';

void main() {
  runApp(const MyApp());
}

class _AudioSettingsData {
  final int bufferSize;
  final int sampleRate;
  final int bitDepth;

  const _AudioSettingsData({
    required this.bufferSize,
    required this.sampleRate,
    required this.bitDepth,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  static const bool _autoDemoEnabled =
      bool.fromEnvironment('WAJUCE_AUTODEMO', defaultValue: false);
  static const bool _autoDemoDisableSyncBeep = bool.fromEnvironment(
      'WAJUCE_AUTODEMO_DISABLE_SYNC_BEEP',
      defaultValue: false);
  static const int _autoDemoStartDelayMs =
      int.fromEnvironment('WAJUCE_AUTODEMO_START_DELAY_MS', defaultValue: 0);

  WAContext? _ctx;
  int _bufferSize = 512;
  int _preferredSampleRate = 44100;
  int _preferredBitDepth = 32;
  double _actualSampleRate = 0.0;
  int _actualBitDepth = 32;
  bool _isApplyingAudioSettings = false;
  late final TabController _tabController;
  bool _autoDemoStarted = false;

  GlobalKey<_DrumPadScreenState> _drumPadKey = GlobalKey<_DrumPadScreenState>();
  GlobalKey<_SequencerScreenState> _sequencerKey =
      GlobalKey<_SequencerScreenState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (_autoDemoEnabled) {
      debugPrint('WAJUCE_AUTODEMO=$_autoDemoEnabled');
    }
    _initEngine();
  }

  Future<void> _initEngine({bool showFeedback = false}) async {
    final previous = _ctx;
    if (previous != null) {
      await previous.close();
    }

    bool sampleRateApplied = false;
    bool bitDepthApplied = false;

    try {
      final ctx = WAContext(
        sampleRate: _preferredSampleRate,
        bufferSize: _bufferSize,
      );
      await ctx.resume();
      sampleRateApplied =
          await ctx.setPreferredSampleRate(_preferredSampleRate.toDouble());
      bitDepthApplied = await ctx.setPreferredBitDepth(_preferredBitDepth);

      if (!mounted) {
        await ctx.close();
        return;
      }

      setState(() {
        _ctx = ctx;
        _actualSampleRate = ctx.sampleRate;
        _actualBitDepth = ctx.bitDepth;
        // Force tab State recreation after context swap so nodes bind to new ctx.
        _drumPadKey = GlobalKey<_DrumPadScreenState>();
        _sequencerKey = GlobalKey<_SequencerScreenState>();
      });

      if (showFeedback) {
        final deviceText =
            'Device I/O ${_actualSampleRate.toStringAsFixed(0)}Hz / ${_actualBitDepth}bit';
        final renderText =
            'Render target ${_preferredSampleRate}Hz / ${_preferredBitDepth}bit';
        if (!sampleRateApplied || !bitDepthApplied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Applied with limits: $deviceText, $renderText',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Audio settings applied: $deviceText, $renderText',
              ),
            ),
          );
        }
      }

      _maybeStartAutoDemo();
    } catch (e) {
      debugPrint('Error initializing engine with settings: $e');
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply audio settings')),
        );
      }
    } finally {
      if (mounted && _isApplyingAudioSettings) {
        setState(() => _isApplyingAudioSettings = false);
      }
    }
  }

  Future<void> _openAudioSettingsDialog() async {
    if (_isApplyingAudioSettings) return;

    final result = await showDialog<_AudioSettingsData>(
      context: context,
      builder: (dialogContext) {
        int selectedBuffer = _bufferSize;
        int selectedSampleRate = _preferredSampleRate;
        int selectedBitDepth = _preferredBitDepth;
        const bufferOptions = [256, 512, 1024, 2048];
        const sampleRateOptions = [8000, 11025, 22050, 44100, 48000, 96000];
        const bitDepthOptions = [4, 8, 12, 16, 24, 32];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Audio Settings'),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedBuffer,
                      decoration:
                          const InputDecoration(labelText: 'Buffer Size'),
                      items: bufferOptions
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text('$v samples')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedBuffer = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedSampleRate,
                      decoration:
                          const InputDecoration(labelText: 'Sample Rate'),
                      items: sampleRateOptions
                          .map((v) =>
                              DropdownMenuItem(value: v, child: Text('$v Hz')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedSampleRate = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedBitDepth,
                      decoration: const InputDecoration(labelText: 'Bit Depth'),
                      items: bitDepthOptions
                          .map((v) =>
                              DropdownMenuItem(value: v, child: Text('$v-bit')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedBitDepth = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Device I/O: ${_actualSampleRate.toStringAsFixed(0)}Hz / ${_actualBitDepth}bit',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Render target: ${selectedSampleRate}Hz / ${selectedBitDepth}bit',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Some iOS devices keep hardware at 48kHz; low sample-rate target is applied as Lo-Fi rendering.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _AudioSettingsData(
                        bufferSize: selectedBuffer,
                        sampleRate: selectedSampleRate,
                        bitDepth: selectedBitDepth,
                      ),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() {
      _bufferSize = result.bufferSize;
      _preferredSampleRate = result.sampleRate;
      _preferredBitDepth = result.bitDepth;
      _ctx = null;
      _autoDemoStarted = false;
      _isApplyingAudioSettings = true;
    });

    await _initEngine(showFeedback: true);
  }

  void _maybeStartAutoDemo() {
    if (!_autoDemoEnabled || _autoDemoStarted || _ctx == null) return;
    _autoDemoStarted = true;
    if (_autoDemoStartDelayMs > 0) {
      Future.delayed(const Duration(milliseconds: _autoDemoStartDelayMs), () {
        if (!mounted || _ctx == null) return;
        unawaited(_runAutoDemo());
      });
      return;
    }
    unawaited(_runAutoDemo());
  }

  Future<void> _waitForAutoDemoTargets() async {
    for (int i = 0; i < 30; i++) {
      if (!mounted) return;
      if (_drumPadKey.currentState != null) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _emitSyncMarkerBeep() {
    final ctx = _ctx;
    if (ctx == null) return;

    final osc = ctx.createOscillator();
    final gain = ctx.createGain();

    osc.type = WAOscillatorType.square;
    osc.frequency.value = 1320.0;
    gain.gain.value = 0.0;

    osc.connect(gain);
    gain.connect(ctx.destination);

    final t = ctx.currentTime + 0.002;
    gain.gain.setValueAtTime(0.0, t);
    gain.gain.linearRampToValueAtTime(0.32, t + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.10);
    osc.start(t);
    osc.stop(t + 0.12);

    Future.delayed(const Duration(milliseconds: 250), () {
      osc.dispose();
      gain.dispose();
    });
  }

  Future<void> _runAutoDemo() async {
    await _waitForAutoDemoTargets();
    if (!mounted) return;

    if (!_autoDemoDisableSyncBeep) {
      debugPrint('AUTODEMO step: sync-beep');
      _emitSyncMarkerBeep();
    }
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    debugPrint('AUTODEMO step: tab->sampler');
    _tabController.animateTo(
      1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    debugPrint('AUTODEMO step: tune');
    _drumPadKey.currentState?.demoSetTune(1200.0);

    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    debugPrint('AUTODEMO step: decay');
    _drumPadKey.currentState?.demoSetDecay(1.77);

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    debugPrint('AUTODEMO step: hit');
    _drumPadKey.currentState?.demoHit();

    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    debugPrint('AUTODEMO step: tab->sequencer');
    _tabController.animateTo(
      2,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    debugPrint('AUTODEMO step: start sequencer');
    await _sequencerKey.currentState?.demoEnsureReadyAndStart();
    debugPrint('AUTODEMO step: done');
  }

  @override
  void dispose() {
    _ctx?.close();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ctx == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_isApplyingAudioSettings) ...[
                const SizedBox(height: 12),
                const Text('Applying audio settings...'),
              ],
            ],
          ),
        ),
      );
    }

    // Web-specific: Show unlock button if AudioContext is suspended
    const bool isWeb = bool.fromEnvironment('dart.library.js_interop');
    if (isWeb && _ctx!.state == WAAudioContextState.suspended) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.volume_off, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('Audio is suspended by browser policy'),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await _ctx!.resume();
                  setState(() {});
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('START AUDIO ENGINE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('wajuce Multi-Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openAudioSettingsDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.piano), text: 'Synth Pad'),
            Tab(icon: Icon(Icons.music_note), text: 'Sampler'),
            Tab(icon: Icon(Icons.grid_view), text: 'Sequencer'),
            Tab(icon: Icon(Icons.mic), text: 'I/O & Rec'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SynthPadScreen(
            key: ValueKey<int>(_ctx!.contextId),
            ctx: _ctx!,
          ),
          DrumPadScreen(key: _drumPadKey, ctx: _ctx!),
          SequencerScreen(key: _sequencerKey, ctx: _ctx!),
          RecorderScreen(
            key: ValueKey<String>('rec-${_ctx!.contextId}'),
            ctx: _ctx!,
          ),
        ],
      ),
    );
    return scaffold;
  }
}

class SynthPadScreen extends StatefulWidget {
  final WAContext ctx;
  const SynthPadScreen({super.key, required this.ctx});

  @override
  State<SynthPadScreen> createState() => _SynthPadScreenState();
}

class _SynthPadScreenState extends State<SynthPadScreen> {
  WAOscillatorNode? _osc;
  WAGainNode? _gain;
  WAOscillatorType _type = WAOscillatorType.custom;

  double _currentFreq = 440.0;
  double _currentGain = 0.0;

  @override
  void initState() {
    super.initState();
    _initNodes();
  }

  void _initNodes() {
    _osc = widget.ctx.createOscillator();
    // For custom type, we must setPeriodicWave
    if (_type == WAOscillatorType.custom) {
      _setCustomWave();
    } else {
      _osc!.type = _type;
    }

    _gain = widget.ctx.createGain();
    _gain!.gain.value = 0;

    _osc!.connect(_gain!);
    _gain!.connect(widget.ctx.destination);

    _osc!.start();
  }

  @override
  void dispose() {
    _osc?.dispose();
    _gain?.dispose();
    super.dispose();
  }

  void _handleInput(Offset localPos, Size size) {
    double normX = (localPos.dx / size.width).clamp(0.0, 1.0);
    double normY = 1.0 - (localPos.dy / size.height).clamp(0.0, 1.0);

    // Freq 50..5000 (Log scale approximate)
    double freq = 50.0 * pow(100.0, normX);

    final now = widget.ctx.currentTime;

    _osc?.frequency.setTargetAtTime(freq, now, 0.02);
    _gain?.gain.setTargetAtTime(normY, now, 0.02);

    setState(() {
      _currentFreq = freq;
      _currentGain = normY;
    });
  }

  void _onPanStart(DragStartDetails d, BoxConstraints c) {
    _handleInput(d.localPosition, Size(c.maxWidth, c.maxHeight));
  }

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints c) {
    _handleInput(d.localPosition, Size(c.maxWidth, c.maxHeight));
  }

  void _onPanEnd(DragEndDetails d) {
    _gain?.gain.setTargetAtTime(0, widget.ctx.currentTime, 0.05);
    setState(() => _currentGain = 0);
  }

  void _setCustomWave() {
    // Generate a "Buzz" wave (sawtooth-like spectrum)
    const int harmonicCount = 64;
    final real = Float32List(harmonicCount); // 0 (phases aligned)
    final imag = Float32List(harmonicCount);

    for (int i = 1; i < harmonicCount; i++) {
      imag[i] = 1.0 / i;
    }

    final wave = WAPeriodicWave(real: real, imag: imag);
    _osc?.setPeriodicWave(wave);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text("Wave: "),
              DropdownButton<WAOscillatorType>(
                value: _type,
                items: WAOscillatorType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _type = v!;
                    if (_type == WAOscillatorType.custom) {
                      _setCustomWave();
                    } else {
                      _osc?.type = _type;
                    }
                  });
                },
              ),
              const Spacer(),
              Text("Freq: ${_currentFreq.toStringAsFixed(1)} Hz"),
              const SizedBox(width: 16),
              Text("Gain: ${_currentGain.toStringAsFixed(2)}"),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanStart: (d) => _onPanStart(d, constraints),
                onPanUpdate: (d) => _onPanUpdate(d, constraints),
                onPanEnd: _onPanEnd,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.blueGrey.shade900,
                  child: CustomPaint(
                    painter: PadPainter(_currentFreq, _currentGain),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PadPainter extends CustomPainter {
  final double freq;
  final double gain;
  PadPainter(this.freq, this.gain);
  @override
  void paint(Canvas canvas, Size size) {
    if (gain > 0.01) {
      final paint = Paint()
        ..color = Colors.orangeAccent.withValues(alpha: 0.3 + gain * 0.7);
      // X position based on freq is hard to reverse, just draw where touch is roughly?
      // Actually we don't have touch pos here. Just draw a circle in center with size = gain.
      canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.5), gain * 100 + 10, paint);
    }
  }

  @override
  bool shouldRepaint(PadPainter old) => old.gain != gain || old.freq != freq;
}

// ============================================================================
// Sampler Tab
// ============================================================================
class DrumPadScreen extends StatefulWidget {
  final WAContext ctx;
  const DrumPadScreen({super.key, required this.ctx});

  @override
  State<DrumPadScreen> createState() => _DrumPadScreenState();
}

class _DrumPadScreenState extends State<DrumPadScreen> {
  WABuffer? _sampleBuffer;
  double _tune = 0;
  double _decay = 0.5;
  double _pan = 0.0;
  double _gain = 0.8;
  bool _isLoading = true;

  final WAMidi _midi = WAMidi();
  List<WAMidiInput> _inputs = [];
  WAMidiInput? _selectedInput;
  String _lastMidiMsg = 'No MIDI input selected';

  @override
  void initState() {
    super.initState();
    _loadSample();
    _initMidi();
  }

  Future<void> _initMidi() async {
    final granted = await _midi.requestAccess();
    if (granted) {
      if (mounted) {
        setState(() {
          _inputs = _midi.inputs;
        });
      }
    }
  }

  void _onMidiSelect(WAMidiInput? input) async {
    if (_selectedInput != null) {
      await _selectedInput!.close();
    }
    setState(() {
      _selectedInput = input;
      _lastMidiMsg = input == null
          ? 'MIDI monitoring disabled'
          : 'Monitoring ${input.name}';
    });
    if (input != null) {
      input.onMessage = (data, ts) {
        if (mounted) {
          setState(() {
            _lastMidiMsg =
                'Msg: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
          });
        }
        // Play sample on Note On
        if (data.isNotEmpty && (data[0] & 0xF0) == 0x90 && data[2] > 0) {
          _play();
        }
      };
      await input.open();
    }
  }

  Future<void> _loadSample() async {
    try {
      final byteData = await rootBundle.load('lib/cr01.wav');
      final wav = Wav.read(byteData.buffer.asUint8List());
      final buffer = WABuffer(
        numberOfChannels: wav.channels.length,
        length: wav.channels[0].length,
        sampleRate: wav.samplesPerSecond,
      );
      for (int i = 0; i < wav.channels.length; i++) {
        buffer.getChannelData(i).setAll(0, wav.channels[i]);
      }
      setState(() {
        _sampleBuffer = buffer;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading sample: $e');
    }
  }

  void _play() {
    if (_sampleBuffer == null) return;
    final source = widget.ctx.createBufferSource();
    source.buffer = _sampleBuffer;
    source.detune.value = _tune;
    source.decay.value = _decay;

    final panner = widget.ctx.createStereoPanner();
    panner.pan.value = _pan;

    final gain = widget.ctx.createGain();
    gain.gain.value = _gain;

    source.connect(panner);
    panner.connect(gain);
    gain.connect(widget.ctx.destination);

    source.start();

    // Dispose after play (approximate duration)
    Future.delayed(
        Duration(
            milliseconds:
                ((_sampleBuffer!.length / _sampleBuffer!.sampleRate) * 1000 +
                        500)
                    .toInt()), () {
      source.dispose();
      panner.dispose();
      gain.dispose();
    });
  }

  void demoSetTune(double value) {
    setState(() {
      _tune = value.clamp(-1200.0, 1200.0).toDouble();
    });
  }

  void demoSetDecay(double value) {
    setState(() {
      _decay = value.clamp(0.01, 2.0).toDouble();
    });
  }

  void demoHit() {
    _play();
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _play,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.5),
                      blurRadius: 30),
                ],
              ),
              child: const Center(
                child: Text('HIT ME',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _SliderRow(
              label: 'Tune',
              value: _tune,
              min: -1200,
              max: 1200,
              onChanged: (v) => setState(() => _tune = v)),
          _SliderRow(
              label: 'Decay',
              value: _decay,
              min: 0.01,
              max: 2.0,
              onChanged: (v) => setState(() => _decay = v)),
          _SliderRow(
              label: 'Pan',
              value: _pan,
              min: -1.0,
              max: 1.0,
              onChanged: (v) => setState(() => _pan = v)),
          _SliderRow(
              label: 'Level',
              value: _gain,
              min: 0.0,
              max: 1.0,
              onChanged: (v) => setState(() => _gain = v)),
          const Divider(height: 48),
          const Text('MIDI INPUT VERIFICATION',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange)),
          const SizedBox(height: 8),
          DropdownButton<WAMidiInput>(
            value: _selectedInput,
            hint: const Text('Select MIDI Input'),
            isExpanded: true,
            items: [
              const DropdownMenuItem<WAMidiInput>(
                  value: null, child: Text('None (Disabled)')),
              ..._inputs.map((input) =>
                  DropdownMenuItem(value: input, child: Text(input.name))),
            ],
            onChanged: _onMidiSelect,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _lastMidiMsg,
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Sequencer Tab
// ============================================================================
class SequencerScreen extends StatefulWidget {
  final WAContext ctx;
  const SequencerScreen({super.key, required this.ctx});

  @override
  State<SequencerScreen> createState() => _SequencerScreenState();
}

class MachineVoice {
  final WAOscillatorNode osc;
  final WABiquadFilterNode filter;
  final WAGainNode gain;
  final WADelayNode delay;
  final WAGainNode delayFb;
  final WAGainNode delayWet;
  final WAStereoPannerNode panner;

  MachineVoice({
    required this.osc,
    required this.filter,
    required this.gain,
    required this.delay,
    required this.delayFb,
    required this.delayWet,
    required this.panner,
  });

  void dispose() {
    osc.dispose();
    filter.dispose();
    gain.dispose();
    delay.dispose();
    delayFb.dispose();
    delayWet.dispose();
    panner.dispose();
  }
}

class MachineVoicePool {
  final WAContext ctx;
  final WAGainNode output;
  final List<MachineVoice> _spares = [];
  bool _isReplenishing = false;
  bool _disposed = false;

  MachineVoicePool(this.ctx, this.output);

  void prepare(int count) {
    _ensureReplenish(target: count);
  }

  void dispose() {
    _disposed = true;
    for (var v in _spares) {
      v.dispose();
    }
    _spares.clear();
  }

  Future<MachineVoice> getVoiceAsync() async {
    // 1. Try to get from pool
    if (_spares.isNotEmpty) {
      final v = _spares.removeLast();
      _ensureReplenish();
      return v;
    }

    // 2. Pool empty? Create one immediately.
    // Keep API async-compatible for call sites.
    final v = _createBatch();

    _ensureReplenish(); // Schedule replenishment
    return v;
  }

  MachineVoice _createBatch() {
    try {
      final nodes = ctx.createMachineVoice();
      final voice = MachineVoice(
        osc: nodes[0] as WAOscillatorNode,
        filter: nodes[1] as WABiquadFilterNode,
        gain: nodes[2] as WAGainNode,
        panner: nodes[3] as WAStereoPannerNode,
        delay: nodes[4] as WADelayNode,
        delayFb: nodes[5] as WAGainNode,
        delayWet: nodes[6] as WAGainNode,
      );
      voice.panner.connect(output);
      voice.delayWet.connect(output);
      return voice;
    } catch (e) {
      // Fallback for Web or platforms where batch creation is not implemented
      final osc = ctx.createOscillator();
      final filter = ctx.createBiquadFilter();
      final gain = ctx.createGain();
      gain.gain.value = 0; // Start silent
      final panner = ctx.createStereoPanner();
      final delay = ctx.createDelay();
      final delayFb = ctx.createGain();
      final delayWet = ctx.createGain();
      delayFb.gain.value = 0; // Delay feedback starts disabled
      delayWet.gain.value = 0; // Delay wet mix starts disabled

      // Basic routing for machine voice
      osc.connect(filter);
      filter.connect(gain);
      gain.connect(panner);

      // Delay routing
      gain.connect(delay);
      delay.connect(delayFb);
      delayFb.connect(delay);
      delay.connect(delayWet);

      panner.connect(output);
      delayWet.connect(output);
      osc.start();

      return MachineVoice(
        osc: osc,
        filter: filter,
        gain: gain,
        panner: panner,
        delay: delay,
        delayFb: delayFb,
        delayWet: delayWet,
      );
    }
  }

  void _ensureReplenish({int target = 8}) {
    if (_disposed || _isReplenishing) return;
    if (_spares.length >= target) return;

    _isReplenishing = true;

    // Fill pool using microtasks to avoid blocking frame
    Future(() {
      // Use Future instead of microtask for better yielding
      try {
        if (_disposed) return;

        final v = _createBatch();

        _spares.add(v);
      } catch (e) {
        debugPrint("Replenish error: $e");
      } finally {
        _isReplenishing = false;
        if (!_disposed && _spares.length < target) {
          // Schedule next batch with a slight delay if needed,
          // and yield a frame to keep UI responsive.
          Future.delayed(const Duration(milliseconds: 16),
              () => _ensureReplenish(target: target));
        }
      }
    });
  }

  // Deprecated: Only use if absolutely necessary
  MachineVoice getVoiceSync() {
    if (_spares.isNotEmpty) {
      final v = _spares.removeLast();
      _ensureReplenish();
      return v;
    }
    final v = _createBatch();
    _ensureReplenish();
    return v;
  }
}

class MachineState {
  final int id;
  // final WAContext ctx; // Removed, handled by Voice/Pool
  // final WAGainNode output; // Removed

  double frequency = 440;
  double decay = 0.5;
  WAOscillatorType waveType = WAOscillatorType.sine;
  WABiquadFilterType filterType = WABiquadFilterType.lowpass;
  double pan = 0.0;
  double cutoff = 2000;
  double resonance = 1;
  double delayTime = 0.3;
  double delayFeedback = 0.3;
  double delayMix = 0.5;
  bool delayEnabled = false;
  List<bool> steps = List.generate(16, (i) => i % 4 == 0);

  final MachineVoice? _voice;
  WAOscillatorType? _lastWaveType;
  WABiquadFilterType? _lastFilterType;
  double _lastFrequency = double.nan;
  double _lastCutoff = double.nan;
  double _lastResonance = double.nan;
  double _lastPan = double.nan;
  double _lastDelayTime = double.nan;
  double _lastDelayFeedback = double.nan;
  double _lastDelayMix = double.nan;
  bool _lastDelayEnabled = false;

  MachineState(this.id, MachineVoice voice) : _voice = voice;

  void ensureVoice() {
    // No-op, voice is injected
  }

  void dispose() {
    _voice?.dispose();
  }
}

class _SequencerScreenState extends State<SequencerScreen> {
  final List<MachineState> _machines = [];
  bool _isPlaying = false;
  double _bpm = 120;
  double _masterGain = 0.8;
  int _currentStep = 0;
  WAGainNode? _masterOutput;
  MachineVoicePool? _pool;

  WAWorkletNode? _clockNode;
  WAGainNode? _clockSink;
  static const double _warmupAheadSeconds = 0.03;
  static const double _noteSafetyAheadSeconds = 0.006;
  static const double _staleTickDropThresholdSeconds = 0.12;

  @override
  void initState() {
    super.initState();
    _masterOutput = widget.ctx.createGain();
    _masterOutput!.gain.value = _masterGain;
    _masterOutput!.connect(widget.ctx.destination);

    _pool = MachineVoicePool(widget.ctx, _masterOutput!);
    // Pre-warm the pool effectively in background
    _pool!.prepare(2);

    // Initial machine
    Future.delayed(const Duration(milliseconds: 100), _addMachine);

    _initClock();
  }

  Future<void> _initClock() async {
    await loadClockWorkletModule(widget.ctx);

    _clockNode?.dispose();
    _clockSink?.dispose();

    _clockNode = createClockWorkletNode(widget.ctx);

    // CRITICAL FIX: Web AudioWorklet must be connected to be active!
    // We connect it to a dummy silent gain to force the browser to run the processor.
    _clockSink = widget.ctx.createGain();
    _clockSink!.gain.value = 0.0;
    _clockNode!.connect(_clockSink!);
    _clockSink!.connect(widget.ctx.destination);

    _clockNode!.port.onMessage = (data) {
      if (data is Map && data['type'] == 'tick') {
        final step = (data['step'] as num?)?.toInt();
        if (step == null) return;
        final scheduledTime = (data['time'] as num?)?.toDouble();
        _onTick(step, scheduledTime);
      }
    };
  }

  @override
  void dispose() {
    _clockNode?.dispose();
    _clockSink?.dispose();
    _pool?.dispose();
    for (final m in _machines) {
      m.dispose();
    }
    _masterOutput?.dispose();
    super.dispose();
  }

  bool _isAddingMachine = false;

  void _addMachine() async {
    if (!mounted || _isAddingMachine) return;

    setState(() => _isAddingMachine = true);

    try {
      // Use async creation to avoid blocking main thread & audio thread lock contention
      final voice = await _pool!.getVoiceAsync();

      if (!mounted) {
        voice.dispose();
        return;
      }

      late final MachineState machine;
      setState(() {
        machine = MachineState(_machines.length, voice);
        _machines.add(machine);
        _isAddingMachine = false;
      });
      _applyMachineRealtimeParams(
        machine,
        atTime: widget.ctx.currentTime + _warmupAheadSeconds,
        force: true,
      );
    } catch (e) {
      debugPrint("Error adding machine: $e");
      if (mounted) setState(() => _isAddingMachine = false);
    }
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _currentStep = 0;
        final warmupTime = widget.ctx.currentTime + _warmupAheadSeconds;
        for (final m in _machines) {
          _applyMachineRealtimeParams(m, atTime: warmupTime, force: true);
        }
        _clockNode?.port.postMessage({
          'type': 'start',
          'contextTime': widget.ctx.currentTime,
        });
        _clockNode?.port.postMessage({'type': 'bpm', 'value': _bpm});
      } else {
        _clockNode?.port.postMessage({'type': 'stop'});
        _hardStopAllMachines();
        _currentStep = -1; // Reset highlight
      }
    });
  }

  void _hardStopAllMachines() {
    final stopTime = widget.ctx.currentTime + 0.001;
    for (final m in _machines) {
      final v = m._voice;
      if (v == null) continue;
      v.gain.gain.cancelAndHoldAtTime(stopTime);
      v.gain.gain.setValueAtTime(0.0, stopTime);
    }
  }

  Future<void> demoEnsureReadyAndStart() async {
    for (int i = 0; i < 50; i++) {
      if (!mounted) return;
      if (_machines.isNotEmpty && _clockNode != null) break;
      if (_machines.isEmpty && !_isAddingMachine) {
        _addMachine();
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }

    if (!mounted) return;
    if (!_isPlaying) {
      _togglePlay();
    }
  }

  void _applyMachineRealtimeParams(MachineState m,
      {double? atTime, bool force = false}) {
    final v = m._voice;
    if (v == null) return;

    final now = widget.ctx.currentTime;
    final t = atTime ?? (now + 0.002);

    if (force || m._lastWaveType != m.waveType) {
      v.osc.type = m.waveType;
      m._lastWaveType = m.waveType;
    }
    if (force ||
        (m.frequency - m._lastFrequency).abs() > 0.0001 ||
        m._lastFrequency.isNaN) {
      v.osc.frequency.setTargetAtTime(m.frequency, t, 0.010);
      m._lastFrequency = m.frequency;
    }

    if (force || m._lastFilterType != m.filterType) {
      v.filter.type = m.filterType;
      m._lastFilterType = m.filterType;
    }
    if (force ||
        (m.cutoff - m._lastCutoff).abs() > 0.0001 ||
        m._lastCutoff.isNaN) {
      v.filter.frequency.setTargetAtTime(m.cutoff, t, 0.012);
      m._lastCutoff = m.cutoff;
    }
    if (force ||
        (m.resonance - m._lastResonance).abs() > 0.0001 ||
        m._lastResonance.isNaN) {
      v.filter.Q.setTargetAtTime(m.resonance, t, 0.012);
      m._lastResonance = m.resonance;
    }
    if (force || (m.pan - m._lastPan).abs() > 0.0001 || m._lastPan.isNaN) {
      v.panner.pan.setTargetAtTime(m.pan, t, 0.015);
      m._lastPan = m.pan;
    }

    // DelayNode delayTime is a regular AudioParam regardless of bypass/mix state.
    // Keep it updated continuously so enabling wet path doesn't cause first-hit jumps.
    if (force ||
        (m.delayTime - m._lastDelayTime).abs() > 0.0001 ||
        m._lastDelayTime.isNaN) {
      if (force || m._lastDelayTime.isNaN) {
        v.delay.delayTime.cancelAndHoldAtTime(t);
        v.delay.delayTime.setValueAtTime(m.delayTime, t);
      } else {
        v.delay.delayTime.setTargetAtTime(m.delayTime, t, 0.12);
      }
      m._lastDelayTime = m.delayTime;
    }

    // Wet/feedback gains are the bypass control for this example graph.
    if (m.delayEnabled) {
      final isDelayEntering = force || !m._lastDelayEnabled;

      if (isDelayEntering ||
          (m.delayFeedback - m._lastDelayFeedback).abs() > 0.0001 ||
          m._lastDelayFeedback.isNaN) {
        v.delayFb.gain.setTargetAtTime(m.delayFeedback, t, 0.09);
        m._lastDelayFeedback = m.delayFeedback;
      }

      if (isDelayEntering ||
          (m.delayMix - m._lastDelayMix).abs() > 0.0001 ||
          m._lastDelayMix.isNaN) {
        v.delayWet.gain.setTargetAtTime(m.delayMix, t, 0.08);
        m._lastDelayMix = m.delayMix;
      }
      m._lastDelayEnabled = true;
    } else {
      if (force || m._lastDelayEnabled) {
        v.delayFb.gain.setTargetAtTime(0, t, 0.08);
        v.delayWet.gain.setTargetAtTime(0, t, 0.06);
      }
      m._lastDelayEnabled = false;
    }
  }

  void _onTick(int step, [double? scheduledTime]) {
    if (!mounted || !_isPlaying) return;
    final now = widget.ctx.currentTime;
    if (scheduledTime != null &&
        scheduledTime < now - _staleTickDropThresholdSeconds) {
      return;
    }
    final triggerTime = scheduledTime == null
        ? (now + _noteSafetyAheadSeconds)
        : max(scheduledTime, now + _noteSafetyAheadSeconds);

    for (var m in _machines) {
      if (m.steps[step]) {
        _playMachine(m, triggerTime);
      }
    }

    if (_currentStep != step) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  void _playMachine(MachineState m, double time) {
    m.ensureVoice();
    final v = m._voice!;

    // Keep voice params warm with slightly longer smoothing to reduce ticks.
    _applyMachineRealtimeParams(m, atTime: time);

    // Retrigger envelope without hard discontinuity.
    v.gain.gain.cancelAndHoldAtTime(time);
    v.gain.gain.setTargetAtTime(0.45, time, 0.004);
    v.gain.gain.setTargetAtTime(0.0001, time + 0.022, max(0.008, m.decay));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black26,
          child: Row(
            children: [
              IconButton.filled(
                onPressed: _togglePlay,
                icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                iconSize: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SliderRow(
                  label: '',
                  value: _masterGain,
                  min: 0,
                  max: 1,
                  onChanged: (v) {
                    setState(() {
                      _masterGain = v;
                      _masterOutput?.gain.setTargetAtTime(v, 0, 0.02);
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              const Text('BPM'),
              Expanded(
                child: Slider(
                  value: _bpm,
                  min: 60,
                  max: 200,
                  onChanged: (v) {
                    setState(() => _bpm = v);
                    if (_isPlaying) {
                      _clockNode?.port.postMessage({'type': 'bpm', 'value': v});
                    }
                  },
                ),
              ),
              Text(_bpm.toInt().toString()),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _machines.length + 1,
            itemBuilder: (context, index) {
              if (index == _machines.length) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: _isAddingMachine ? null : _addMachine,
                    icon: _isAddingMachine
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: Text(_isAddingMachine
                        ? ' BUILDING NODES...'
                        : 'ADD MACHINE'),
                  ),
                );
              }
              final m = _machines[index];
              return _MachineView(
                state: m,
                currentStep: _currentStep,
                onChanged: () {
                  _applyMachineRealtimeParams(m);
                  setState(() {});
                },
                onDelete: () {
                  _machines[index].dispose();
                  setState(() => _machines.removeAt(index));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MachineView extends StatelessWidget {
  final MachineState state;
  final int currentStep;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _MachineView(
      {required this.state,
      required this.currentStep,
      required this.onChanged,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Text('Synth #${state.id + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                DropdownButton<WAOscillatorType>(
                  value: state.waveType,
                  isDense: true,
                  items: [
                    for (final type in WAOscillatorType.values)
                      DropdownMenuItem(value: type, child: Text(type.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      state.waveType = v;
                      onChanged();
                    }
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<WABiquadFilterType>(
                  value: state.filterType,
                  isDense: true,
                  items: [
                    for (final type in WABiquadFilterType.values)
                      DropdownMenuItem(value: type, child: Text(type.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      state.filterType = v;
                      onChanged();
                    }
                  },
                ),
                IconButton(
                    onPressed: onDelete,
                    icon:
                        const Icon(Icons.close, size: 20, color: Colors.grey)),
              ],
            ),
            _SliderRow(
                label: 'Freq',
                value: state.frequency,
                min: 20,
                max: 2000,
                onChanged: (v) {
                  state.frequency = v;
                  onChanged();
                }),
            _SliderRow(
                label: 'Decay',
                value: state.decay,
                min: 0.01,
                max: 1.0,
                isSeconds: true,
                onChanged: (v) {
                  state.decay = v;
                  onChanged();
                }),
            _SliderRow(
                label: 'Cutoff',
                value: state.cutoff,
                min: 50,
                max: 10000,
                onChanged: (v) {
                  state.cutoff = v;
                  onChanged();
                }),
            _SliderRow(
                label: 'Res',
                value: state.resonance,
                min: 0,
                max: 20,
                onChanged: (v) {
                  state.resonance = v;
                  onChanged();
                }),
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                      value: state.delayEnabled,
                      onChanged: (v) {
                        state.delayEnabled = v ?? false;
                        onChanged();
                      }),
                ),
                const Text(' Delay ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Column(
                    children: [
                      _SliderRow(
                        label: 'Time',
                        value: state.delayTime,
                        min: 0,
                        max: 1,
                        isSeconds: true,
                        onChanged: state.delayEnabled
                            ? (v) {
                                state.delayTime = v;
                                onChanged();
                              }
                            : (v) {},
                      ),
                      _SliderRow(
                        label: 'Fdbk',
                        value: state.delayFeedback,
                        min: 0,
                        max: 0.95,
                        onChanged: state.delayEnabled
                            ? (v) {
                                state.delayFeedback = v;
                                onChanged();
                              }
                            : (v) {},
                      ),
                      _SliderRow(
                        label: 'Mix',
                        value: state.delayMix,
                        min: 0,
                        max: 1,
                        onChanged: state.delayEnabled
                            ? (v) {
                                state.delayMix = v;
                                onChanged();
                              }
                            : (v) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 16 steps in 8x2 grid
            Column(
              children: [
                _StepRow(
                    steps: state.steps,
                    start: 0,
                    count: 8,
                    currentStep: currentStep,
                    onChanged: onChanged),
                const SizedBox(height: 4),
                _StepRow(
                    steps: state.steps,
                    start: 8,
                    count: 8,
                    currentStep: currentStep,
                    onChanged: onChanged),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final List<bool> steps;
  final int start;
  final int count;
  final int currentStep;
  final VoidCallback onChanged;

  const _StepRow(
      {required this.steps,
      required this.start,
      required this.count,
      required this.currentStep,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(count, (i) {
        final idx = start + i;
        final isActive = currentStep == idx;
        return GestureDetector(
          onTap: () {
            steps[idx] = !steps[idx];
            onChanged();
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: steps[idx] ? Colors.orange : Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? Colors.white : Colors.white10,
                width: isActive ? 2 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: Colors.white.withValues(alpha: 0.5),
                          blurRadius: 4)
                    ]
                  : null,
            ),
            child: Center(
                child: Text('${idx + 1}',
                    style: TextStyle(
                        fontSize: 8,
                        color: isActive ? Colors.white : Colors.white54,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal))),
          ),
        );
      }),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool isSeconds;
  final ValueChanged<double> onChanged;

  const _SliderRow(
      {required this.label,
      required this.value,
      required this.min,
      required this.max,
      this.isSeconds = false,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.0),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label, style: const TextStyle(fontSize: 11))),
          Expanded(
              child: SizedBox(
                  height: 32,
                  child: Slider(
                      value: value, min: min, max: max, onChanged: onChanged))),
          SizedBox(
              width: 45,
              child: Text(
                  isSeconds
                      ? '${value.toStringAsFixed(2)}s'
                      : value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

// ============================================================================
// I/O & Recording Tab
// ============================================================================
class RecorderScreen extends StatefulWidget {
  final WAContext ctx;
  const RecorderScreen({super.key, required this.ctx});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  WAMediaStreamSourceNode? _micSource;
  WAAnalyserNode? _analyser;
  WAGainNode? _monitorGain;
  WAGainNode? _filePlaybackGain;

  WABufferSourceNode? _fileSource;
  WABuffer? _decodedBuffer;

  bool _isMicActive = false;
  bool _isMonitoring = false;
  bool _isLoadingFile = false;

  final Uint8List _fftData = Uint8List(256);
  Timer? _visualizerTimer;

  @override
  void initState() {
    super.initState();
    _initNodes();
    _visualizerTimer = Timer.periodic(const Duration(milliseconds: 33), (t) {
      if (_analyser != null) {
        _analyser!.getByteTimeDomainData(_fftData);
        if (mounted) setState(() {});
      }
    });
  }

  void _initNodes() {
    _analyser = widget.ctx.createAnalyser();
    _analyser!.fftSize = 512;

    _monitorGain = widget.ctx.createGain();
    _monitorGain!.gain.value = 0; // Default monitor off
    _filePlaybackGain = widget.ctx.createGain();
    _filePlaybackGain!.gain.value = 0.9; // Keep decoded file audible by default

    _analyser!.connect(_monitorGain!);
    _monitorGain!.connect(widget.ctx.destination);
    _filePlaybackGain!.connect(widget.ctx.destination);
  }

  @override
  void dispose() {
    _visualizerTimer?.cancel();
    _micSource?.dispose();
    _analyser?.dispose();
    _monitorGain?.dispose();
    _filePlaybackGain?.dispose();
    _fileSource?.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_isMicActive) {
      _micSource?.disconnect();
      _micSource?.dispose();
      _micSource = null;
    } else {
      try {
        _micSource = await widget.ctx.createMicrophoneSource();
        _micSource!.connect(_analyser!);
      } catch (e) {
        debugPrint('Error creating mic source: $e');
        return;
      }
    }
    setState(() => _isMicActive = !_isMicActive);
  }

  void _toggleMonitor() {
    setState(() {
      _isMonitoring = !_isMonitoring;
      _monitorGain?.gain.setTargetAtTime(
          _isMonitoring ? 0.8 : 0, widget.ctx.currentTime, 0.05);
    });
  }

  Future<void> _testDecodeAndPlay() async {
    if (_isLoadingFile) return;
    setState(() => _isLoadingFile = true);

    try {
      await widget.ctx.resume();
      final data = await rootBundle.load('lib/cr01.wav');
      final buffer =
          await widget.ctx.decodeAudioData(data.buffer.asUint8List());

      _fileSource?.stop();
      _fileSource?.dispose();

      _fileSource = widget.ctx.createBufferSource();
      _fileSource!.buffer = buffer;
      _fileSource!.connect(_analyser!);
      _fileSource!.connect(_filePlaybackGain!);
      _fileSource!.start();

      _decodedBuffer = buffer;
    } catch (e) {
      debugPrint('Error testing decode: $e');
    } finally {
      setState(() => _isLoadingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text("Phase 4 Verification: I/O & Buffers",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Oscilloscope Visualizer
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: CustomPaint(
              painter: OscilloscopePainter(_fftData),
            ),
          ),

          const SizedBox(height: 24),

          // Mic Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _toggleMic,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isMicActive ? Colors.red.withValues(alpha: 0.8) : null,
                ),
                icon: Icon(_isMicActive ? Icons.mic_off : Icons.mic),
                label: Text(_isMicActive ? "STOP MIC" : "START MIC"),
              ),
              ElevatedButton.icon(
                onPressed: _isMicActive ? _toggleMonitor : null,
                icon: Icon(_isMonitoring ? Icons.volume_up : Icons.volume_off),
                label: Text(_isMonitoring ? "MONITOR ON" : "MONITOR OFF"),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // Decode Test
          const Text("decodeAudioData & BufferSource Test"),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _testDecodeAndPlay,
            icon: _isLoadingFile
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text("DECODE & PLAY CR01.WAV"),
          ),
          if (_decodedBuffer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                  "Decoded: ${_decodedBuffer!.numberOfChannels}ch, "
                  "${_decodedBuffer!.length} samples @ ${_decodedBuffer!.sampleRate.toInt()}Hz",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),

          const Spacer(),
          const Text("Verification Status:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text("✅ MediaStreamSource -> Analyser -> Monitor",
              style: TextStyle(fontSize: 12)),
          const Text("✅ decodeAudioData -> BufferSource -> Analyser",
              style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// End of file
