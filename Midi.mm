#include "Midi.h"
#include "ChannelManager.h"

#ifdef CLASSIC
#define INTERVAL	5805
#endif

Midi *gMidi;

Midi::Midi(float _interval) : interval(_interval) {
	Clear();
}

Midi::~Midi() {
	if (fi) fclose(fi);
	Clear();
}

void Midi::Clear() { // clear except interval
	for (Tracks::iterator i = tracks.begin(); i != tracks.end(); ++i)
		delete *i;
	tracks.clear();
	fi = NULL;
	timebase = 0;
	Reset();
	timeAll = 0.f;
	ready = drive = false;
	speed = 1.f;
}

void Midi::Reset() {
	time = 0.f;
	delta = timebase / 500000;	// default: 0.5sec BPM=120
	for (Tracks::iterator i = tracks.begin(); i != tracks.end(); ++i) (*i)->Reset();
	for (int j = 0; j < N; j++) ch[j].Reset();
}

int Midi::Process() {
	if (!ready) return -1;
#ifdef CLASSIC
	time += 1e-6f * INTERVAL * speed;
#else
	time += interval;
#endif
	bool f = false;
	for (Tracks::iterator i = tracks.begin(); i != tracks.end(); ++i) {
		int r = (*i)->Process();
		if (r < 0) {
			return r;
		}
		f |= !r;
	}
	return !f;
}

int Midi::get2() {
	u16 v;
	int c = getc(fi);
	if (c < 0) return -1;
	v = c << 8;
	c = getc(fi);
	if (c < 0) return -1;
	return v | c;
}

int Midi::get4() { // cannot read value -1
	u32 v;
	int c = getc(fi);
	if (c < 0) return -1;
	v = c << 24;
	c = getc(fi);
	if (c < 0) return -1;
	v |= c << 16;
	c = getc(fi);
	if (c < 0) return -1;
	v |= c << 8;
	c = getc(fi);
	if (c < 0) return -1;
	return v | c;
}

int Midi::Prepare(const char *path) {
	if (fi) fclose(fi);
	Clear();
#if defined(WIN32) && _MSC_VER >= 1400
	if(fopen_s(&fi, path, "rb") != 0) return 1;
#else
	fi = fopen(path, "rb");
	if (!fi) return 1;
#endif
	if (get4() != 'MThd') return 1;
	if (get4() != 6) return 1;
	int c = get2();
	if (c != 0 && c != 1) return 1;
	int trackN = get2();
	if (trackN < 0) return 1;
	c = get2();
	if (c < 0) return 1;
#ifdef CLASSIC
	timebase = INTERVAL * (c << 8);
#else
	timebase = 1e6f * interval * (c << 8);
#endif
	delta = timebase / 500000;	// default: 0.5sec BPM=120
	while (trackN-- > 0) {
		if (get4() != 'MTrk') return 1;
		int size = get4();
		if (size < 0) return 1;
		Track *t = new Track(*this, size);
		tracks.push_back(t);
	}
	ready = true;
	return 0;
}

void Midi::Position(float position) {
	if (position < 0.f) {
		drive = false;
		while (!Process())
			;
		timeAll = time;
		Reset();
		float t = 1e6f;
		for (Tracks::iterator i = tracks.begin(); i != tracks.end(); ++i)
			if ((*i)->startTime && t > (*i)->startTime) t = (*i)->startTime;
		drive = true;
		// position 1 second before first note on
		while (time < t - 1.f && !Process())
			;
	}
	else {
		int target = timeAll * position;
		if (time > target) Reset();
		drive = false;
		while (time < target && !Process())
			;
		drive = true;
	}
}

Midi::Track::Track(Midi &_midi, int size) : midi(_midi), state(INIT), state0(INIT), startTime(0.f), time(0), v(0), len(0), ch(0), d1(0) {
	buf = ptr = new u8[size];
	lim = buf + size;
	fread(buf, size, 1, midi.fi);
	DeltaTime();
}

void Midi::Track::DeltaTime() {
	s32 r = 0;
	u8 c = 0x80;
	while (ptr < lim && c & 0x80) {
		c = *ptr++;
		r = r << 7 | (c & 0x7f);
	}
	time -= r << 8;
}

void Midi::Track::Note(u8 midi_ch, u8 note, u8 velo) {
	if (!midi.drive) return;
	u16 id = (u16)note << 8 | midi_ch;
	if (velo) {
		Midi::Ch *p = &midi.ch[midi_ch];
		u8 prognum = p->prognum;
		gMan->KeyOn(prognum, note, velo, p->volume, p->expression, 
			p->pan, (s32)p->bendsen * p->bend >> 6, id);
	}
	else gMan->KeyOff(id);
}

u8 Midi::Track::Process1(u8 data) {
	Midi::Ch *p = &midi.ch[ch];
	if (state == INIT && !(data & 0x80)) state = state0;
	switch (state) {
		case INIT:
		ch = data & 0xf;
		len = 0;
		if (data >= 0x80 && data <= 0xf0) state = state0 = State(data >> 4);
		else if (data == 0xff) state = state0 = META;
		break;
		case NOTEOFF:
		Note(ch, data, 0);
		state = DUMMY;
		break;
		case NOTEON:
		d1 = data;
		state = NOTEON2;
		break;
		case NOTEON2:
		Note(ch, d1, data);
		if (!startTime) startTime = midi.time;
		state = INIT;
		break;
		case CONTROL:
		d1 = data;
		state = CONTROL2;
		break;
		case CONTROL2:
		switch (d1) {
			case 7:
			p->volume = data;
			gMan->SetVolExp(ch, p->volume, p->expression);
			break;
			case 10:
			p->pan = data;
			gMan->SetPan(ch, p->pan);
			break;
			case 11:
			p->expression = data;
			gMan->SetVolExp(ch, p->volume, p->expression);
			break;
			case 98: case 99:
			p->rpnl = p->rpnm = 0x7f;
			break;
			case 100:
			p->rpnl = data;
			break;
			case 101:
			p->rpnm = data;
			break;
			case 6:
			if (!p->rpnl && !p->rpnm) {
				p->bendsen = data & 0x1f;
				p->rpnl = p->rpnm = 0x7f;
			}
			break;
		}
		state = INIT;
		break;
		case PROGRAM:
		p->prognum = data;
		state = INIT;
		break;
		case KEY:
		state = DUMMY;
		break;
		case PITCH:
		d1 = data;
		state = PITCH2;
		break;
		case PITCH2:
		p->bend = ((s16)data - 0x40) << 7 | d1;
		gMan->Bend(ch, (s32)p->bendsen * p->bend >> 6);
		state = INIT;
		break;
		case EX:
		len = len << 7 | (data & 0x7f);
		if (!(data & 0x80)) state = len ? DUMMYV : INIT;
		break;
		case META:
		d1 = data;
		state = META2;
		break;
		case META2:
		len = len << 7 | (data & 0x7f);
		if (!(data & 0x80)) state = d1 == 0x51 ? TEMPO : len ? DUMMYV : INIT;
		break;
		case TEMPO:
		v = (u32)data << 16;
		state = TEMPO2;
		break;
		case TEMPO2:
		v |= (u16)data << 8;
		state = TEMPO3;
		break;
		case TEMPO3:
		v |= data;
		midi.delta = midi.timebase / v;
		state = INIT;
		break;
		case DUMMYV:
		if (!--len) state = INIT;
		break;
		case CHANNEL:
		default:
		state = INIT;
		break;
	}
	return state != INIT;
}

int Midi::Track::Process() {
	if (!gMan) return -1;
	while (time >= 0) {
		while (ptr < lim && Process1(*ptr++))
			;
		if (ptr >= lim) return 1;
		DeltaTime();
		if (ptr >= lim) return 1;
	}
	time += midi.speed * midi.delta;
	return 0;
}
