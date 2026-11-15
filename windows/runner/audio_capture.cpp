#include "audio_capture.h"
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <sstream>
#include <stdexcept>

using Microsoft::WRL::ComPtr;
namespace {
std::string Utf8(const wchar_t* text) {
  if (!text) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  std::string result(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, result.data(), n, nullptr, nullptr);
  if (!result.empty()) result.pop_back();
  return result;
}
std::wstring Wide(const std::string& text) {
  int n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), n);
  return result;
}
void Check(HRESULT hr, const char* operation) {
  if (FAILED(hr)) {
    std::ostringstream message;
    message << operation << " (0x" << std::hex << static_cast<unsigned long>(hr) << ")";
    throw std::runtime_error(message.str());
  }
}
std::string DeviceName(IMMDevice* device) {
  ComPtr<IPropertyStore> store;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &store))) return "Windows audio";
  PROPVARIANT value;
  PropVariantInit(&value);
  std::string name = "Windows audio";
  if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &value)) && value.vt == VT_LPWSTR) name = Utf8(value.pwszVal);
  PropVariantClear(&value);
  return name;
}
}

AudioCapture::~AudioCapture() { Stop(); }
std::vector<OutputDevice> AudioCapture::Devices() {
  HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  std::vector<OutputDevice> result;
  {
    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDeviceCollection> devices;
    if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) &&
        SUCCEEDED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices))) {
      UINT count = 0;
      devices->GetCount(&count);
      for (UINT i = 0; i < count; ++i) {
        ComPtr<IMMDevice> device;
        if (FAILED(devices->Item(i, &device))) continue;
        LPWSTR id = nullptr;
        if (SUCCEEDED(device->GetId(&id))) {
          result.push_back({Utf8(id), DeviceName(device.Get())});
          CoTaskMemFree(id);
        }
      }
    }
  }
  if (SUCCEEDED(com)) CoUninitialize();
  return result;
}
void AudioCapture::Start(const std::string& id) {
  Stop();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    ring_.clear(); state_ = {}; last_packet_ms_ = 0;
  }
  stop_ = false;
  worker_ = std::thread(&AudioCapture::Run, this, id);
}
void AudioCapture::Stop() {
  stop_ = true;
  if (worker_.joinable()) worker_.join();
  std::lock_guard<std::mutex> lock(mutex_);
  state_.running = false;
  ring_.clear();
}
CaptureState AudioCapture::State() {
  std::lock_guard<std::mutex> lock(mutex_);
  auto result = state_;
  const bool fresh = last_packet_ms_ && GetTickCount64() - last_packet_ms_ < 800;
  result.samples = fresh ? static_cast<int>(ring_.size()) : 0;
  double sum = 0;
  size_t count = std::min<size_t>(1600, ring_.size());
  for (size_t i = ring_.size() - count; i < ring_.size(); ++i) {
    double sample = ring_[i] / 32768.0; sum += sample * sample;
  }
  result.level = fresh && count ? std::sqrt(sum / count) : 0;
  return result;
}
std::vector<uint8_t> AudioCapture::Snapshot(int seconds) {
  std::lock_guard<std::mutex> lock(mutex_);
  size_t count = static_cast<size_t>(std::clamp(seconds, 1, 12)) * 8000;
  if (!state_.running || ring_.size() < count || !last_packet_ms_ || GetTickCount64() - last_packet_ms_ > 800) return {};
  std::vector<uint8_t> bytes(count * 2);
  size_t begin = ring_.size() - count;
  for (size_t i = 0; i < count; ++i) {
    uint16_t value = static_cast<uint16_t>(ring_[begin + i]);
    bytes[i * 2] = static_cast<uint8_t>(value & 255);
    bytes[i * 2 + 1] = static_cast<uint8_t>(value >> 8);
  }
  return bytes;
}

void AudioCapture::Run(std::string device_id) {
  HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  WAVEFORMATEX* format = nullptr;
  ComPtr<IAudioClient> client;
  bool started = false;
  try {
    Check(com, "Initialize audio thread");
    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDevice> device;
    Check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)), "Open audio devices");
    if (device_id.empty()) Check(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device), "Find output device");
    else Check(enumerator->GetDevice(Wide(device_id).c_str(), &device), "Find selected output");
    auto name = DeviceName(device.Get());
    Check(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client), "Open output audio");
    Check(client->GetMixFormat(&format), "Read audio format");
    bool is_float = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
    bool is_pcm = format->wFormatTag == WAVE_FORMAT_PCM;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= 22) {
      auto ext = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format);
      is_float = IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
      is_pcm = IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_PCM);
    }
    if ((!is_float && !is_pcm) || (is_float && format->wBitsPerSample != 32) ||
        (!is_float && format->wBitsPerSample != 16 && format->wBitsPerSample != 24 && format->wBitsPerSample != 32) || !format->nChannels || format->nSamplesPerSec < 8000)
      throw std::runtime_error("Unsupported output audio format");
    Check(client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 1000000, 0, format, nullptr), "Start loopback capture");
    ComPtr<IAudioCaptureClient> capture;
    Check(client->GetService(IID_PPV_ARGS(&capture)), "Open loopback stream");
    Check(client->Start(), "Start audio stream"); started = true;
    {
      std::lock_guard<std::mutex> lock(mutex_); state_.running = true; state_.device = name;
    }
    double phase = 0, sum = 0;
    int accumulated = 0;
    while (!stop_) {
      UINT32 frames = 0;
      Check(capture->GetNextPacketSize(&frames), "Read output audio (device may have changed)");
      if (!frames) { Sleep(8); continue; }
      BYTE* data = nullptr; DWORD flags = 0;
      Check(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr), "Read output samples");
      const auto now = GetTickCount64();
      std::vector<int16_t> block;
      block.reserve(frames * 8000 / format->nSamplesPerSec + 2);
      const int bytes = format->wBitsPerSample / 8;
      for (UINT32 f = 0; f < frames; ++f) {
        double mono = 0;
        if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
          for (WORD c = 0; c < format->nChannels; ++c) {
            const BYTE* sample = data + f * format->nBlockAlign + c * bytes;
            if (is_float) { float value; std::memcpy(&value, sample, 4); mono += std::isfinite(value) ? value : 0; }
            else if (bytes == 2) { int16_t value; std::memcpy(&value, sample, 2); mono += value / 32768.0; }
            else if (bytes == 3) { int32_t value = sample[0] | (sample[1] << 8) | (sample[2] << 16); if (value & 0x800000) value |= static_cast<int32_t>(0xff000000); mono += value / 8388608.0; }
            else { int32_t value; std::memcpy(&value, sample, 4); mono += value / 2147483648.0; }
          }
          mono /= format->nChannels;
        }
        sum += mono; ++accumulated; phase += 8000;
        if (phase >= format->nSamplesPerSec) {
          block.push_back(static_cast<int16_t>(std::clamp(sum / accumulated, -1.0, 1.0) * 32767));
          phase -= format->nSamplesPerSec; sum = 0; accumulated = 0;
        }
      }
      Check(capture->ReleaseBuffer(frames), "Release output samples");
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if ((last_packet_ms_ && now - last_packet_ms_ > 500) || (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)) ring_.clear();
        last_packet_ms_ = now;
        ring_.insert(ring_.end(), block.begin(), block.end());
        while (ring_.size() > 12 * 8000) ring_.pop_front();
        state_.sequence += block.size();
      }
    }
  } catch (const std::exception& error) {
    std::lock_guard<std::mutex> lock(mutex_); state_.error = error.what();
  }
  if (started && client) client->Stop();
  client.Reset();
  if (format) CoTaskMemFree(format);
  if (SUCCEEDED(com)) CoUninitialize();
  std::lock_guard<std::mutex> lock(mutex_); state_.running = false;
}
