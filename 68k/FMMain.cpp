#include "ChannelManager.h"
#include "Midi.h"

#define BUF_UNIT_LOG	12
#define BUF_UNIT		(1 << BUF_UNIT_LOG)
#define CH				2			// 1...mono 2...stereo
#define BUF_SIZE		(BUF_UNIT * CH)
#define RING_N			8

void fatal(Str255 msg);
int doEvent(EventRecord *e);

int gSampleRate;

template <class T, int N> class RingBuffer {
public:
	RingBuffer() : rindex(0), windex(0) {}
	float GetRatio() const { return float(windex >= rindex ? windex - rindex : windex - rindex + N) / (N - 1); }
	bool IsEmpty() const { return rindex == windex; }
	bool IsFull() const { return (windex + 1 >= N ? 0 : windex + 1) == rindex; }
	T &Read() { int i = rindex; rindex = i + 1 >= N ? 0 : i + 1; return buffer[i]; }
	T &Write() { return buffer[windex]; }
	T &Glance(int count) {
		int last, i = rindex;
		do {
			last = i;
			if (++i >= N) i = 0;
		} while (--count >= 0 && i != windex);
		return buffer[last];
	}
	void Commit() { if (++windex >= N) windex = 0; }
	void Reset() { rindex = windex = 0; }
private:
	T buffer[N];
	int rindex, windex;
};

struct Buffer {
	Buffer() { d = NewPtrClear(BUF_SIZE); ended = false; }
	~Buffer() { DisposePtr(d); }
	char *d;
	bool ended;
};

typedef RingBuffer<Buffer, RING_N> SndBuf;

static SndBuf sSndBuf;
static bool sStarted;

struct SndDblBuf : SndDoubleBufferHeader {
	SndDblBuf();
	~SndDblBuf();
	bool IsBusy();
	pascal static void Callback(SndChannelPtr, SndDoubleBufferPtr doubleBuffer);
	static SndChannelPtr chan;
};

SndChannelPtr SndDblBuf::chan;

SndDblBuf::SndDblBuf() {
	static long r[] = { 0x15bba2e8, 0x2b7745d1, 0x56ee8ba3, 0xac440000 };
	if (SndNewChannel(&chan, sampledSynth, CH == 1 ? initMono : initStereo, 0)) 
		fatal("\pSndNewChannel failed.");
	dbhNumChannels = CH;
	dbhSampleSize = 8;
	dbhCompressionID = 0;
	dbhPacketSize = 0;
	dbhSampleRate = r[gSampleRate];
#ifdef __POWERPC__
	dbhDoubleBack = NewSndDoubleBackProc(&Callback);
#else
	dbhDoubleBack = &Callback;
#endif
	for (int i = 0; i < 2; i++) {
		SndDoubleBufferPtr doubleBuffer = (SndDoubleBufferPtr)NewPtrClear(
			sizeof(SndDoubleBuffer) + BUF_SIZE);
		doubleBuffer->dbUserInfo[0] = (long)&sSndBuf;
		doubleBuffer->dbUserInfo[1] = (long)&sStarted;
		Callback(chan, doubleBuffer);
		dbhBufferPtr[i] = doubleBuffer;
	}
	SndPlayDoubleBuffer(chan, this);
}

SndDblBuf::~SndDblBuf() {
	SndDisposeChannel(chan, true);
	DisposePtr((Ptr)dbhBufferPtr[0]);
	DisposePtr((Ptr)dbhBufferPtr[1]);
}

bool SndDblBuf::IsBusy() {
	SCStatus status;
	SndChannelStatus(chan, sizeof(status), &status);
	return status.scChannelBusy;
}

pascal void SndDblBuf::Callback(SndChannelPtr, SndDoubleBufferPtr doubleBuffer) {
	SndBuf *sndBuf = (SndBuf *)doubleBuffer->dbUserInfo[0];
	bool started = *(bool *)doubleBuffer->dbUserInfo[1];
	if (started && !sndBuf->IsEmpty()) {
		Buffer &b = sndBuf->Read();
		BlockMove(b.d, doubleBuffer->dbSoundData, BUF_SIZE);
		if (b.ended) doubleBuffer->dbFlags |= dbLastBuffer;
	}
	else {
		// can't use memset() here.
		char *p = (char *)doubleBuffer->dbSoundData;
		for (int i = 0; i < BUF_SIZE; i++) *p++ = 0x80;
	}
	doubleBuffer->dbNumFrames = BUF_UNIT;
	doubleBuffer->dbFlags |= dbBufferReady;
}

void FMMain(int att) {
	SndDblBuf snd;
	int quit = 0;
	do {
		if (!sSndBuf.IsFull()) {
			int f = 0;
			int i, s = BUF_UNIT_LOG - 5 - gSampleRate;
			s32 *tmp = (s32 *)NewPtrClear(sizeof(s32) * 2 * BUF_UNIT); // always stereo
			for (i = 0; i < 1 << s; i++) {
				f |= gMidi->Process();
				gMan->Update(&tmp[i * 2 * BUF_UNIT >> s], BUF_UNIT >> s); // always stereo
			}
			Buffer &b = sSndBuf.Write();
			b.ended = f;
			s32 *src = tmp;
			u8 *dst = (u8 *)b.d;
			for (i = 0; i < BUF_SIZE; i++) {
#if CH == 1
				s16 d = 0x80 + (src[0] + src[1] >> att + 1);
				src += 2;
#else
				s16 d = 0x80 + (*src++ >> att);
#endif
				if (d < 0) d = 0;
				else if (d > 255) d = 255;
				*dst++ = d;
			}
			DisposePtr((Ptr)tmp);
			sSndBuf.Commit();
			gMan->Poll();
		}
		else sStarted = 1;
		EventRecord e = { 0 };
		if (WaitNextEvent(everyEvent, &e, sSndBuf.IsFull() ? 1 : 0, nil)) 
			quit = doEvent(&e);
	} while (!quit && snd.IsBusy());
}
