/// Oscillator waveform types.
enum WAOscillatorType {
  /// Sine wave.
  sine,
  /// Square wave.
  square,
  /// Sawtooth wave.
  sawtooth,
  /// Triangle wave.
  triangle,
  /// Custom waveform.
  custom,
}

/// BiquadFilter types.
enum WABiquadFilterType {
  /// Low-pass filter.
  lowpass,
  /// High-pass filter.
  highpass,
  /// Band-pass filter.
  bandpass,
  /// Low-shelf filter.
  lowshelf,
  /// High-shelf filter.
  highshelf,
  /// Peaking filter.
  peaking,
  /// Notch filter.
  notch,
  /// All-pass filter.
  allpass,
}

/// AudioContext state.
enum WAAudioContextState {
  /// Context is suspended.
  suspended,
  /// Context is running and processing audio.
  running,
  /// Context is closed and its resources may have been released.
  closed,
}

/// AudioParam automation rate.
enum WAAutomationRate {
  /// a-rate: Parameter is updated at the sample rate.
  aRate,
  /// k-rate: Parameter is updated at the block rate.
  kRate,
}

/// Panner distance model.
enum WADistanceModel {
  /// Linear distance model.
  linear,
  /// Inverse distance model.
  inverse,
  /// Exponential distance model.
  exponential,
}

/// Panner panning model.
enum WAPanningModel {
  /// Equal-power panning.
  equalpower,
  /// HRTF (Head-Related Transfer Function) panning.
  hrtf,
}

/// OverSample type for WaveShaper.
enum WAOverSampleType {
  /// No oversampling.
  none,
  /// 2x oversampling.
  x2,
  /// 4x oversampling.
  x4,
}

/// Channel count mode.
enum WAChannelCountMode {
  /// Max number of channels in use.
  max,
  /// Clamped to max number of channels.
  clampedMax,
  /// Explicit number of channels.
  explicit,
}

/// Channel interpretation.
enum WAChannelInterpretation {
  /// Speaker-based interpretation.
  speakers,
  /// Discrete channel interpretation.
  discrete,
}
