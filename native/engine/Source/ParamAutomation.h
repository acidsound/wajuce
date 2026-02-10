#pragma once
/**
 * ParamAutomation.h — Scheduled parameter value changes.
 * Implements Web Audio AudioParam automation timeline.
 */

#include <algorithm>
#include <cmath>
#include <mutex>
#include <vector>

namespace wajuce {

enum class AutomationEventType {
  SetValue,
  LinearRamp,
  ExponentialRamp,
  SetTarget,
  Cancel,
};

struct AutomationEvent {
  AutomationEventType type;
  double time;        // schedule time
  float value;        // target value
  float timeConstant; // for setTargetAtTime
};

class ParamTimeline {
public:
  void setValueAtTime(float value, double time) {
    std::lock_guard<std::mutex> lock(mtx);
    events.push_back({AutomationEventType::SetValue, time, value, 0.0f});
    sortEvents();
  }

  void linearRampToValueAtTime(float value, double endTime) {
    std::lock_guard<std::mutex> lock(mtx);
    events.push_back({AutomationEventType::LinearRamp, endTime, value, 0.0f});
    sortEvents();
  }

  void exponentialRampToValueAtTime(float value, double endTime) {
    std::lock_guard<std::mutex> lock(mtx);
    events.push_back(
        {AutomationEventType::ExponentialRamp, endTime, value, 0.0f});
    sortEvents();
  }

  void setTargetAtTime(float target, double startTime, float timeConstant) {
    std::lock_guard<std::mutex> lock(mtx);
    events.push_back(
        {AutomationEventType::SetTarget, startTime, target, timeConstant});
    sortEvents();
  }

  void cancelScheduledValues(double cancelTime) {
    std::lock_guard<std::mutex> lock(mtx);
    events.erase(std::remove_if(events.begin(), events.end(),
                                [cancelTime](const AutomationEvent &e) {
                                  return e.time >= cancelTime;
                                }),
                 events.end());
  }

  // Process automation for a block of samples
  // Returns the value at the end of the block
  float processBlock(double startTime, double sampleRate, int numSamples,
                     float *outputValues = nullptr) {
    std::lock_guard<std::mutex> lock(mtx);
    float val = lastValue;

    // Optimize: Only search if there are events and we are past the current
    // event time
    for (int i = 0; i < numSamples; ++i) {
      double t = startTime + (double)i / sampleRate;
      val = getValueAtTime(val, t, sampleRate);
      if (outputValues)
        outputValues[i] = val;
    }
    lastValue = val;
    return val;
  }

  void setLastValue(float v) {
    std::lock_guard<std::mutex> lock(mtx);
    lastValue = v;
  }

private:
  float getValueAtTime(float currentVal, double time, double sampleRate) {
    if (events.empty())
      return lastValue;

    // 1. Find the current event (the latest event with e.time <= time)
    int currentIdx = -1;
    for (int i = (int)events.size() - 1; i >= 0; --i) {
      if (events[i].time <= time) {
        currentIdx = i;
        break;
      }
    }

    // 2. If no event has started yet, return the initial/last value
    if (currentIdx == -1) {
      return lastValue;
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

        float startValue =
            (currentIdx == 0) ? lastValue : events[currentIdx].value;
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
    std::sort(events.begin(), events.end(),
              [](const AutomationEvent &a, const AutomationEvent &b) {
                return a.time < b.time;
              });
  }

  std::vector<AutomationEvent> events;
  std::mutex mtx;
  float lastValue = 0.0f;
};

} // namespace wajuce
