// android/app/src/main/cpp/native-lib.cpp
//
// 📱 جسر JNI صغير يشغّل Node.js (libnode.so من nodejs-mobile) داخل عملية الخدمة ":wanode".
//   • node::Start يُستدعى مرة واحدة في عمر العملية (قيد في Node نفسه): للإعادة تُقتل العملية
//     وتُشغَّل من جديد (WaNodeService.kt).
//   • مخرجات Node (stdout/stderr) تُحوَّل إلى logcat بوسم «WaNode» للتشخيص.

#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "node.h"

namespace {

const char *kTag = "WaNode";
int g_pipe[2] = {-1, -1};
pthread_t g_reader;

void *pipe_reader(void *) {
  char buf[2048];
  ssize_t n;
  std::string line;
  while ((n = read(g_pipe[0], buf, sizeof(buf) - 1)) > 0) {
    line.append(buf, static_cast<size_t>(n));
    size_t pos;
    while ((pos = line.find('\n')) != std::string::npos) {
      __android_log_write(ANDROID_LOG_INFO, kTag, line.substr(0, pos).c_str());
      line.erase(0, pos + 1);
    }
  }
  if (!line.empty()) __android_log_write(ANDROID_LOG_INFO, kTag, line.c_str());
  return nullptr;
}

void redirect_output() {
  setvbuf(stdout, nullptr, _IOLBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  if (pipe(g_pipe) != 0) return;
  dup2(g_pipe[1], STDOUT_FILENO);
  dup2(g_pipe[1], STDERR_FILENO);
  if (pthread_create(&g_reader, nullptr, pipe_reader, nullptr) == 0) pthread_detach(g_reader);
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_example_debt_1book_WaNodeNative_startNodeWithArguments(JNIEnv *env, jclass, jobjectArray arguments) {
  const jsize count = env->GetArrayLength(arguments);
  if (count <= 0) return -1;

  // Node يتوقع argv متصلة في الذاكرة (تعيد libuv استعمالها لعنوان العملية)
  std::vector<std::string> args;
  args.reserve(static_cast<size_t>(count));
  size_t total = 0;
  for (jsize i = 0; i < count; i++) {
    auto js = static_cast<jstring>(env->GetObjectArrayElement(arguments, i));
    const char *c = env->GetStringUTFChars(js, nullptr);
    args.emplace_back(c ? c : "");
    if (c) env->ReleaseStringUTFChars(js, c);
    env->DeleteLocalRef(js);
    total += args.back().size() + 1;
  }
  char *buffer = static_cast<char *>(calloc(total, 1));
  if (buffer == nullptr) return -1;
  std::vector<char *> argv(static_cast<size_t>(count) + 1, nullptr);
  char *pos = buffer;
  for (jsize i = 0; i < count; i++) {
    const std::string &a = args[static_cast<size_t>(i)];
    memcpy(pos, a.c_str(), a.size() + 1);
    argv[static_cast<size_t>(i)] = pos;
    pos += a.size() + 1;
  }

  redirect_output();
  // يعود فقط عند خروج Node (لا يُحرَّر buffer: Node قد يحتفظ بمؤشرات إليه حتى نهاية العملية)
  return static_cast<jint>(node::Start(static_cast<int>(count), argv.data()));
}
