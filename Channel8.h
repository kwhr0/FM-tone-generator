// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

#include "Operator8.h"

struct Tone {
	u8 flags, con, on, pad0;
	u8 amd, pmd, spd, dly, sn;
	u8 sc[1];
};

class GPVars;

class Channel8 {
	enum { FLAG_FZ = 0x40, FLAG_NZ = 0x20, FLAG_SS = 0x10, FLAG_PERC = 8 };
public:
#ifdef __AVX2__
	void *operator new(std::size_t size) { return _mm_malloc(size, 32); }
	void operator delete(void *p) { _mm_free(p); }
#endif
	Channel8();
	void NoteOn(u8 prog, u8 note, s16 bend, u8 velo, u8 vol, u8 exp, u8 pan, u16 id, u16 pr);
	void NoteOff(bool percMask);
	void SetNote(u8 note, s16 bend);
	void Bend(s16 bend);
	void SetVolExp(u8 vol, u8 exp);
	void Update(s32 *buf, int numSamples);
	bool IsActive();
	u8 CopyToGP(GPVars *c, int index);
	void CopyFromGP(GPVars *c, int index);
	void SetPan(u8 _pan) { pan = _pan; }
	int getId() const { return id; }
	int getPr() const { return pr; }
	bool isReleased() const { return released; }
	static void SetModulate(bool f) { s_modulate = f; }
	static void AppendToneData(const void *t) { toneData.push_back(t); }
	static void SetBank(u8 b) { if (b < toneData.size()) bank = b; }
protected:
	Operator8 op[8];
	s32 level[8]; // NEON/ALTIVEC: -0x80000000 - 0x7fffffff  SSE:21bit
	s32 c_l[8];
	s32 c_rate[8];
	s32 stay[8];
	s32 c_sw[8];
	s32 count[8];
	s32 delta[8];
	s32 ml[8];
	s16 value[8];
	s16 con[8];
	Tone *tone;
	Channel8 *next;
	u16 id, pr;
	u8 opN, note, pan, modulate, released, perc;
	static std::vector<const void *> toneData;
	static int bank;
	static bool s_modulate, simd, inited;
};
