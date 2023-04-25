// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

#include "types.h"

#define FS			44100

#if defined(__ARM_NEON__) && !defined(USE_METAL) && !defined(USE_OPENCL) || defined(__ALTIVEC__)
#define SHIFTED_LEVEL
#endif

#ifdef __AVX2__
#define _ALIGN	__attribute__((aligned(32)))
#elif defined(__ARM_NEON__) || defined(__ALTIVEC__) || defined(__SSE4_1__)
#define _ALIGN	__attribute__((aligned(16)))
#else
#define _ALIGN
#endif

struct OpParam {
	u8 mul_l, mul_u, ml_l, ml_u;			// +0
	u8 con, vs, ph; s8 det;					// +4
	u8 at1, at2, dt1, dt2, st, rt1, rt2, ht;// +8
	u8 al, tl, dl, sl, rl, byteCountAdjust;	// +16
};

class Operator8 {
	friend class Channel8;
	class EG {
		friend class Operator8;
		friend class Channel8;
		enum Phase {
			OFF, R2, R1, S, D2, D1, A2, A1, H, N
			/*   -   -   rl  -  sl  dl  tl  al  ht */
		};
		enum { LOGTABLE_LOG = 10, LOGTABLE_N = 1 << LOGTABLE_LOG };
		enum { RATETABLE_N = 256 };
#ifdef SHIFTED_LEVEL
		static const s32 LEVEL_MIN = 0x80000000;
		static const s32 LEVEL_MAX = 0x7ffffffe;
#else
		static const s32 LEVEL_MIN = 0;
		static const s32 LEVEL_MAX = 0x1ffffe;
#endif
	public:
		enum { LOGTABLE_OUT_LOG = 16, LOGTABLE_MAX = (1 << LOGTABLE_OUT_LOG) - 1 };
		EG();
		void Trans(s32 &level, s32 &stay, s32 &c_sw, s32 &c_rate, s32 &c_l) {
			Trans(phase - 1, level, stay, c_sw, c_rate, c_l);
		}
		void Trans(s32 next_phase, s32 &level, s32 &stay, s32 &c_sw, s32 &c_rate, s32 &c_l) {
			phase = next_phase;
			if (phase >= A1) level = LEVEL_MIN;
			stay = phase == OFF || phase == S ? -1 : 0;
			c_sw = phase >= A2 ? -1 : 0;
			c_rate = c_sw ? ratetable[rate[phase]] : -ratetable[rate[phase]];
			c_l = l[phase];
		}
		void SetParam(OpParam *p, u8 ratio);
	private:
		s32 l[N];
		u8 rate[N];
		u8 phase;
		static void MakeTable();
		static u16 logtable[LOGTABLE_N];
		static s32 ratetable[RATETABLE_N];
	};
	class PG {
		friend class Operator8;
		friend class Channel8;
		enum { POWTABLE_LOG = 12, POWTABLE_N = 1 << POWTABLE_LOG, POWTABLE_MASK = POWTABLE_N - 1 };
		enum { POWTABLE_OUT_LOG = 14 };
		enum { LOGSINTABLE_LOG = 12, LOGSINTABLE_N = 1 << LOGSINTABLE_LOG, LOGSINTABLE_MASK = LOGSINTABLE_N - 1 };
		struct IIRParam {
			float k, b1, b2, a0, a1, a2;
		};
		struct IIRElm {
			IIRElm(IIRParam *_p) : p(_p), r0(0.f), r1(0.f), r2(0.f) {}
			float Calc(float x) {
				r0 = p->k * x - p->b1 * r1 - p->b2 * r2;
				float y = p->a0 * r0 + p->a1 * r1 + p->a2 * r2;
				r2 = r1;
				r1 = r0;
				return y;
			}
			IIRParam *p;
			float r0, r1, r2;
		};
	public:
		PG();
		void SetParam(OpParam *p, u8 ratio);
		void SetVolExp(u8 vol, u8 exp) {
			int t = (EG::LOGTABLE_MAX >> 1) -
				(velo << (EG::LOGTABLE_OUT_LOG - 9)) -
				(vol * exp << (EG::LOGTABLE_OUT_LOG - 16));
			fvol = carrier ? t : vs * t >> 7; //(EG::LOGTABLE_OUT_LOG-1)bit
		}
		u32 GetDelta(u8 note, s16 bend) { // note:0-254
			u16 v = (note << 7) + bend + det;
			u16 index = v >> 7;
			if (index > 254) index = 254;
			v &= 0x7f;
			u32 d = ((128 - v) * deltatable[index] + v * deltatable[index + 1]) >> 7;
			return mul * d >> 9;
		}
		s16 Update(s32 x, s32 t) {
			t += wave ? POWTABLE_N : logsintable[x & LOGSINTABLE_MASK];
			int s = t >> POWTABLE_LOG;
			if (s >= 16) return 0;
			s16 v = powtable[t & POWTABLE_MASK] >> s;
			if (x & LOGSINTABLE_N) v = -v;
			return v;
		}
		s16 Update(s32 x, s32 t, int noise) {
			s16 v;
			if (noise) {
				r = r << 1 | ((r >> 15 ^ r >> 11 ^ r >> 2 ^ r) & 1);
				x = int(i1.Calc(i0.Calc(r)));
				v = x * (powtable[t & POWTABLE_MASK] >> (t >> POWTABLE_LOG)) >> 15;
			}
			else v = Update(x, t);
			return v;
		}
		void GetFilter0(float &f0, float &f1, float &f2) {
			f0 = i0.r0;
			f1 = i0.r1;
			f2 = i0.r2;
		}
		void GetFilter1(float &f0, float &f1, float &f2) {
			f0 = i1.r0;
			f1 = i1.r1;
			f2 = i1.r2;
		}
		void SetFilter0(float f0, float f1, float f2) {
			i0.r0 = f0;
			i0.r1 = f1;
			i0.r2 = f2;
		}
		void SetFilter1(float f0, float f1, float f2) {
			i1.r0 = f0;
			i1.r1 = f1;
			i1.r2 = f2;
		}
		static void MakeTable();
	private:
		IIRElm i0, i1;
		u16 mul, fvol;
		u8 velo, vs, carrier;
		s8 det;
		static int wave;
		static u16 logsintable[LOGSINTABLE_N];
		static u16 powtable[POWTABLE_N];
		static u32 deltatable[256];
		static IIRParam iirparam[];
		static s16 r;
	};
public:
	Operator8();
	void NoteOn(OpParam *p, u8 ratio, u8 velo, u8 vol, u8 exp, bool carrier);
	s16 Update(s32 x, s32 lindex) {
		s32 t = (eg.phase != EG::H ? EG::logtable[lindex] : EG::LOGTABLE_MAX) + pg.fvol;
		return pg.Update(x, t);
	}
	s16 Update(s32 x, s32 lindex, s32 noise) {
		s32 t = (eg.phase != EG::H ? EG::logtable[lindex] : EG::LOGTABLE_MAX) + pg.fvol;
		return pg.Update(x, t, noise);
	}
	static void MakeTable() {
		EG::MakeTable();
		PG::MakeTable();
	}
	static void SetWave(int wave) { PG::wave = wave; }
	static int GetWave() { return PG::wave; }
	static s16 GetRand() { return PG::r; }
	static void SetRand(s16 _r) { PG::r = _r; }
private:
	s16 con[8] _ALIGN;
	EG eg;
	PG pg;
};
