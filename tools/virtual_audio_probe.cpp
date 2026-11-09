// Execute the actual ring, ABI validator and rate converter without loading a driver.
#include "../windows/virtual_audio/audio_protocol.h"
#include "../windows/virtual_audio/pcm_ring.h"
#include "../windows/virtual_audio/pcm_converter.h"
#include "../windows/virtual_audio/cable_assignment.h"
#include "../windows/virtual_audio/render_queue.h"
#include "../windows/virtual_audio/pcm_packet.h"
#include "virtual_audio_kernel_shim.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <deque>
#include <iostream>
#include <random>
#include <vector>
#include <thread>

extern "C" NTSTATUS UserPcmBuffer_Init(ULONG);
extern "C" NTSTATUS LocalistAudioRequest(PIRP);
extern "C" NTSTATUS LocalistAudioOpenClose(PIRP);
extern "C" ULONG LocalistReadAudio(ULONG, UCHAR*, ULONG);

void TestTransport() {
  assert(UserPcmBuffer_Init(0) == STATUS_SUCCESS);
  FILE_OBJECT owners[4]{{1},{2},{3},{4}}, stranger{5};
  std::vector<std::thread> threads;
  for (ULONG slot = 0; slot < 4; ++slot) threads.emplace_back([slot, &owners, &stranger] {
    LocalistAudioPacket packet{};
    packet.header = {LOCALIST_AUDIO_MAGIC, 1, static_cast<uint32_t>(slot), 480, 48000, 1, 16, 0};
    for (auto& sample : packet.samples) sample = static_cast<int16_t>(1000 + slot);
    IRP irp{}; irp.AssociatedIrp.SystemBuffer = &packet;
    irp.stack.FileObject = &owners[slot];
    irp.stack.Parameters.DeviceIoControl = {LOCALIST_AUDIO_WRITE_IOCTL, 32 + 960};
    std::array<int16_t, 480> output{};
    for (int cycle = 0; cycle < 1000; ++cycle) {
      assert(LocalistAudioRequest(&irp) == STATUS_SUCCESS);
      assert(LocalistReadAudio(slot, reinterpret_cast<UCHAR*>(output.data()), sizeof(output)) == sizeof(output));
      for (auto value : output) assert(value == static_cast<int16_t>(1000 + slot));
    }
    irp.stack.FileObject = &stranger;
    assert(LocalistAudioRequest(&irp) == STATUS_DEVICE_BUSY);
    irp.stack.FileObject = &owners[slot];
    irp.stack.Parameters.DeviceIoControl.InputBufferLength = sizeof(LocalistAudioHeader) - 1;
    assert(LocalistAudioRequest(&irp) == STATUS_INVALID_DEVICE_REQUEST);
    irp.stack.Parameters.DeviceIoControl.InputBufferLength = 32 + 960;
    assert(LocalistAudioRequest(&irp) == STATUS_SUCCESS);
    irp.stack.MajorFunction = IRP_MJ_CLOSE;
    assert(LocalistAudioOpenClose(&irp) == STATUS_SUCCESS);
    assert(LocalistReadAudio(slot, reinterpret_cast<UCHAR*>(output.data()), sizeof(output)) == 0);
    for (auto value : output) assert(value == 0);
    irp.stack.FileObject = &stranger;
    assert(LocalistAudioRequest(&irp) == STATUS_SUCCESS); // Closing releases ownership.
    packet.header.frames = 0; packet.header.flags = LOCALIST_AUDIO_RESET;
    irp.stack.Parameters.DeviceIoControl.InputBufferLength = sizeof(LocalistAudioHeader);
    assert(LocalistAudioRequest(&irp) == STATUS_SUCCESS);
  });
  for (auto& thread : threads) thread.join();
}

int main() {
  LocalistRenderQueue render;
  render.Configure(20,100,6);
  std::array<int16_t,960> quiet{};quiet.fill(1000);
  std::array<int16_t,480> queue_output{};
  render.Push(quiet.data(),480);
  assert(render.Pull(queue_output.data(),480)==0);
  render.Push(quiet.data(),480);
  assert(render.Pull(queue_output.data(),480)==480&&queue_output[0]>=1990&&queue_output[0]<=2000);
  std::array<int16_t,4800> loud{};loud.fill(30000);
  render.Push(loud.data(),loud.size());
  assert(render.Dropped()==480&&render.Clipped()==4800);
  for(int i=0;i<11;++i)render.Pull(queue_output.data(),480);
  assert(render.Underruns()>0&&render.Buffered()==0);
  for(const auto gain : {-30.0,40.0}) {
    render.Configure(0,100,gain);
    const int16_t input=100;
    render.Push(&input,1);
    assert(render.Pull(queue_output.data(),1)==1);
    assert(queue_output[0]==(gain<0?3:10000));
  }
  LocalistNetworkPcmHeader header;
  std::vector<uint8_t> valid(sizeof(header)+960*sizeof(int16_t));header.frames=960;
  std::memcpy(valid.data(),&header,sizeof(header));
  assert(ReadLocalistNetworkPcm(valid.data(),valid.size(),header));
  valid[0]=0;assert(!ReadLocalistNetworkPcm(valid.data(),valid.size(),header));
  const std::vector<std::string> cables={"base","a","b","c"};
  std::vector<std::string> allocated;
  for(int i=0;i<4;++i){const int index=SelectLocalistCable(cables,allocated,"");assert(index==i);allocated.push_back(cables[index]);}
  assert(SelectLocalistCable(cables,allocated,"")==-1);
  allocated.erase(allocated.begin()+1);
  assert(SelectLocalistCable(cables,allocated,"")==1);
  assert(SelectLocalistCable(cables,allocated,"base")==-1);
  assert(SelectLocalistCable(cables,allocated,"missing")==-1);
  assert(SelectLocalistCable(cables,allocated,"a")==1);
  TestTransport();
  LocalistAudioPacket packet{};
  packet.header = {LOCALIST_AUDIO_MAGIC, 1, 0, 480, 48000, 1, 16, 0};
  constexpr size_t bytes = sizeof(LocalistAudioHeader) + 480 * 2;
  assert(LocalistValidAudioPacket(&packet, bytes));
  assert(!LocalistValidAudioPacket(nullptr, bytes));
  for (size_t size = 0; size < sizeof(packet) + 128; ++size)
    assert(LocalistValidAudioPacket(&packet, size) == (size == bytes));
  std::mt19937 random(991);
  for (int i = 0; i < 100000; ++i) {
    auto fields = reinterpret_cast<uint32_t*>(&packet.header);
    const unsigned int field = random() % 8;
    const auto value = fields[field];
    fields[field] ^= 1u << (random() % 32);
    assert(LocalistValidAudioPacket(&packet, bytes) == (field == 2 && fields[field] < 4));
    fields[field] = value;
  }
  packet.header.flags = LOCALIST_AUDIO_RESET;
  assert(!LocalistValidAudioPacket(&packet, bytes));
  packet.header.frames = 0;
  assert(LocalistValidAudioPacket(&packet, sizeof(LocalistAudioHeader)));

  std::array<LocalistPcmRing, 4> rings{};
  std::array<std::deque<int16_t>, 4> model{};
  for (int step = 0; step < 20000; ++step) {
    const unsigned int slot = random() % 4;
    auto& ring = rings[slot]; auto& queue = model[slot];
    const size_t frames = random() % 12000;
    if (random() % 2) {
      std::vector<int16_t> input(frames);
      for (auto& sample : input) { sample = static_cast<int16_t>(random()); queue.push_back(sample); }
      while (queue.size() > ring.capacity) queue.pop_front();
      ring.Push(input.data(), input.size());
    } else {
      std::vector<int16_t> output(frames + 2, 12345);
      const size_t expected = std::min(frames, queue.size());
      assert(ring.Pull(output.data() + 1, frames) == expected);
      assert(output.front() == 12345 && output.back() == 12345);
      for (size_t i = 0; i < frames; ++i) {
        const auto value = queue.empty() ? 0 : queue.front();
        if (!queue.empty()) queue.pop_front();
        assert(output[i + 1] == value);
      }
    }
    assert(ring.count == queue.size());
    if (step % 111 == 0) { ring.Clear(); queue.clear(); }
  }
  for (int rate : {8000, 16000, 32000, 44100, 48000}) {
    LocalistPcmConverter converter;
    std::vector<int16_t> output;
    const auto emit = [&output](int16_t value) { output.push_back(value); };
    std::vector<int16_t> input(static_cast<size_t>(rate / 100) * 2);
    for (size_t i = 0; i < input.size(); i += 2) { input[i] = 3000; input[i + 1] = -1000; }
    for (int i = 0; i < 100; ++i) assert(converter.Convert(input.data(), 16, rate, 2, input.size()/2, emit));
    assert(output.size() == 48000);
    assert(std::all_of(output.begin(), output.end(), [](int16_t value) { return value == 1000; }));
    assert(!converter.Convert(input.data(), 32, rate, 2, 100, emit));
    assert(!converter.Convert(input.data(), 16, rate, 0, 100, emit));
    assert(!converter.Convert(input.data(), 16, rate, 9, 100, emit));
    assert(!converter.Convert(input.data(), 16, rate, 2, static_cast<size_t>(rate), emit));
    converter.Reset(); output.clear();
    assert(converter.Convert(input.data(), 16, rate, 2, input.size()/2, emit));
    assert(output.size() == 480);
  }
  std::cout << "LOCALIST_AUDIO_ABI_RING_CONVERTER_OK 100000 malformed packets; 20000 ring operations; 5 sample rates\n";
}
