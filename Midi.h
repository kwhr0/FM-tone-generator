#include "types.h"

class Midi {
	struct Track {
		enum State {
			INIT, NOTEON2, CONTROL2, PITCH2, META, META2, DUMMY, DUMMYV,
			// following line must be assigned 8 to 15
			NOTEOFF, NOTEON, KEY, CONTROL, PROGRAM, CHANNEL, PITCH, EX,
			TEMPO, TEMPO2, TEMPO3
		};
		Track(Midi &midi, int size);
		~Track() {
			delete[] buf;
			buf = NULL;
		}
		void DeltaTime();
		u8 Process1(u8 data);
		int Process();
		void Note(u8 midi_ch, u8 note, u8 velo);
		void Reset() { // clear except lim, startTime
			ptr = buf;
			v = len = 0;
			time = 0;
			state = state0 = INIT;
			ch = d1 = 0;
			DeltaTime();
		}
		Midi &midi;
		u8 *buf, *ptr, *lim;
		u32 v, len;
		s32 time; // S23.8
		State state, state0;
		float startTime;
		u8 ch, d1;
	};
	friend class Track;
	typedef std::vector<Track *> Tracks;
	enum { N = 16 };
	struct Ch {
		Ch() { Reset(); }
		void Reset() {
			prognum = 0;
			volume = 100;
			pan = 64;
			expression = rpnl = rpnm = 127;
			bend = 0;
			bendsen = 2;
		}
		u8 volume, rpnl, rpnm, pan, expression, prognum;
		s16 bend;
		s8 bendsen;
	};
public:
	Midi(float interval);
	~Midi();
	void Clear();
	int Prepare(const char *path);
	int Process();
	void Reset();
	float GetPosition() const { return timeAll ? time / timeAll : 0.f; }
	void Position(float position);
	void SetSpeed(float _speed) { speed = _speed; }
	float GetTime() const { return time; }
	float GetTotalTime() const { return timeAll; }
	int get2();
	int get4();
private:
	Ch ch[N];
	Tracks tracks;
	FILE *fi;
	u32 timebase;
	u16 delta;
	float time, timeAll, speed, interval;
	bool ready, drive;
};

extern Midi *gMidi;
