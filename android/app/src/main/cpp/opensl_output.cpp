#include <jni.h>
#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>
#include <array>
#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <chrono>

namespace {
class Player {
 public:
  ~Player(){Stop();if(player_)(*player_)->Destroy(player_);if(mix_)(*mix_)->Destroy(mix_);if(engine_)(*engine_)->Destroy(engine_);}
  bool Start(bool effects){
    if(slCreateEngine(&engine_,0,nullptr,0,nullptr,nullptr)!=SL_RESULT_SUCCESS||(*engine_)->Realize(engine_,SL_BOOLEAN_FALSE)!=SL_RESULT_SUCCESS)return false;
    SLEngineItf engine=nullptr;
    if((*engine_)->GetInterface(engine_,SL_IID_ENGINE,&engine)!=SL_RESULT_SUCCESS||(*engine)->CreateOutputMix(engine,&mix_,0,nullptr,nullptr)!=SL_RESULT_SUCCESS||(*mix_)->Realize(mix_,SL_BOOLEAN_FALSE)!=SL_RESULT_SUCCESS)return false;
    SLDataLocator_AndroidSimpleBufferQueue queue{SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE,2};
    SLDataFormat_PCM pcm{SL_DATAFORMAT_PCM,1,SL_SAMPLINGRATE_48,SL_PCMSAMPLEFORMAT_FIXED_16,SL_PCMSAMPLEFORMAT_FIXED_16,SL_SPEAKER_FRONT_CENTER,SL_BYTEORDER_LITTLEENDIAN};
    SLDataSource source{&queue,&pcm};SLDataLocator_OutputMix sink{SL_DATALOCATOR_OUTPUTMIX,mix_};SLDataSink destination{&sink,nullptr};
    const SLInterfaceID interfaces[]={SL_IID_ANDROIDSIMPLEBUFFERQUEUE,SL_IID_ANDROIDCONFIGURATION};
    const SLboolean required[]={SL_BOOLEAN_TRUE,SL_BOOLEAN_TRUE};
    if((*engine)->CreateAudioPlayer(engine,&player_,&source,&destination,2,interfaces,required)!=SL_RESULT_SUCCESS)return false;
    SLAndroidConfigurationItf config=nullptr;
    if((*player_)->GetInterface(player_,SL_IID_ANDROIDCONFIGURATION,&config)==SL_RESULT_SUCCESS){
      SLint32 stream=SL_ANDROID_STREAM_MEDIA;
      (*config)->SetConfiguration(config,SL_ANDROID_KEY_STREAM_TYPE,&stream,sizeof(stream));
      SLuint32 mode=effects?SL_ANDROID_PERFORMANCE_NONE:SL_ANDROID_PERFORMANCE_LATENCY;
      (*config)->SetConfiguration(config,SL_ANDROID_KEY_PERFORMANCE_MODE,&mode,sizeof(mode));
    }
    if((*player_)->Realize(player_,SL_BOOLEAN_FALSE)!=SL_RESULT_SUCCESS||(*player_)->GetInterface(player_,SL_IID_PLAY,&play_)!=SL_RESULT_SUCCESS||(*player_)->GetInterface(player_,SL_IID_ANDROIDSIMPLEBUFFERQUEUE,&queue_)!=SL_RESULT_SUCCESS)return false;
    if((*queue_)->RegisterCallback(queue_,Callback,this)!=SL_RESULT_SUCCESS)return false;
    active_=true;
    return (*play_)->SetPlayState(play_,SL_PLAYSTATE_PLAYING)==SL_RESULT_SUCCESS;
  }
  bool Write(const int16_t* data,size_t size){
    std::unique_lock<std::mutex> lock(mutex_);
    if(!ready_.wait_for(lock,std::chrono::seconds(1),[this]{return !active_||queued_<2;})||!active_)return false;
    auto& buffer=buffers_[next_];std::copy(data,data+size,buffer.begin());
    const auto result=(*queue_)->Enqueue(queue_,buffer.data(),static_cast<SLuint32>(size*sizeof(int16_t)));
    if(result!=SL_RESULT_SUCCESS)return false;
    next_=(next_+1)%2;++queued_;return true;
  }
  void Stop(){
    {std::lock_guard<std::mutex> lock(mutex_);active_=false;ready_.notify_all();}
    if(play_)(*play_)->SetPlayState(play_,SL_PLAYSTATE_STOPPED);
    if(queue_)(*queue_)->Clear(queue_);
  }
 private:
  static void Callback(SLAndroidSimpleBufferQueueItf,void* context){
    auto* player=static_cast<Player*>(context);std::lock_guard<std::mutex> lock(player->mutex_);
    if(player->queued_)--player->queued_;player->ready_.notify_one();
  }
  SLObjectItf engine_=nullptr,mix_=nullptr,player_=nullptr;
  SLPlayItf play_=nullptr;SLAndroidSimpleBufferQueueItf queue_=nullptr;
  std::mutex mutex_;std::condition_variable ready_;bool active_=false;
  size_t queued_=0,next_=0;std::array<std::array<int16_t,480>,2> buffers_{};
};
}
extern "C" JNIEXPORT jlong JNICALL Java_com_prs_localist_OpenSlAudioOutput_create(JNIEnv*,jobject,jboolean effects){
  auto player=std::make_unique<Player>();if(!player->Start(effects))return 0;
  return reinterpret_cast<jlong>(player.release());
}
extern "C" JNIEXPORT jboolean JNICALL Java_com_prs_localist_OpenSlAudioOutput_write(JNIEnv* env,jobject,jlong handle,jshortArray pcm){
  if(!handle||!pcm||env->GetArrayLength(pcm)!=480)return JNI_FALSE;
  std::array<int16_t,480> samples{};env->GetShortArrayRegion(pcm,0,480,samples.data());
  return reinterpret_cast<Player*>(handle)->Write(samples.data(),samples.size())?JNI_TRUE:JNI_FALSE;
}
extern "C" JNIEXPORT void JNICALL Java_com_prs_localist_OpenSlAudioOutput_stop(JNIEnv*,jobject,jlong handle){if(handle)reinterpret_cast<Player*>(handle)->Stop();}
extern "C" JNIEXPORT void JNICALL Java_com_prs_localist_OpenSlAudioOutput_release(JNIEnv*,jobject,jlong handle){delete reinterpret_cast<Player*>(handle);}
