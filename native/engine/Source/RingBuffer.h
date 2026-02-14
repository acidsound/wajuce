#pragma once
#include <algorithm>
#include <atomic>
#include <vector>

namespace wajuce {

/**
 * Single-Producer Single-Consumer (SPSC) Lock-Free Ring Buffer.
 * Optimized for audio data transfer between Dart Isolate and JUCE Engine.
 */
class SPSCRingBuffer {
public:
  SPSCRingBuffer(int capacity) : capacity(capacity), buffer(capacity, 0.0f) {
    readPos.store(0);
    writePos.store(0);
  }

  int getAvailableToRead() const {
    int w = writePos.load(std::memory_order_acquire);
    int r = readPos.load(std::memory_order_relaxed);
    int diff = w - r;
    return diff >= 0 ? diff : diff + capacity;
  }

  int getAvailableToWrite() const {
    int w = writePos.load(std::memory_order_relaxed);
    int r = readPos.load(std::memory_order_acquire);
    int diff = r - w - 1;
    return diff >= 0 ? diff : diff + capacity;
  }

  int write(const float *data, int numSamples) {
    int available = getAvailableToWrite();
    int toWrite = std::min(numSamples, available);
    int w = writePos.load(std::memory_order_relaxed);

    for (int i = 0; i < toWrite; ++i) {
      buffer[w] = data[i];
      w = (w + 1) % capacity;
    }

    writePos.store(w, std::memory_order_release);
    return toWrite;
  }

  int read(float *data, int numSamples) {
    int available = getAvailableToRead();
    int toRead = std::min(numSamples, available);
    int r = readPos.load(std::memory_order_relaxed);

    for (int i = 0; i < toRead; ++i) {
      data[i] = buffer[r];
      r = (r + 1) % capacity;
    }

    readPos.store(r, std::memory_order_release);
    return toRead;
  }

  void clear() {
    readPos.store(0);
    writePos.store(0);
    std::fill(buffer.begin(), buffer.end(), 0.0f);
  }

  int getReadPos() const { return readPos.load(std::memory_order_acquire); }
  int getWritePos() const { return writePos.load(std::memory_order_acquire); }
  void setReadPos(int pos) {
    const int wrapped = ((pos % capacity) + capacity) % capacity;
    readPos.store(wrapped, std::memory_order_release);
  }
  void setWritePos(int pos) {
    const int wrapped = ((pos % capacity) + capacity) % capacity;
    writePos.store(wrapped, std::memory_order_release);
  }

  // Direct pointers for Zero-Copy FFI access
  float *getBufferRawPtr() { return buffer.data(); }
  int *getReadPosPtr() { return reinterpret_cast<int *>(&readPos); }
  int *getWritePosPtr() { return reinterpret_cast<int *>(&writePos); }
  int getCapacity() const { return capacity; }

private:
  int capacity;
  std::vector<float> buffer;
  std::atomic<int> readPos;
  std::atomic<int> writePos;
};

/**
 * Multi-channel wrapper for SPSCRingBuffer.
 */
class MultiChannelSPSCRingBuffer {
public:
  MultiChannelSPSCRingBuffer(int channels, int capacityPerChannel)
      : numChannels(channels) {
    for (int i = 0; i < channels; ++i) {
      channels_buffers.push_back(
          std::make_unique<SPSCRingBuffer>(capacityPerChannel));
    }
  }

  SPSCRingBuffer *getChannel(int channel) {
    if (channel < 0 || channel >= numChannels)
      return nullptr;
    return channels_buffers[channel].get();
  }

  int getNumChannels() const { return numChannels; }
  void clear() {
    for (auto &buf : channels_buffers) {
      buf->clear();
    }
  }

private:
  int numChannels;
  std::vector<std::unique_ptr<SPSCRingBuffer>> channels_buffers;
};

} // namespace wajuce
