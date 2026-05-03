#pragma once
/**
 * ParamAutomation.h — Scheduled parameter value changes.
 * Implements Web Audio AudioParam automation timeline.
 */

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <mutex>
#include <vector>

namespace wajuce {

enum class AutomationEventType {
  SetValue,
  LinearRamp,
  ExponentialRamp,
  SetTarget,
  ValueCurve,
  Cancel,
};

struct AutomationEvent {
  AutomationEventType type;
  double time;        // schedule time
  float value;        // target value
  float timeConstant; // for setTargetAtTime
  double duration = 0.0;
  std::vector<float> curve;
};

class ParamTimeline {
public:
  void setValueAtTime(float value, double time) {
    std::lock_guard<std::mutex> lock(mtx);
    addEvent({AutomationEventType::SetValue, time, value, 0.0f});
  }

  void linearRampToValueAtTime(float value, double endTime) {
    std::lock_guard<std::mutex> lock(mtx);
    addEvent({AutomationEventType::LinearRamp, endTime, value, 0.0f});
  }

  void exponentialRampToValueAtTime(float value, double endTime) {
    std::lock_guard<std::mutex> lock(mtx);
    addEvent({AutomationEventType::ExponentialRamp, endTime, value, 0.0f});
  }

  void setTargetAtTime(float target, double startTime, float timeConstant) {
    std::lock_guard<std::mutex> lock(mtx);
    addEvent({AutomationEventType::SetTarget, startTime, target, timeConstant});
  }

  void setValueCurveAtTime(const float *values, int length, double startTime,
                           double duration) {
    if (!values || length <= 0 || duration <= 0.0) {
      return;
    }
    std::lock_guard<std::mutex> lock(mtx);
    AutomationEvent event{AutomationEventType::ValueCurve, startTime,
                          values[length - 1], 0.0f};
    event.duration = duration;
    event.curve.assign(values, values + length);
    addEvent(event);
  }

  void cancelScheduledValues(double cancelTime) {
    std::lock_guard<std::mutex> lock(mtx);
    events.erase(std::remove_if(events.begin(), events.end(),
                                [cancelTime](const AutomationEvent &e) {
                                  return e.time >= cancelTime;
                                }),
                 events.end());
  }

  void cancelAndHoldAtTime(double cancelTime, double sampleRate) {
    std::lock_guard<std::mutex> lock(mtx);
    const float held = valueAtTimeUnlocked(cancelTime, sampleRate);
    events.erase(std::remove_if(events.begin(), events.end(),
                                [cancelTime](const AutomationEvent &e) {
                                  return e.time >= cancelTime;
                                }),
                 events.end());
    addEvent({AutomationEventType::SetValue, cancelTime, held, 0.0f});
  }

  // Process automation for a block of samples
  // Returns the value at the end of the block
  float processBlock(double startTime, double sampleRate, int numSamples,
                     float *outputValues = nullptr) {
    std::unique_lock<std::mutex> lock(mtx, std::try_to_lock);
    if (!lock.owns_lock()) {
      const float held = lastValue.load(std::memory_order_relaxed);
      if (outputValues) {
        std::fill(outputValues, outputValues + numSamples, held);
      }
      return held;
    }

    if (sampleRate <= 0.0 || numSamples <= 0) {
      return lastValue.load(std::memory_order_relaxed);
    }

    prunePastEvents(startTime);

    const float initialValue = lastValue.load(std::memory_order_relaxed);
    float val = initialValue;
    int currentIdx = -1;
    size_t nextIdx = 0;
    while (nextIdx < events.size() && events[nextIdx].time <= startTime) {
      currentIdx = static_cast<int>(nextIdx);
      ++nextIdx;
    }

    for (int i = 0; i < numSamples; ++i) {
      double t = startTime + (double)i / sampleRate;
      while (nextIdx < events.size() && events[nextIdx].time <= t) {
        currentIdx = static_cast<int>(nextIdx);
        ++nextIdx;
      }
      val = getValueAtEventIndex(initialValue, val, currentIdx, t, sampleRate);
      if (outputValues)
        outputValues[i] = val;
    }
    lastValue.store(val, std::memory_order_relaxed);
    return val;
  }

  void setLastValue(float v) {
    std::lock_guard<std::mutex> lock(mtx);
    lastValue.store(v, std::memory_order_relaxed);
  }

  bool holdsValueForBlock(float value, double startTime, double sampleRate,
                          int numSamples, float tolerance = 1.0e-7f) {
    std::unique_lock<std::mutex> lock(mtx, std::try_to_lock);
    if (!lock.owns_lock()) {
      return false;
    }
    if (sampleRate <= 0.0 || numSamples <= 0) {
      return std::abs(lastValue.load(std::memory_order_relaxed) - value) <=
             tolerance;
    }
    prunePastEvents(startTime);
    const double blockEnd = startTime + static_cast<double>(numSamples) /
                                            std::max(1.0, sampleRate);
    for (const auto &event : events) {
      if (event.time <= blockEnd) {
        return false;
      }
      break;
    }
    return std::abs(lastValue.load(std::memory_order_relaxed) - value) <=
           tolerance;
  }

private:
  float valueAtTimeUnlocked(double time, double sampleRate) const {
    float value = lastValue.load(std::memory_order_relaxed);
    if (sampleRate <= 0.0) {
      sampleRate = 44100.0;
    }

    for (size_t i = 0; i < events.size(); ++i) {
      const auto &event = events[i];
      if (event.type == AutomationEventType::LinearRamp ||
          event.type == AutomationEventType::ExponentialRamp) {
        if (i > 0 && time < event.time) {
          const auto &previous = events[i - 1];
          const double duration = event.time - previous.time;
          if (duration > 0.0 && time >= previous.time) {
            const float progress = static_cast<float>(
                std::clamp((time - previous.time) / duration, 0.0, 1.0));
            if (event.type == AutomationEventType::LinearRamp) {
              return previous.value + progress * (event.value - previous.value);
            }
            if (previous.value > 0.0f && event.value > 0.0f) {
              return previous.value *
                     std::pow(event.value / previous.value, progress);
            }
          }
          return value;
        }
        if (time >= event.time) {
          value = event.value;
          continue;
        }
      }

      if (event.time > time) {
        break;
      }

      switch (event.type) {
      case AutomationEventType::SetValue:
        value = event.value;
        break;
      case AutomationEventType::ValueCurve:
        if (!event.curve.empty() && event.duration > 0.0) {
          if (time >= event.time + event.duration) {
            value = event.curve.back();
          } else {
            const double position =
                ((time - event.time) / event.duration) *
                (event.curve.size() - 1);
            const auto i0 = static_cast<size_t>(std::floor(position));
            const auto i1 = std::min(i0 + 1, event.curve.size() - 1);
            const float frac =
                static_cast<float>(position - std::floor(position));
            value = event.curve[i0] +
                    frac * (event.curve[i1] - event.curve[i0]);
          }
        }
        break;
      case AutomationEventType::SetTarget:
        if (event.timeConstant > 0.0f) {
          value = event.value + (value - event.value) *
                                    std::exp(-(time - event.time) /
                                             event.timeConstant);
        }
        break;
      case AutomationEventType::LinearRamp:
      case AutomationEventType::ExponentialRamp:
      case AutomationEventType::Cancel:
        break;
      }
    }

    return value;
  }

  float getValueAtEventIndex(float initialValue, float currentVal,
                             int currentIdx, double time, double sampleRate) {
    if (currentIdx < 0) {
      return initialValue;
    }

    const auto &e = events[currentIdx];
    float val = currentVal;

    // 3. Check if the NEXT event is a ramp (Linear/Exponential)
    // If so, we are currently in a ramping phase between currentIdx and
    // currentIdx + 1
    if ((size_t)currentIdx + 1 < events.size()) {
      const auto &nextE = events[currentIdx + 1];
      if (nextE.type == AutomationEventType::LinearRamp ||
          nextE.type == AutomationEventType::ExponentialRamp) {

        float startValue = events[currentIdx].value;
        double startTime = events[currentIdx].time;
        double endTime = nextE.time;
        float duration = (float)(endTime - startTime);

        if (duration > 0) {
          float t = (float)((time - startTime) / duration);
          t = std::max(0.0f, std::min(1.0f, t));

          if (nextE.type == AutomationEventType::LinearRamp) {
            return startValue + t * (nextE.value - startValue);
          } else { // Exponential
            if (startValue > 0 && nextE.value > 0) {
              return startValue * std::pow(nextE.value / startValue, t);
            }
          }
        }
        return nextE.value;
      }
    }

    // 4. No ramp ahead, process the current event's persistent behavior
    switch (e.type) {
    case AutomationEventType::SetValue:
    case AutomationEventType::LinearRamp:
    case AutomationEventType::ExponentialRamp:
      // These are discrete set-points, they just hold their value until next
      // event
      val = e.value;
      break;

    case AutomationEventType::ValueCurve:
      if (!e.curve.empty() && e.duration > 0.0) {
        if (time <= e.time) {
          val = e.curve.front();
        } else if (time >= e.time + e.duration) {
          val = e.curve.back();
        } else {
          const double position =
              ((time - e.time) / e.duration) * (e.curve.size() - 1);
          const auto i0 = static_cast<size_t>(std::floor(position));
          const auto i1 = std::min(i0 + 1, e.curve.size() - 1);
          const float frac = static_cast<float>(position - std::floor(position));
          val = e.curve[i0] + frac * (e.curve[i1] - e.curve[i0]);
        }
      }
      break;

    case AutomationEventType::SetTarget:
      if (time >= e.time && e.timeConstant > 0) {
        // Recursive formula for smooth target approach (per sample)
        float dt = 1.0f / (float)sampleRate;
        val = e.value + (val - e.value) * std::exp(-dt / e.timeConstant);
      }
      break;

    default:
      break;
    }

    return val;
  }

  void sortEvents() {
    std::stable_sort(events.begin(), events.end(),
                     [](const AutomationEvent &a, const AutomationEvent &b) {
                       return a.time < b.time;
                     });
  }

  void addEvent(const AutomationEvent &event) {
    events.push_back(event);
    if (events.size() > 1 &&
        events[events.size() - 2].time > events.back().time) {
      sortEvents();
    }
  }

  // Keep at most one event in the past as a baseline for future ramps.
  void prunePastEvents(double currentTime) {
    if (events.size() < 3)
      return;

    size_t keepFrom = 0;
    while (keepFrom + 1 < events.size() && events[keepFrom + 1].time <= currentTime) {
      ++keepFrom;
    }

    if (keepFrom > 0) {
      events.erase(events.begin(),
                   events.begin() + static_cast<std::ptrdiff_t>(keepFrom));
    }
  }

  std::vector<AutomationEvent> events;
  std::mutex mtx;
  std::atomic<float> lastValue{0.0f};
};

} // namespace wajuce
