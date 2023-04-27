#include "FMMain.h"
#include "Midi.h"
#include "Channel8.h"
#include "ChannelManager.h"

#define CHECK_PEAK		0
#define CHECK_BUFFER	0

#define v2(p)		(((u8 *)(p))[0] | ((u8 *)(p))[1] << 8)

FMMain *gFMMain;

#ifdef __APPLE__
#define ATT			3e-7f
float FMMain::buf[2][FMMain::BUFN], FMMain::bufAlt[2][FMMain::BUFN];
#else
#define ATT			7
short FMMain::buf[2 * FMMain::BUFN], FMMain::bufAlt[2 * FMMain::BUFN];
#endif

#ifdef WIN32
#define LOCK()		(WaitForSingleObject(mutex, INFINITE))
#define UNLOCK()	(ReleaseMutex(mutex))
HANDLE FMMain::mutex;
#else
#define LOCK()		(pthread_mutex_lock(&mutex))
#define UNLOCK()	(pthread_mutex_unlock(&mutex))
pthread_mutex_t FMMain::mutex;
#endif

int FMMain::ncore, FMMain::bufN, FMMain::bufRemain, FMMain::quit;
bool FMMain::positionRequest, FMMain::bufferActive;
float FMMain::position, FMMain::amp;
#if defined(MULTI_THREAD) && defined(__linux)
pthread_t *FMMain::thread;
#endif

FMMain::FMMain() : chType(0) {
	Operator8::MakeTable();
#ifdef __APPLE__
	size_t len = sizeof(ncore);
	int selection[] = { CTL_HW, HW_NCPU };
	if (sysctl(selection, 2, &ncore, &len, NULL, 0)) ncore = 1;
#elif defined(WIN32)
	ncore = 1;
#else
	ncore = sysconf(_SC_NPROCESSORS_CONF);
#endif
#ifdef WIN32
	mutex = CreateMutex(0, FALSE, 0);
#else
	pthread_mutex_init(&mutex, NULL);
#endif
#if defined(MULTI_THREAD) && defined(__linux)
	thread = new pthread_t[ncore];
#endif
}

FMMain::~FMMain() {
#ifdef WIN32
	CloseHandle(mutex);
#else
	pthread_mutex_destroy(&mutex);
#endif
#if defined(MULTI_THREAD) && defined(__linux)
	delete[] thread;
#endif
}

int FMMain::LoadTone(const char *tonefile) {
	FILE *fi;
#if defined(WIN32) && _MSC_VER >= 1400
	if (fopen_s(&fi, tonefile, "rb") != 0) return 1;
#else
	fi = fopen(tonefile, "rb");
	if (!fi) return 1;
#endif
	fseek(fi, 0, SEEK_END);
	size_t len = ftell(fi);
	rewind(fi);
	u8 *buf = new u8[len], *p = buf + 4;
	fread(buf, len, 1, fi);
	fclose(fi);
	Channel8::AppendToneData(&p[v2(&p[0])]);
	ChannelManager::AppendDrumData((Drum *)&p[v2(&p[2])]);
	return 0;
}

void FMMain::NewChannelManager(int n) {
	if (!gMan) {
		gMan = new ChannelManager(n);
		SetChType(chType);
	}
}

void FMMain::SetChType(int type) {
	chType = type;
}

bool FMMain::MainLoop() {
	signal(SIGINT, Terminate);
#ifndef WIN32
	signal(SIGTSTP, Next);
#endif
	bufferActive = false;
	bufRemain = -1;
	bufN = quit = 0;
	amp = 1.f;
	gMan->Clear();
	do {
		int n = (BUFN - bufN) / MIDI_UNIT;
		if (n > 0) {
			n *= MIDI_UNIT;
#ifdef __APPLE__
			int r = Generate(bufAlt[0], bufAlt[1], n);
#else
			int r = Generate(bufAlt, n);
#endif
			if (r >= 0) {
				LOCK();
#ifdef __APPLE__
				memmove(&buf[0][bufN], bufAlt[0], sizeof(float) * n);
				memmove(&buf[1][bufN], bufAlt[1], sizeof(float) * n);
#else
				memmove(&buf[2 * bufN], bufAlt, sizeof(short) * 2 * n);
#endif
				bufN += n;
				UNLOCK();
				bufferActive = true;
			}
			if (r > 0) {
				if (bufRemain < 0) bufRemain = BUFN;
				else if (!bufRemain) return quit > 0;
			}
		}
		else {
#ifdef WIN32
			Sleep(10);
#else
			usleep(10000);
#endif
		}
	} while (quit >= 0);
	return false;
}

#if defined(MULTI_THREAD) && !defined(__APPLE__)
static void *update1(void *ptr) {
	while (!gMan->Update1((s32 *)ptr, MIDI_UNIT))
		;
	return NULL;
}
#endif

#ifdef __APPLE__
int FMMain::Generate(float *buf0, float *buf1, int numSamples) { // OS X
#else
int FMMain::Generate(short *buf0, int numSamples) { // others
#endif
	s32 **buf = new s32 *[ncore], **src = new s32 *[ncore];
	int i;
	for (i = 0; i < ncore; i++) {
		buf[i] = new s32[2 * numSamples];
		memset(buf[i], 0, sizeof(s32) * 2 * numSamples);
	}
	int r = 0;
	for (int ofs = 0; ofs < numSamples; ofs += MIDI_UNIT) {
		if (gMidi) {
			if (positionRequest) {
				positionRequest = false;
				gMan->KeyOffAll();
				gMidi->Position(position);
			}
			else r = quit ? 1 : gMidi->Process();
		}
		else r = -1;
#ifdef MULTI_THREAD
		if (ncore > 1) {
			gMan->StartEnum();
#ifdef __APPLE__
			dispatch_group_t g = dispatch_group_create();
			for  (i = 0; i < ncore; i++) {
				s32 *p = buf[i];
				dispatch_group_async(g, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					while (!gMan->Update1(&p[ofs << 1], MIDI_UNIT))
						;
				});
			}
			dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
			dispatch_release(g);
#else
			for (i = 0; i < ncore; i++) 
				if (pthread_create(&thread[i], NULL, update1, &buf[i][ofs << 1])) {
					return -1;
				}
			for (i = 0; i < ncore; i++) 
				pthread_join(thread[i], NULL);
#endif
		}
		else gMan->Update(&buf[0][ofs << 1], MIDI_UNIT);
#else
		gMan->Update(&buf[0][ofs << 1], MIDI_UNIT);
#endif
		gMan->Poll();
	}
#if CHECK_PEAK
	static int peak = -20;
	float log2 = logf(2.f);
#endif
	for (i = 0; i < ncore; i++) src[i] = buf[i];
	for (i = numSamples; i; i--) {
#ifdef __APPLE__
#ifdef MULTI_THREAD
		s32 d0 = 0, d1 = 0;
		for (int j = ncore - 1; j >= 0; j--) {
			d0 += *src[j]++;
			d1 += *src[j]++;
		}	
		*buf0++ = ATT * d0;
		*buf1++ = ATT * d1;
#else
		*buf0++ = ATT * *src[0]++;
		*buf1++ = ATT * *src[0]++;
#endif
#else
#ifdef MULTI_THREAD
		s32 d0 = 0, d1 = 0;
		for (int j = ncore - 1; j >= 0; j--) {
			d0 += *src[j]++;
			d1 += *src[j]++;
		}
		d0 >>= ATT;
		if (d0 < -32768) d0 = -32768;
		else if (d0 > 32767) d0 = 32767;
		d1 >>= ATT;
		*buf0++ = d0;
		if (d1 < -32768) d1 = -32768;
		else if (d1 > 32767) d1 = 32767;
		*buf0++ = d1;

#else
		s32 d0 = *src[0]++ >> ATT;
		if (d0 < -32768) d0 = -32768;
		else if (d0 > 32767) d0 = 32767;
		*buf0++ = d0;
		d0 = *src[0]++ >> ATT;
		if (d0 < -32768) d0 = -32768;
		else if (d0 > 32767) d0 = 32767;
		*buf0++ = d0;
#endif
#endif
#if CHECK_PEAK
#ifdef __APPLE__
		int db = int(6.f * logf(fabsf(buf0[-1])) / log2);
#else
		int db = int(6.f * logf(fabsf(d0 / 32768.f)) / log2);
#endif
		if (peak < db) {
			peak = db;
			printf("peak=%+ddB%s\n", peak, peak >= 0 ? " (saturated)" : "");
		}
#endif
	}
	delete[] src;
	for (i = 0; i < ncore; i++) delete[] buf[i];
	delete[] buf;
	return r;
}

#ifdef __APPLE__
void FMMain::Callback(float *buf0, float *buf1, int numSamples) {
#else
void FMMain::Callback(short *buf0, int numSamples) {
#endif
	if (bufferActive && numSamples <= bufN) {
		LOCK();
#ifdef __APPLE__
		if (quit) {
			for (int i = 0; i < numSamples; i++) {
				buf0[i] = amp * buf[0][i];
				buf1[i] = amp * buf[1][i];
			}
			amp *= .8f;
		}
		else {
			memmove(buf0, buf[0], sizeof(float) * numSamples);
			memmove(buf1, buf[1], sizeof(float) * numSamples);
		}
		memmove(buf[0], &buf[0][numSamples], sizeof(float) * (BUFN - numSamples));
		memmove(buf[1], &buf[1][numSamples], sizeof(float) * (BUFN - numSamples));
#else
		if (quit) {
			for (int i = 0; i < 2 * numSamples; i++) 
				buf0[i] = amp * buf[i];
			amp *= .8f;
		}
		else memmove(buf0, buf, sizeof(short) * 2 * numSamples);
		memmove(buf, &buf[2 * numSamples], sizeof(short) * 2 * (BUFN - numSamples));
#endif
		bufN -= numSamples;
		UNLOCK();
		if (bufRemain > 0 && (bufRemain -= numSamples) < 0) bufRemain = 0;
#if CHECK_BUFFER
		static int cnt, bufNMin = BUFN;
		if (bufNMin > bufN) bufNMin = bufN, cnt = 100;
		else if (!--cnt) printf("bufmin=%.f%%%s\n", 100. * bufNMin / BUFN, bufNMin ? "" : " (underflow)");
#endif
	}
	else {
#ifdef __APPLE__
		memset(buf0, 0, sizeof(float) * numSamples);
		memset(buf1, 0, sizeof(float) * numSamples);
#else
		memset(buf0, 0, sizeof(short) * 2 * numSamples);
#endif
	}
}
