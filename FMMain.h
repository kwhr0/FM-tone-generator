#include "types.h"

#define MIDI_UNIT			256

class FMMain {
	static const int BUFN = 0x8000;
public:
	FMMain();
	~FMMain();
	int LoadTone(const char *tonefile);
	void NewChannelManager(int n);
	bool MainLoop();
	void Stop();
	void SetChType(int type);
	static void RequestPosition(float r) { position = r; positionRequest = true; }
	static void Terminate(int) { quit = 1; }
	static void Next(int) { quit = -1; }
#ifdef __APPLE__
	static void Callback(float *buf0, float *buf1, int numSamples);
	static int Generate(float *buf0, float *buf1, int numSamples);
#else
	static void Callback(short *buf0, int numSamples);
	static int Generate(short *buf0, int numSamples);
#endif
private:
	int current, chType;
	static int ncore, bufN, bufRemain, quit;
	static bool positionRequest, bufferActive;
	static float position, amp;
#ifdef __APPLE__
	static float buf[2][BUFN], bufAlt[2][BUFN];
	static pthread_mutex_t mutex;
#elif defined(WIN32)
	static short buf[2 * BUFN], bufAlt[2 * BUFN];
	static HANDLE mutex;
#else
	static short buf[2 * BUFN], bufAlt[2 * BUFN];
	static pthread_mutex_t mutex;
#endif
#ifdef MULTI_THREAD
	static pthread_t *thread;
#endif
};

extern FMMain *gFMMain;
