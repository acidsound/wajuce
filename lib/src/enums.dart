/// Oscillator waveform types.
enum WAOscillatorType {
  sine,
  square,
  sawtooth,
  triangle,
  custom,
}

/// BiquadFilter types.
enum WABiquadFilterType {
  lowpass,
  highpass,
  bandpass,
  lowshelf,
  highshelf,
  peaking,
  notch,
  allpass,
}

/// AudioContext state.
enum WAAudioContextState {
  suspended,
  running,
  closed,
}

/// AudioParam automation rate.
enum WAAutomationRate {
  aRate,
  kRate,
}

/// Panner distance model.
enum WADistanceModel {
  linear,
  inverse,
  exponential,
}

/// Panner panning model.
enum WAPanningModel {
  equalpower,
  hrtf,
}

/// OverSample type for WaveShaper.
enum WAOverSampleType {
  none,
  x2,
  x4,
}

/// Channel count mode.
enum WAChannelCountMode {
  max,
  clampedMax,
  explicit,
}

/// Channel interpretation.
enum WAChannelInterpretation {
  speakers,
  discrete,
}
