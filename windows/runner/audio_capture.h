#pragma once
#include <atomic>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct OutputDevice { std::string id; std::string name; };
struct CaptureState {
  bool running = false;
  int samples = 0;
  double level = 0;
  std::string error;
  std::string device;
  uint64_t sequence = 0;
};

class AudioCapture {
 public:
  ~AudioCapture();
  static std::vector<OutputDevice> Devices();
  void Start(const std::string& device_id);
  void Stop();
  CaptureState State();
  std::vector<uint8_t> Snapshot(int seconds);
 private:
  void Run(std::string device_id);
  std::atomic<bool> stop_{true};
  std::thread worker_;
  std::mutex mutex_;
  std::deque<int16_t> ring_;
  CaptureState state_;
  uint64_t last_packet_ms_ = 0;
};
