/// MIDI API — Device enumeration, input streams, and output sending.
///
/// Mirrors the Web MIDI API with platform-native support via JUCE.
/// ```dart
/// final midi = WAMidi();
/// await midi.requestAccess();
///
/// for (final input in midi.inputs) {
///   input.onMessage = (data, timestamp) {
///     print('MIDI: ${data[0].toRadixString(16)}');
///   };
/// }
///
/// midi.outputs.first.send([0x90, 60, 127]); // Note On
/// ```
library;

import 'dart:async';
import 'dart:typed_data';

import 'backend/backend.dart' as backend;

/// MIDI access state.
enum WAMidiAccessState {
  /// Access request is pending.
  pending,
  /// Access has been granted.
  granted,
  /// Access has been denied.
  denied,
}

/// A MIDI input port (receives messages from external devices).
class WAMidiInput {
  /// Unique identifier for the port.
  final String id;
  /// Human-readable name of the port.
  final String name;
  /// Manufacturer of the device.
  final String manufacturer;
  /// The hardware port index.
  final int portIndex;

  /// Callback for incoming MIDI messages.
  /// [data] is the raw MIDI bytes, [timestamp] is in milliseconds.
  void Function(Uint8List data, double timestamp)? onMessage;

  /// Creates a new MIDI input port representation.
  WAMidiInput({
    required this.id,
    required this.name,
    this.manufacturer = '',
    required this.portIndex,
  });

  /// Open this input port.
  Future<void> open() async {
    backend.midiInputOpen(portIndex);
  }

  /// Close this input port.
  Future<void> close() async {
    backend.midiInputClose(portIndex);
  }

  @override
  String toString() => 'WAMidiInput($name)';
}

/// A MIDI output port (sends messages to external devices).
class WAMidiOutput {
  /// Unique identifier for the port.
  final String id;
  /// Human-readable name of the port.
  final String name;
  /// Manufacturer of the device.
  final String manufacturer;
  /// The hardware port index.
  final int portIndex;

  /// Creates a new MIDI output port representation.
  WAMidiOutput({
    required this.id,
    required this.name,
    this.manufacturer = '',
    required this.portIndex,
  });

  /// Send MIDI data. [data] is raw MIDI bytes.
  /// Optional [timestamp] for scheduling (0 = immediately).
  void send(List<int> data, [double timestamp = 0]) {
    backend.midiOutputSend(portIndex, Uint8List.fromList(data), timestamp);
  }

  /// Send a SysEx message.
  void sendSysEx(List<int> data) {
    // Ensure proper SysEx framing
    final msg = <int>[];
    if (data.isEmpty || data.first != 0xF0) msg.add(0xF0);
    msg.addAll(data);
    if (msg.last != 0xF7) msg.add(0xF7);
    send(msg);
  }

  /// Open this output port.
  Future<void> open() async {
    backend.midiOutputOpen(portIndex);
  }

  /// Close this output port.
  Future<void> close() async {
    backend.midiOutputClose(portIndex);
  }

  @override
  String toString() => 'WAMidiOutput($name)';
}

/// Main MIDI access manager. Mirrors Web MIDI API MIDIAccess.
class WAMidi {
  List<WAMidiInput> _inputs = [];
  List<WAMidiOutput> _outputs = [];
  WAMidiAccessState _state = WAMidiAccessState.pending;
  StreamController<WAMidiInput>? _inputChangeController;
  StreamController<WAMidiOutput>? _outputChangeController;

  /// Creates a new MIDI manager.
  WAMidi();

  /// Request MIDI access. Must be called before using inputs/outputs.
  ///
  /// [sysex] — if true, request permission for SysEx messages.
  Future<bool> requestAccess({bool sysex = false}) async {
    try {
      final success = await backend.midiRequestAccess(sysex: sysex);
      _state = success ? WAMidiAccessState.granted : WAMidiAccessState.denied;
      if (success) {
        backend.onMidiMessageReceived = _handleMidiMessage;
        await _refreshDevices();
      }
      return success;
    } catch (e) {
      _state = WAMidiAccessState.denied;
      return false;
    }
  }

  void _handleMidiMessage(int portIndex, Uint8List data, double timestamp) {
    for (final input in _inputs) {
      if (input.portIndex == portIndex) {
        input.onMessage?.call(data, timestamp);
      }
    }
  }

  /// Available MIDI inputs.
  List<WAMidiInput> get inputs => List.unmodifiable(_inputs);

  /// Available MIDI outputs.
  List<WAMidiOutput> get outputs => List.unmodifiable(_outputs);

  /// Current access state.
  WAMidiAccessState get state => _state;

  /// Stream of newly connected inputs.
  Stream<WAMidiInput> get onInputConnected {
    _inputChangeController ??= StreamController<WAMidiInput>.broadcast();
    return _inputChangeController!.stream;
  }

  /// Stream of newly connected outputs.
  Stream<WAMidiOutput> get onOutputConnected {
    _outputChangeController ??= StreamController<WAMidiOutput>.broadcast();
    return _outputChangeController!.stream;
  }

  /// Refresh the device list.
  Future<void> _refreshDevices() async {
    final deviceInfo = await backend.midiGetDevices();

    _inputs = [];
    _outputs = [];

    for (int i = 0; i < deviceInfo.inputCount; i++) {
      _inputs.add(WAMidiInput(
        id: 'input-$i',
        name: deviceInfo.inputNames[i],
        manufacturer: deviceInfo.inputManufacturers[i],
        portIndex: i,
      ));
    }

    for (int i = 0; i < deviceInfo.outputCount; i++) {
      _outputs.add(WAMidiOutput(
        id: 'output-$i',
        name: deviceInfo.outputNames[i],
        manufacturer: deviceInfo.outputManufacturers[i],
        portIndex: i,
      ));
    }
  }

  /// Close all open ports and release MIDI access.
  Future<void> dispose() async {
    for (final input in _inputs) {
      await input.close();
    }
    for (final output in _outputs) {
      await output.close();
    }
    _inputChangeController?.close();
    _outputChangeController?.close();
    backend.midiDispose();
  }
}
