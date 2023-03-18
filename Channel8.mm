// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

#include "Channel8.h"
#if defined(USE_METAL) || defined(USE_OPENCL)
#include "gp_types.h"
#endif

#if defined(__ALTIVEC__)
#define SYSCTL_KEY	"hw.optional.altivec"
#elif defined(__SSE4_1__)
#define SYSCTL_KEY	"hw.optional.sse4_1"
#elif defined(__ARM_NEON__)
#define SYSCTL_KEY	"hw.optional.neon"
#endif

#define id1(name)	(((0x100 - ratio) * p[0].name + ratio * p[1].name) >> 8)
#define id2(name)	(((0x100 - ratio) * (p[0].name##_l | p[0].name##_u << 8) + ratio * (p[1].name##_l | p[1].name##_u << 8)) >> 8)
#define v2(p)	(((u8 *)(p))[0] | ((u8 *)(p))[1] << 8)

std::vector<const void *> Channel8::toneData;
int Channel8::bank;
bool Channel8::s_modulate = true, Channel8::simd, Channel8::inited;

Channel8::Channel8() {
#if defined(__ARM_NEON__) || defined(__ALTIVEC__) || defined(__SSE4_1__)
	if (!inited) {
		inited = true;
#if TARGET_OS_IPHONE
		simd = true;
#else
		int d;
		size_t len = sizeof(d);
		if (!sysctlbyname(SYSCTL_KEY, &d, &len, NULL, 0) && d) simd = true;
#endif
	}
#endif
	for (int i = 0; i < 8; i++) {
		stay[i] = -1;
		level[i] = Operator8::EG::LEVEL_MIN;
		c_l[i] = Operator8::EG::LEVEL_MIN;
		c_sw[i] = 0;
		c_rate[i] = 0;
		ml[i] = 0x100; // Fixed S23.8
		count[i] = 0;
		delta[i] = 0x10000;
		value[i] = 0;
	}
}

void Channel8::NoteOn(u8 _prog, u8 _note, s16 _bend, u8 _velo, u8 _vol, u8 _exp, u8 _pan, u16 _id, u16 _pr) {
	const void *table = toneData[bank];
	tone = (Tone *)&((u8 *)table)[v2(&((u16 *)table)[_prog])];
	note = _note;
	pan = _pan;
	this->id = _id;
	pr = _pr;
	released = 0;
	if (!tone) return;
	int sN = tone->sn;
	u8 *sc = tone->sc;
	OpParam *p = (OpParam *)((u8 *)tone + 16);
	if (p == NULL || sc == NULL) return;
	int i, ratio = 0;
	if (sN) {
		for (i = 0; i < sN && note >= sc[i]; i++)
			;
		if (i < sN) {
			if (i) {
				p += i - 1;
				ratio = ((note - sc[i - 1]) << 8) / (sc[i] - sc[i - 1]);
			}
		}
		else p += sN - 1;
	}
	if (tone->flags & FLAG_SS) note += 60;
	else note <<= 1;
	u8 co = tone->con;
	opN = tone->on;
	for (i = 0; i < opN; i++) {
		op[i].NoteOn(p, ratio, _velo, _vol, _exp, co >> i & 1);
		op[i].eg.Trans(Operator8::EG::H, level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
		ml[i] = id2(ml);
		count[i] = id1(ph) << (22 - 8);
		delta[i] = op[i].pg.GetDelta(note, _bend);
		value[i] = 0;
		con[i] = co >> i & 1;
		p += sN ? sN : 1;
	}
	perc = (tone->flags & FLAG_PERC) != 0;
	modulate = s_modulate;
}

void Channel8::NoteOff(bool percMask) {
	if (released || (percMask && perc)) return;
	for (int i = 0; i < opN; i++) {
		op[i].eg.Trans(Operator8::EG::R1, level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
	}
	released = 1;
}

bool Channel8::IsActive() {
	for (int i = 0; i < opN; i++)
		if (tone->con & 1 << i && (perc ? level[i] > Operator8::EG::LEVEL_MIN : op[i].eg.phase != Operator8::EG::OFF)) return true;
	return false;
}

void Channel8::Bend(s16 bend) {
	for (int i = 0; i < opN; i++) {
		delta[i] = op[i].pg.GetDelta(note, bend);
	}
}

void Channel8::SetVolExp(u8 vol, u8 exp) {
	for (int i = 0; i < opN; i++) op[i].pg.SetVolExp(vol, exp);
}

#ifdef __ALTIVEC__
#include <altivec.h>
#ifndef ALTIVEC_RAW
struct SInt32x4 {
	SInt32x4() {}
	SInt32x4(int32_t &p) { v = vec_ld(0, &p); }
	SInt32x4(vector int _v) { v = _v; }
	operator vector int() const { return v; }
	SInt32x4 operator%(const SInt32x4 &a) const { return vec_mergel(v, a.v); }
	SInt32x4 operator+(const SInt32x4 &a) const { return vec_add(v, a.v); }
	SInt32x4 operator>>(int n) const { vector int s = (vector int){ n, n, n, n }; return vec_sra(v, s); }
	SInt32x4 operator>(const SInt32x4 &a) const { return vec_cmpgt(v, a.v); }
	SInt32x4 operator&(const SInt32x4 &a) const { return vec_and(v, a.v); }
	SInt32x4 operator^(const SInt32x4 &a) const { return vec_xor(v, a.v); }
	SInt32x4 operator|(const SInt32x4 &a) const { return vec_or(v, a.v); }
	SInt32x4 MulAdd(const SInt32x4 &a, const SInt32x4 &b) const {
		return vec_cts(vec_madd(vec_ctf(a.v, 0), vec_ctf(b.v, 0), vec_ctf(v, 0)), 0);
	}
	SInt32x4 AddS(const SInt32x4 &a) const { return vec_adds(v, a.v); }
	SInt32x4 Select(const SInt32x4 &a, const SInt32x4 &b) const { return vec_sel(a.v, b.v, (vector bool int)v); }
	SInt32x4 Perm(const SInt32x4 &a, const SInt32x4 &b) const { return vec_perm(a.v, b.v, v); }
	SInt32x4 Store(int32_t &p) const { vec_st(v, 0, &p); return *this; }
	void Store1(int32_t &p, int x) const { vec_ste(v, x, &p); }
	static SInt32x4 Dup(int _v) { return (vector int){ _v, _v, _v, _v }; }
	vector int v;
};
struct SInt16x8 {
	SInt16x8(int16_t &p) { v = vec_ld(0, &p); }
	SInt16x8(vector short _v) { v = _v; }
	SInt32x4 operator->*(const SInt16x8 &a) const {
		vector int z = vec_splat_u32(0);
		return vec_sums(vec_msum(v, a.v, z), z);
	}
	vector short v;
};
#define DEF_V()		SInt16x8 v0 = value[0];
#define LINDEX()	((l >> (32 - Operator8::EG::LOGTABLE_LOG)) + cofs)
#define NEXT_L(r)	(l.AddS(r))
#define MODULATE0()	((cmask & c).MulAdd(ml0, p.Perm(oc00->*v0 % oc10->*v0, oc20->*v0 % oc30->*v0)))
#define MODULATE4()	((cmask & c).MulAdd(ml4, p.Perm(oc40->*v0 % oc50->*v0, oc60->*v0 % oc70->*v0)))
#define X()			(q >> 21 - Operator8::PG::LOGSINTABLE_LOG)
#define STORE()		{ s32 tmp[4] _ALIGN; (con0->*v0).Store1(tmp[0], 12); buf[0] += lvol * tmp[3]; buf[1] += rvol * tmp[3]; }
#define VALUE_T SInt32x4
#endif
#endif

#ifdef	__SSE4_1__
#include <smmintrin.h>
struct SInt32x4 {
	SInt32x4() {}
	SInt32x4(int32_t &p) { v = _mm_load_si128((__m128i *)&p); }
	SInt32x4(__m128i _v) { v = _v; }
	operator __m128i() const { return v; }
	SInt32x4 operator->*(const SInt32x4 &a) const { return _mm_hadd_epi32(v, a.v); }
	SInt32x4 operator*(const SInt32x4 &a) const { return _mm_mullo_epi32(v, a.v); }
	SInt32x4 operator+(const SInt32x4 &a) const { return _mm_add_epi32(v, a.v); }
	SInt32x4 operator>>(int n) const { return _mm_srai_epi32(v, n); }
	SInt32x4 operator>(const SInt32x4 &a) const { return _mm_cmpgt_epi32(v, a.v); }
	SInt32x4 operator^(const SInt32x4 &a) const { return _mm_xor_si128(v, a.v); }
	SInt32x4 operator|(const SInt32x4 &a) const { return _mm_or_si128(v, a.v); }
	SInt32x4 Select(const SInt32x4 &a, SInt32x4 &b) const { return _mm_blendv_epi8(a.v, b.v, v); }
	SInt32x4 Clamp(const SInt32x4 &low, const SInt32x4 &high) const {
		return _mm_min_epi32(_mm_max_epi32(v, low), high);
	}
	SInt32x4 Store(int32_t &p) const { _mm_store_si128((__m128i *)&p, v); return *this; }
	SInt32x4 StoreLo(int32_t &p) const { _mm_storel_pi((__m64 *)&p, (__m128)v); return *this; }
	static SInt32x4 Dup(int _v) { return _mm_set1_epi32(_v); }
	__m128i v;
};
struct SInt32x2 {
	SInt32x2(int32_t &p) { v = _mm_set_pi32((&p)[1], (&p)[0]); }
	operator SInt32x4() const { return _mm_movpi64_epi64(v); }
	__m64 v;
};
struct SInt16x8 {
	SInt16x8(int16_t &p) { v = _mm_load_si128((__m128i *)&p); }
	SInt16x8(__m128i _v) { v = _v; }
	SInt32x4 operator%(const SInt16x8 &a) const { return _mm_madd_epi16(v, a.v); }
	__m128i v;
};
#define DEF_V()		SInt16x8 v0 = value[0];
#define LINDEX()	(l >> (21 - Operator8::EG::LOGTABLE_LOG))
#define NEXT_L(r)	((l + (r)).Clamp(clow, chigh))
#define X()			(q >> (21 - Operator8::PG::LOGSINTABLE_LOG))
#define STORE()		{SInt32x4 t = con0 % v0; t = t->*t; (cvol * t->*t + SInt32x2(*buf)).StoreLo(*buf);}
#endif

#ifdef __AVX2__
#include <immintrin.h>
struct SInt32x8 {
	SInt32x8() {}
	SInt32x8(int32_t &p) { v = _mm256_load_si256((__m256i *)&p); }
	SInt32x8(__m256i _v) { v = _v; }
	SInt32x8(const SInt32x4 &a) {
		v = _mm256_insertf128_si256(v, a, 0);
	}
	SInt32x8(const SInt32x4 &a, const SInt32x4 &b) {
		v = _mm256_insertf128_si256(_mm256_insertf128_si256(v, a, 0), b, 1);
	}
	operator __m256i() const { return v; }
	SInt32x8 operator*(const SInt32x8 &a) const { return _mm256_mullo_epi32(v, a.v); }
	SInt32x8 operator+(const SInt32x8 &a) const { return _mm256_add_epi32(v, a.v); }
	SInt32x8 operator>>(int n) const { return _mm256_srai_epi32(v, n); }
	SInt32x8 operator>(const SInt32x8 &a) const { return _mm256_cmpgt_epi32(v, a.v); }
	SInt32x8 operator^(const SInt32x8 &a) const { return _mm256_xor_si256(v, a.v); }
	SInt32x8 operator|(const SInt32x8 &a) const { return _mm256_or_si256(v, a.v); }
	SInt32x8 Select(const SInt32x8 &a, SInt32x8 &b) const { return _mm256_blendv_epi8(a.v, b.v, v); }
	SInt32x8 Clamp(const SInt32x8 &low, const SInt32x8 &high) const {
		return _mm256_min_epi32(_mm256_max_epi32(v, low), high);
	}
	SInt32x8 Store(int32_t &p) const { _mm256_store_si256((__m256i *)&p, v); return *this; }
	static SInt32x8 Dup(int _v) { return _mm256_set1_epi32(_v); }
	__m256i v;
};
#define MODULATE0()	(c + ml0 * (opN <= 4 ? \
	SInt32x8(((oc00 % v0)->*(oc10 % v0))->*((oc20 % v0)->*(oc30 % v0))) :\
	SInt32x8(((oc00 % v0)->*(oc10 % v0))->*((oc20 % v0)->*(oc30 % v0)),\
			((oc40 % v0)->*(oc50 % v0))->*((oc60 % v0)->*(oc70 % v0)))))
#define VALUE_T SInt32x8
#elif defined(__SSE4_1__)
#define MODULATE0()	(c + ml0 * ((oc00 % v0)->*(oc10 % v0))->*((oc20 % v0)->*(oc30 % v0)))
#define MODULATE4()	(c + ml4 * ((oc40 % v0)->*(oc50 % v0))->*((oc60 % v0)->*(oc70 % v0)))
#define VALUE_T SInt32x4
#endif

#ifdef __ARM_NEON__
#include <arm_neon.h>
struct SInt32x4 {
	SInt32x4() {}
	SInt32x4(int32_t &p) { v = vld1q_s32(&p); }
	SInt32x4(int32x4_t _v) { v = _v; }
	operator int32x4_t() const { return v; }
	template <int N> SInt32x4 ShiftRight() const { return vshrq_n_s32(v, N); }
	SInt32x4 &operator=(const SInt32x4 &a) { v = a.v; return *this; }
	SInt32x4 operator+(const SInt32x4 &a) const { return vaddq_s32(v, a.v); }
	SInt32x4 operator>(const SInt32x4 &a) const { return vcgtq_s32(v, a.v); }
	SInt32x4 operator^(const SInt32x4 &a) const { return veorq_s32(v, a.v); }
	SInt32x4 operator|(const SInt32x4 &a) const { return vorrq_s32(v, a.v); }
#ifdef __aarch64__
    SInt32x4 operator->*(const SInt32x4 &a) const { return vpaddq_s32(v, a.v); }
#endif
    SInt32x4 Store(int32_t &p) const { vst1q_s32(&p, v); return *this; }
	SInt32x4 QAdd(const SInt32x4 &a) const { return vqaddq_s32(v, a.v); }
	SInt32x4 MulAdd(const SInt32x4 &a, const SInt32x4 &b) const { return vmlaq_s32(v, a.v, b.v); }
	SInt32x4 Select(const SInt32x4 &a, SInt32x4 &b) const { return vbslq_s32(v, b.v, a.v); }
    int32x2_t Low() const { return vget_low_s32(v); }
	static SInt32x4 Dup(int _v) { return vdupq_n_s32(_v); }
	int32x4_t v;
};
struct SInt32x2 {
	SInt32x2(int32_t &p) { v = vld1_s32(&p); }
	SInt32x2(int32x2_t _v) { v = _v; }
	SInt32x2 MulAdd(const SInt32x2 &a, const SInt32x2 &b) const { return vmla_s32(v, a.v, b.v); }
	SInt32x4 operator%(const SInt32x2 &a) const { return vcombine_s32(v, a.v); }
	void Store(int32_t &p) const { vst1_s32(&p, v); }
	int32x2_t v;
};
struct SInt16x4 {
	SInt16x4() {}
	SInt16x4(int16_t &p) { v = vld1_s16(&p); }
	SInt16x4(int16x4_t _v) { v = _v; }
	operator int16x4_t() const { return v; }
	SInt16x4 operator->*(const SInt16x4 &a) const { return vpadd_s16(v, a.v); }
	SInt16x4 operator*(const SInt16x4 &a) const { return vmul_s16(v, a.v); }
	SInt32x2 operator++(int) const { return vpaddl_s16(v); }
	int16x4_t v;
};
struct SInt16x8 {
    SInt16x8() {}
    SInt16x8(int16_t &p) { v = vld1q_s16(&p); }
    SInt16x8(int16x8_t _v) { v = _v; }
    operator int16x8_t() const { return v; }
#ifdef __aarch64__
    SInt16x8 operator->*(const SInt16x8 &a) const { return vpaddq_s16(v, a.v); }
#endif
    SInt16x8 operator*(const SInt16x8 &a) const { return vmulq_s16(v, a.v); }
    SInt32x4 operator++(int) const { return vpaddlq_s16(v); }
    int16x8_t v;
};
#define LINDEX()	(l.ShiftRight<32 - Operator8::EG::LOGTABLE_LOG>() + cofs)
#define NEXT_L(r)	(l.QAdd(r))
#define X()			(q.ShiftRight<21 - Operator8::PG::LOGSINTABLE_LOG>())
#define VALUE_T SInt32x4
#ifdef __aarch64__
#define DEF_V()		SInt16x8 v0 = value[0];
#define MODULATE0()	(c.MulAdd(ml0, (((oc00 * v0)->*(oc10 * v0))->*((oc20 * v0)->*(oc30 * v0)))++))
#define MODULATE4()	(c.MulAdd(ml4, (((oc40 * v0)->*(oc50 * v0))->*((oc60 * v0)->*(oc70 * v0)))++))
#define STORE()		{SInt32x4 t = (con0 * v0)++; t = t->*t; SInt32x2 t2 = (t->*t).Low(); SInt32x2(*buf).MulAdd(cvol, t2).Store(*buf);}
#else
#define DEF_V()		SInt16x4 v0 = value[0], v4 = value[4];
#define MODULATE0()	(c.MulAdd(ml0,\
	(((oc00 * v0)->*(oc04 * v4))->*((oc10 * v0)->*(oc14 * v4)))++ %\
	(((oc20 * v0)->*(oc24 * v4))->*((oc30 * v0)->*(oc34 * v4)))++))
#define MODULATE4()	(c.MulAdd(ml4,\
	(((oc40 * v0)->*(oc44 * v4))->*((oc50 * v0)->*(oc54 * v4)))++ %\
	(((oc60 * v0)->*(oc64 * v4))->*((oc70 * v0)->*(oc74 * v4)))++))
#define STORE()		(v0 = (con0 * v0)->*(con4 * v4), SInt32x2(*buf).MulAdd(cvol, (v0->*v0)++).Store(*buf))
#endif
#endif

void Channel8::Update(s32 *buf, int numSamples) {
	if (simd) {
#if defined(__ALTIVEC__) && defined(ALTIVEC_RAW)
		vector short oc00 = vec_ld(0, op[0].con);
		vector short oc10 = vec_ld(0, op[1].con);
		vector short oc20 = vec_ld(0, op[2].con);
		vector short oc30 = vec_ld(0, op[3].con);
		vector short oc40 = vec_ld(0, op[4].con);
		vector short oc50 = vec_ld(0, op[5].con);
		vector short oc60 = vec_ld(0, op[6].con);
		vector short oc70 = vec_ld(0, op[7].con);
		vector short con0 = vec_ld(0, con);
		int k0 = Operator8::EG::LOGTABLE_N >> 1;
		vector int cofs = (vector int){ k0, k0, k0, k0 };
		int k1 = 32 - Operator8::EG::LOGTABLE_LOG;
		vector int csft = (vector int){ k1, k1, k1, k1 };
		vector unsigned char p = (vector unsigned char){ 8, 9, 10, 11, 12, 13, 14, 15, 24, 25, 26, 27, 28, 29, 30, 31 };
		vector int cmask = (vector int){ 0x3fffff, 0x3fffff, 0x3fffff, 0x3fffff };
		s32 lvol = 0x7f - pan, rvol = pan;
		vector int ml0 = vec_ld(0, ml), ml4 = vec_ld(16, ml);
		vector int t0, t1, z = vec_splat_u32(0);
		while (--numSamples >= 0) {
			// parallel part
			vector int q, c, l;
			vector short v0 = vec_ld(0, value);
			s32 _ALIGN lindex[8], x[8], cond[8];
			l = vec_ld(0, level);
			vec_st(vec_add(vec_sra(l, csft), cofs), 0, lindex);
			q = vec_adds(l, vec_ld(0, c_rate));
			c = vec_or(vec_xor(vec_cmpgt(q, vec_ld(0, c_l)), vec_ld(0, c_sw)), vec_ld(0, stay));
			vec_st(c, 0, cond);
			vec_st(vec_sel(l, q, (vector bool int)c), 0, level);
			c = vec_ld(0, count);
			if (modulate) {
				t0 = vec_mergel(vec_sums(vec_msum(oc00, v0, z), z), vec_sums(vec_msum(oc10, v0, z), z));
				t1 = vec_mergel(vec_sums(vec_msum(oc20, v0, z), z), vec_sums(vec_msum(oc30, v0, z), z));
				t0 = vec_perm(t0, t1, p);
				t1 = vec_and(cmask, c);
				q = vec_cts(vec_madd(vec_ctf(ml0, 0), vec_ctf(t0, 0), vec_ctf(vec_and(t1, c), 0)), 0);
			}
			else q = c;
			vec_st(vec_sra(q, vec_splat_u32(21 - Operator8::PG::LOGSINTABLE_LOG)), 0, x);
			vec_st(vec_add(c, vec_ld(0, delta)), 0, count);
			if (opN > 4) {
				l = vec_ld(16, level);
				vec_st(vec_add(vec_sra(l, csft), cofs), 16, lindex);
				q = vec_adds(l, vec_ld(16, c_rate));
				c = vec_or(vec_xor(vec_cmpgt(q, vec_ld(16, c_l)), vec_ld(16, c_sw)), vec_ld(16, stay));
				vec_st(c, 16, cond);
				vec_st(vec_sel(l, q, (vector bool int)c), 16, level);
				c = vec_ld(16, count);
				if (modulate) {
					t0 = vec_mergel(vec_sums(vec_msum(oc40, v0, z), z), vec_sums(vec_msum(oc50, v0, z), z));
					t1 = vec_mergel(vec_sums(vec_msum(oc60, v0, z), z), vec_sums(vec_msum(oc70, v0, z), z));
					t0 = vec_perm(t0, t1, p);
					t1 = vec_and(cmask, c);
					q = vec_cts(vec_madd(vec_ctf(ml4, 0), vec_ctf(t0, 0), vec_ctf(vec_and(t1, c), 0)), 0);
				}
				else q = c;
				vec_st(vec_sra(q, vec_splat_u32(21 - Operator8::PG::LOGSINTABLE_LOG)), 16, x);
				vec_st(vec_add(c, vec_ld(16, delta)), 16, count);
			}
			s32 tmp[4] _ALIGN;
			vec_ste(vec_sums(vec_msum(con0, v0, z), z), 12, tmp);
			*buf++ += lvol * tmp[3];
			*buf++ += rvol * tmp[3];
			// sequential part (same as SSE/NEON)
			value[0] = op[0].Update(x[0], lindex[0], tone->flags & FLAG_NZ);
			if (!cond[0]) op[0].eg.Trans(level[0], stay[0], c_sw[0], c_rate[0], c_l[0]);
			if (con[0] && tone->flags & FLAG_FZ) {
				int d = value[0];
				if (d < -512) d = -512;
				else if (d > 511) d = 511;
				value[0] = 6 * d;
			}
			if (modulate)
				for (int i = 1; i < opN; i++) {
					value[i] = op[i].Update(x[i], lindex[i]);
					if (!cond[i]) op[i].eg.Trans(level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
				}
			else
				for (int i = 1; i < opN; i++)
					if (con[i]) {
						value[i] = op[i].Update(x[i], lindex[i]);
						if (!cond[i]) op[i].eg.Trans(level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
					}
		}
#endif
#if defined(__ALTIVEC__) && !defined(ALTIVEC_RAW) || defined(__SSE4_1__) || defined(__ARM_NEON__) && defined(__aarch64__)
		SInt16x8 oc00 = op[0].con[0];
		SInt16x8 oc10 = op[1].con[0];
		SInt16x8 oc20 = op[2].con[0];
		SInt16x8 oc30 = op[3].con[0];
		SInt16x8 oc40 = op[4].con[0];
		SInt16x8 oc50 = op[5].con[0];
		SInt16x8 oc60 = op[6].con[0];
		SInt16x8 oc70 = op[7].con[0];
		SInt16x8 con0 = con[0];
#endif
#if defined(__ALTIVEC__) && !defined(ALTIVEC_RAW)
		SInt32x4 cofs = SInt32x4::Dup(Operator8::EG::LOGTABLE_N >> 1);
		SInt32x4 p = (vector unsigned char){ 8, 9, 10, 11, 12, 13, 14, 15, 24, 25, 26, 27, 28, 29, 30, 31 };
		SInt32x4 cmask = (vector int){ 0x3fffff, 0x3fffff, 0x3fffff, 0x3fffff };
		s32 lvol = 0x7f - pan, rvol = pan;
#elif defined(__SSE4_1__)
		VALUE_T clow = VALUE_T::Dup(0), chigh = VALUE_T::Dup(0x1fffff);
		s32 va[] = { 0x7f - pan, pan, 0, 0 };
		SInt32x4 cvol = va[0];
#elif defined(__ARM_NEON__)
#ifndef __aarch64__
		SInt16x4 oc00 = op[0].con[0], oc04 = op[0].con[4];
		SInt16x4 oc10 = op[1].con[0], oc14 = op[1].con[4];
		SInt16x4 oc20 = op[2].con[0], oc24 = op[2].con[4];
		SInt16x4 oc30 = op[3].con[0], oc34 = op[3].con[4];
		SInt16x4 oc40 = op[4].con[0], oc44 = op[4].con[4];
		SInt16x4 oc50 = op[5].con[0], oc54 = op[5].con[4];
		SInt16x4 oc60 = op[6].con[0], oc64 = op[6].con[4];
		SInt16x4 oc70 = op[7].con[0], oc74 = op[7].con[4];
		SInt16x4 con0 = con[0], con4 = con[4];
#endif
        SInt32x4 cofs = SInt32x4::Dup(Operator8::EG::LOGTABLE_N >> 1);
		s32 va[] = { 0x7f - pan, pan };
		SInt32x2 cvol = va[0];
#endif
#if defined(__ALTIVEC__) && !defined(ALTIVEC_RAW) || defined(__SSE4_1__) || defined(__ARM_NEON__)
#ifdef __AVX2__
		SInt32x8 ml0 = ml[0];
#else
		SInt32x4 ml0 = ml[0], ml4 = ml[4];
#endif
		while (--numSamples >= 0) {
			// parallel part
			VALUE_T q, c, l;
			DEF_V();
			s32 _ALIGN lindex[8], x[8], cond[8];
			l = level[0];
			LINDEX().Store(lindex[0]);
			q = NEXT_L(c_rate[0]);
			c = q > c_l[0] ^ c_sw[0] | stay[0];
			c.Store(cond[0]).Select(l, q).Store(level[0]);
			c = count[0];
			q = modulate ? MODULATE0() : c;
			X().Store(x[0]);
			(c + delta[0]).Store(count[0]);
#ifndef __AVX2__
			if (opN > 4) {
				l = level[4];
				LINDEX().Store(lindex[4]);
				q = NEXT_L(c_rate[4]);
				c = q > c_l[4] ^ c_sw[4] | stay[4];
				c.Store(cond[4]).Select(l, q).Store(level[4]);
				c = count[4];
				q = modulate ? MODULATE4() : c;
				X().Store(x[4]);
				(c + delta[4]).Store(count[4]);
			}
#endif
			STORE();
			buf += 2;
			// sequential part
			value[0] = op[0].Update(x[0], lindex[0], tone->flags & FLAG_NZ);
			if (!cond[0]) op[0].eg.Trans(level[0], stay[0], c_sw[0], c_rate[0], c_l[0]);
			if (con[0] && tone->flags & FLAG_FZ) {
				int d = value[0];
				if (d < -512) d = -512;
				else if (d > 511) d = 511;
				value[0] = 6 * d;
			}
			if (modulate)
				for (int i = 1; i < opN; i++) {
					value[i] = op[i].Update(x[i], lindex[i]);
					if (!cond[i]) op[i].eg.Trans(level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
				}
			else
				for (int i = 1; i < opN; i++)
					if (con[i]) {
						value[i] = op[i].Update(x[i], lindex[i]);
						if (!cond[i]) op[i].eg.Trans(level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
					}
		}
#endif
	}
	else {
		while (--numSamples >= 0) {
			int acc = 0;
			for (int i = 0; i < opN; i++) {
				if (!modulate && !con[i]) continue;
				s16 *c = op[i].con;
				int mod = 0;
				for (int j = opN - 1; j >= 0; j--)
					if (c[j]) mod += value[j];
				s32 t = (op[i].eg.phase != Operator8::EG::H ?
					Operator8::EG::logtable[level[i] >> (21 - Operator8::EG::LOGTABLE_LOG)] :
					Operator8::EG::LOGTABLE_MAX) + op[i].pg.fvol;
				s32 tl = level[i] + c_rate[i];
				if (stay[i] || (c_sw[i] ? 1 : 0) ^ (tl > c_l[i]))
					level[i] = tl < 0 ? 0 : tl > 0x1fffff ? 0x1fffff : tl;
				else op[i].eg.Trans(level[i], stay[i], c_sw[i], c_rate[i], c_l[i]);
				u16 x = 0;
				int noise = !i && tone->flags & FLAG_NZ;
				if (!noise) {
					x = (count[i] + ml[i] * mod) >> (21 - Operator8::PG::LOGSINTABLE_LOG);
					count[i] += delta[i];
				}
				int d = op[i].pg.Update(x, t, noise);
				value[i] = d;
				if (con[i]) {
					if (tone->flags & FLAG_FZ) {
						if (d < -512) d = -512;
						else if (d > 511) d = 511;
						d *= 6;
					}
					acc += d;
				}
			}
			*buf++ += (0x7f - pan) * acc;
			*buf++ += pan * acc;
		}
	}
}

#if defined(USE_METAL) || defined(USE_OPENCL)

u8 Channel8::CopyToGP(GPVars *c, int index) {
	c->fz[index] = tone->flags & FLAG_FZ ? true : false;
	for (int i = 0; i < 8; i++) {
		int num = (index << 3) + i;
		GPOperator *m = &c->op[num];
		m->value = value[i];
		m->phase = (GPOperator::Phase)op[i].eg.phase;
		m->count = count[i];
		m->lv = level[i];
		m->delta = delta[i];
		m->ml = ml[i];
		m->carrier = con[i];
		m->noise = !i && tone->flags & FLAG_NZ;
		op[i].pg.GetFilter0(m->f00, m->f01, m->f02);
		op[i].pg.GetFilter1(m->f10, m->f11, m->f12);
		for (int j = 0; j < 8; j++) m->con[j] = op[i].con[j];
		m->fvol = op[i].pg.fvol;
		for (int j = 0; j < GPOperator::N; j++) {
			m->l[j] = op[i].eg.l[j];
			m->sw[j] = op[i].eg.sw[j];
			m->rate[j] = op[i].eg.rate[j];
		}
	}
	return pan;
}

void Channel8::CopyFromGP(GPVars *c, int index) {
	for (int i = 0; i < 8; i++) {
		int num = (index << 3) + i;
		GPOperator *m = &c->op[num];
		value[i] = m->value;
		op[i].eg.phase = m->phase;
		count[i] = m->count;
		level[i] = m->lv;
		op[i].pg.SetFilter0(m->f00, m->f01, m->f02);
		op[i].pg.SetFilter1(m->f10, m->f11, m->f12);
	}
}

#endif
