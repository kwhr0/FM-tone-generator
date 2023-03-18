#include "ChannelManager.h"
#include "Channel8.h"
#if defined(USE_METAL)
#include "gp_types.h"
#include "MetalManager.h"
#elif defined(USE_OPENCL)
#include "gp_types.h"
#include "CLManager.h"
#endif

#define CHECK_NOTEMAX		0

struct Drum {
	u8 tn, sc, pan, alt;
};

ChannelManager *gMan;

std::vector<Drum *> ChannelManager::drumData;
int ChannelManager::drumBank;

ChannelManager::ChannelManager(int n) : chN(n), cntA(0), cntR(0), cntTotal(0) {
#ifdef MULTI_THREAD
	pthread_mutex_init(&mutex, NULL);
#endif
#if defined(USE_METAL)
	gpm = new MetalManager(n);
#elif defined(USE_OPENCL)
	gpm = new CLManager;
#endif
}

ChannelManager::~ChannelManager() {
	Clear();
#ifdef MULTI_THREAD
	pthread_mutex_destroy(&mutex);
#endif
}

void ChannelManager::Clear() {
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i) delete *i;
	active.clear();
}

Channel8 *ChannelManager::KeyOn(u8 &prog, u8 &note, u8 velo, u8 vol, u8 exp, u8 pan, s16 bend, u16 id) {
	if ((id & 0xff) == 10 - 1) {
		Drum &d = drumData[drumBank][note];
		if (!d.tn) return NULL;
		prog = d.tn;
		note = d.sc;
		pan = d.pan;
	}
	u16 pr = velo * vol * exp >> 5;
	ChannelList::iterator i;
	for (i = active.begin(); i != active.end() && (*i)->getId() != id; ++i)
		;
	if (i != active.end()) (*i)->NoteOff(true);
	int cnt = (int)active.size();
#if CHECK_NOTEMAX
	static int noteMax;
	if (noteMax < cnt) {
		noteMax = cnt;
		printf("noteMax=%d%s\n", noteMax, noteMax < chN ? "" : "(limit)");
	}
#endif
	Channel8 *t;
	if (cnt < chN) t = new Channel8;
	else {
		ChannelList::reverse_iterator ri;
		for (ri = active.rbegin(); ri != active.rend() && !(*ri)->isReleased(); ++ri)
			;
		if (ri != active.rend()) {
			i = (++ri).base();
			t = *i;
			active.erase(i);
			cntR++;
		}
		else if (cnt) {
			t = active.back();
			if (pr < t->getPr()) return NULL;
			active.pop_back();
			cntA++;
		}
		else return NULL;
	}
	cntTotal++;
	for (i = active.begin(); i != active.end() && (*i)->getPr() > pr; ++i)
		;
	active.insert(i, t);
	t->NoteOn(prog, note, bend, velo, vol, exp, pan, id, pr);
	return t;
}

void ChannelManager::KeyOff(u16 id) {
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		if ((*i)->getId() == id) (*i)->NoteOff(true);
}

void ChannelManager::KeyOffAll() {
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		(*i)->NoteOff(false);
}

void ChannelManager::SetPan(u8 id_low, u8 pan) {
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		if (((*i)->getId() & 0xff) == id_low)
			(*i)->SetPan(pan);
}

void ChannelManager::SetVolExp(u8 id_low, u8 vol, u8 exp) {
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		if (((*i)->getId() & 0xff) == id_low)
			(*i)->SetVolExp(vol, exp);
}

void ChannelManager::Bend(u8 id_low, s16 bend) {
	bend <<= 1;
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		if (((*i)->getId() & 0xff) == id_low)
			(*i)->Bend(bend);
}

#ifdef MULTI_THREAD
bool ChannelManager::Update1(s32 *buf, int numSamples) {
	Channel8 *c = NULL;
	pthread_mutex_lock(&mutex);
	bool f = sharedI == active.end();
	if (!f) c = *sharedI++;
	pthread_mutex_unlock(&mutex);
	if (c) c->Update(buf, numSamples);
	return f;
}
#endif

void ChannelManager::Update(s32 *buf, int numSamples) {
#if defined(USE_METAL) || defined(USE_OPENCL)
	GPVars *vars = new GPVars;
	vars->numSamples = numSamples;
	vars->psg = Operator8::GetWave();
	vars->r = Operator8::GetRand();
	u8 *panl = new u8[GP_CH_N];
	u8 *panr = new u8[GP_CH_N];
	int index = 0;
	for (ChannelList::iterator i = active.begin(); i != active.end() && index < GP_CH_N; ++i) {
		u8 t = (*i)->CopyToGP(vars, index);
		panl[index] = 127 - t;
		panr[index] = t;
		index++;
	}
	gpm->Run(vars, index, ^(int32_t *sp) {
		s32 *dp = buf;
		for (int i = 0; i < numSamples; i++) {
			int32_t l = 0, r = 0;
			for (int j = 0; j < index; j++) {
				int16_t v = sp[j];
				l += panl[j] * v;
				r += panr[j] * v;
			}
			*dp++ += l;
			*dp++ += r;
			sp += GP_CH_N;
		}
	});
	delete[] panl;
	delete[] panr;
	index = 0;
	for (ChannelList::iterator i = active.begin(); i != active.end() && index < GP_CH_N; ++i)
		(*i)->CopyFromGP(vars, index++);
	Operator8::SetRand(vars->r);
	delete vars;
#else
	for (ChannelList::iterator i = active.begin(); i != active.end(); ++i)
		(*i)->Update(buf, numSamples);
#endif
}

void ChannelManager::Poll() {
	int cnt = 0;
	for (ChannelList::iterator i = active.begin(); i != active.end();)
		if (cnt++ < chN && (*i)->IsActive()) ++i;
		else {
			delete *i;
			i = active.erase(i);
		}
}
