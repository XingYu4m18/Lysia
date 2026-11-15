#include "audio_decode.h"
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <sstream>
#include <stdexcept>
#define STB_VORBIS_HEADER_ONLY
#include "vendor/stb_vorbis.c"
using Microsoft::WRL::ComPtr;
namespace {
void Check(HRESULT hr, const char* step) {
  if (FAILED(hr)) {std::ostringstream text;text << step << " (0x" << std::hex << static_cast<unsigned long>(hr) << ")";throw std::runtime_error(text.str());}
}
std::vector<uint8_t> ReadVorbis(const std::wstring& path) {
  FILE* file=nullptr;
  if (_wfopen_s(&file,path.c_str(),L"rb") || !file) throw std::runtime_error("无法打开音频文件");
  int error=0;
  stb_vorbis* decoder=stb_vorbis_open_file(file,1,&error,nullptr);
  if(!decoder){fclose(file);throw std::runtime_error("OGG 文件不是受支持的 Vorbis 音频，或文件已损坏");}
  std::unique_ptr<stb_vorbis, decltype(&stb_vorbis_close)> handle(decoder,stb_vorbis_close);
  auto info=stb_vorbis_get_info(decoder);
  if(info.channels<1 || info.channels>32 || info.sample_rate<8000 || info.sample_rate>384000)throw std::runtime_error("不支持此音频的声道或采样率");
  const auto duration=stb_vorbis_stream_length_in_seconds(decoder);
  unsigned int offset=static_cast<unsigned int>(std::min(15.0,std::max(0.0,(static_cast<double>(duration)-6.0)/2))*info.sample_rate);
  if(offset && !stb_vorbis_seek(decoder,offset))throw std::runtime_error("无法定位 OGG 音频片段");
  const int wanted=static_cast<int>(info.sample_rate)*6;
  std::vector<float> samples(static_cast<size_t>(wanted)*info.channels);
  int frames=stb_vorbis_get_samples_float_interleaved(decoder,info.channels,samples.data(),static_cast<int>(samples.size()));
  if(frames<static_cast<int>(info.sample_rate)*3)throw std::runtime_error("音频需要至少 3 秒");
  int count=std::min(48000,static_cast<int>(static_cast<int64_t>(frames)*8000/info.sample_rate));
  std::vector<uint8_t> output(static_cast<size_t>(count)*2);
  for(int i=0;i<count;++i){
    double source=static_cast<double>(i)*info.sample_rate/8000;int low=static_cast<int>(source);double fraction=source-low,mono=0;
    for(int ch=0;ch<info.channels;++ch){double a=samples[static_cast<size_t>(low)*info.channels+ch], b=samples[static_cast<size_t>(std::min(low+1,frames-1))*info.channels+ch];mono+=a*(1-fraction)+b*fraction;}
    mono/=info.channels;if(!std::isfinite(mono))mono=0;
    uint16_t value=static_cast<uint16_t>(static_cast<int16_t>(std::clamp(mono,-1.0,1.0)*32767));
    output[i*2]=static_cast<uint8_t>(value&255);output[i*2+1]=static_cast<uint8_t>(value>>8);
  }
  return output;
}
std::vector<uint8_t> ReadMediaFoundation(const std::wstring& path) {
  ComPtr<IMFAttributes> attributes;Check(MFCreateAttributes(&attributes,1),"初始化解码器");
  ComPtr<IMFSourceReader> reader;
  Check(MFCreateSourceReaderFromURL(path.c_str(),attributes.Get(),&reader),"无法读取此格式，或系统缺少解码器");
  Check(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),FALSE),"选择音轨");
  Check(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),TRUE),"未找到音轨");
  ComPtr<IMFMediaType> type;Check(MFCreateMediaType(&type),"初始化音频格式");
  Check(type->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio),"设置音频类型");
  Check(type->SetGUID(MF_MT_SUBTYPE,MFAudioFormat_PCM),"设置 PCM 格式");
  Check(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,1),"设置单声道");
  Check(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,8000),"设置采样率");
  Check(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16),"设置位深");
  Check(type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,2),"设置音频块");
  Check(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,16000),"设置码率");
  Check(reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),nullptr,type.Get()),"无法转换此音频格式");
  PROPVARIANT duration;PropVariantInit(&duration);
  if(SUCCEEDED(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE),MF_PD_DURATION,&duration)) && duration.vt==VT_UI8){
    LONGLONG position=std::min<LONGLONG>(150000000,std::max<LONGLONG>(0,(static_cast<LONGLONG>(duration.uhVal.QuadPart)-60000000)/2));
    if(position>0){PROPVARIANT value;InitPropVariantFromInt64(position,&value);reader->SetCurrentPosition(GUID_NULL,value);PropVariantClear(&value);}
  }
  PropVariantClear(&duration);
  std::vector<uint8_t> output;output.reserve(96000);
  for(int attempt=0;attempt<10000 && output.size()<96000;++attempt){
    DWORD flags=0;ComPtr<IMFSample> sample;
    Check(reader->ReadSample(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),0,nullptr,&flags,nullptr,&sample),"音频解码失败");
    if(flags & MF_SOURCE_READERF_ERROR)throw std::runtime_error("音频解码器报告错误");
    if(sample){
      ComPtr<IMFMediaBuffer> buffer;Check(sample->ConvertToContiguousBuffer(&buffer),"读取音频片段");
      BYTE* bytes=nullptr;DWORD length=0;Check(buffer->Lock(&bytes,nullptr,&length),"读取音频数据");
      const size_t count=std::min<size_t>(length,96000-output.size());output.insert(output.end(),bytes,bytes+count);buffer->Unlock();
    }
    if(flags & MF_SOURCE_READERF_ENDOFSTREAM)break;
  }
  output.resize(output.size()&~size_t(1));
  if(output.size()<48000)throw std::runtime_error("音频需要至少 3 秒");
  return output;
}
}
std::vector<uint8_t> DecodeAudioFile(const std::wstring& path) {
  HRESULT com=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
  if(FAILED(com))throw std::runtime_error("无法初始化音频解码线程");
  bool mf=false;
  try{
    std::wstring extension=path.substr(path.find_last_of(L'.')==std::wstring::npos?path.size():path.find_last_of(L'.'));
    std::transform(extension.begin(),extension.end(),extension.begin(),::towlower);
    std::vector<uint8_t> output;
    if(extension==L".ogg" || extension==L".oga")output=ReadVorbis(path);
    else {Check(MFStartup(MF_VERSION),"Windows 音频解码服务不可用");mf=true;output=ReadMediaFoundation(path);}
    if(mf)MFShutdown();CoUninitialize();return output;
  }catch(...){if(mf)MFShutdown();CoUninitialize();throw;}
}
