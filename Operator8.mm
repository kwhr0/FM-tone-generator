// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

#include "Operator8.h"

#ifdef CLASSIC
extern int gSampleRate;
#endif

u16 Operator8::EG::logtable[LOGTABLE_N];
s32 Operator8::EG::ratetable[RATETABLE_N];
u16 Operator8::PG::logsintable[LOGSINTABLE_N];
u16 Operator8::PG::powtable[POWTABLE_N];
u32 Operator8::PG::deltatable[256];
int Operator8::PG::wave;
s16 Operator8::PG::r = 1;

Operator8::EG::EG() {
	phase = OFF;
	l[OFF] = l[S] = l[R1] = l[R2] = LEVEL_MIN;
	l[H] = l[A1] = l[A2] = l[D1] = l[D2] = LEVEL_MAX;
	rate[OFF] = rate[S] = 0;
	rate[A1] = rate[A2] = rate[D1] = rate[D2] = rate[R1] = rate[R2] = 0xff;
	rate[H] = 0xff;
}

void Operator8::EG::MakeTable() {
#ifdef CLASSIC
	BlockMove(*GetResource('logt', 128), logtable, sizeof(logtable));
	BlockMove(*GetResource('rate', 128), ratetable, sizeof(ratetable));
	for (int i = 0; i < RATETABLE_N; i++) ratetable[i] <<= 3 - gSampleRate;
#else
	int i;
	double log2 = log(2.0), k = -(1 << (LOGTABLE_OUT_LOG - 3));
	for (i = 0; i < LOGTABLE_N; i++) {
		int v = k * log(double(i + 1) / LOGTABLE_N) / log2;
		logtable[i] = v > LOGTABLE_MAX ? LOGTABLE_MAX : v;
	}
	ratetable[0] = 0;
	for (i = 1; i < RATETABLE_N; i++) {
#ifdef SHIFTED_LEVEL
		ratetable[i] = s32(2048.0 * pow(2.0, 16.0 * i / RATETABLE_N));
#else
		ratetable[i] = s32(pow(2.0, 16.0 * i / RATETABLE_N));
		if (!ratetable[i]) ratetable[i] = 1;
#endif
	}
#ifdef DUMP
	FILE *fo = fopen("logtable", "wb");
	if (fo) {
		fwrite(logtable, 1, sizeof(logtable), fo);
		fclose(fo);
	}
	fo = fopen("ratetable", "wb");
	if (fo) {
		fwrite(ratetable, 1, sizeof(ratetable), fo);
		fclose(fo);
	}
#endif
#endif
}

#define egid_rate(phase, src)	(rate[phase] = ((0x100 - ratio) * p[0].src + ratio * p[1].src) >> 8)
#ifdef SHIFTED_LEVEL
#define egid_l(phase, src)		(l[phase] = ((s32)(((0x100 - ratio) * p[0].src + ratio * p[1].src) >> 8) << 24) - LEVEL_MIN)
#else
#define egid_l(phase, src)		(l[phase] = (((0x100 - ratio) * p[0].src + ratio * p[1].src) >> 8) << 13)
#endif

void Operator8::EG::SetParam(OpParam *p, u8 ratio) {
	egid_rate(H, ht);
	egid_rate(A1, at1);
	egid_rate(A2, at2);
	egid_rate(D1, dt1);
	egid_rate(D2, dt2);
	egid_rate(S, st);
	egid_rate(R1, rt1);
	egid_rate(R2, rt2);
	egid_l(A1, al);
	egid_l(A2, tl);
	egid_l(D1, dl);
	egid_l(D2, sl);
	egid_l(R1, rl);
}

// HPF,バタワース,2205,11025,0.5dB,35dB
Operator8::PG::IIRParam Operator8::PG::iirparam[] = {
	{ 2.06618808993525943e-01, -1.73524764025896339e-01, 0., 2.83983043398209434e+00, -2.83983043398209434e+00, 0. },
	{ 5.63561327378342761e-02, -4.58134432632905764e-01, 3.59832556438254181e-01, 8.06463689377092940e+00, -1.61292737875418588e+01, 8.06463689377092940e+00 },
};

Operator8::PG::PG() : i0(&iirparam[0]), i1(&iirparam[1]) {
	mul = 0x200; // Fixed7.9
	det = 0; // Fixed S.7
	vs = 0; // Fixed1.7
	velo = 0x7f; // 0..min 0x7f..max
	fvol = 0; // 0x7ff..min 0..max
}

void Operator8::PG::MakeTable() {
#ifdef CLASSIC
	BlockMove(*GetResource('logs', 128), logsintable, sizeof(logsintable));
	BlockMove(*GetResource('powt', 128), powtable, sizeof(powtable));
	BlockMove(*GetResource('delt', 128), deltatable, sizeof(deltatable));
	for (int i = 0; i < 256; i++) deltatable[i] <<= 3 - gSampleRate;
#else
	double log2 = log(2.0);
	int i;
	for (i = 0; i < POWTABLE_N; i++) {
		u16 v = (u16)pow(2.0, POWTABLE_OUT_LOG - double(i) / POWTABLE_N);
		powtable[i] = v;
	}
	for (i = 0; i < LOGSINTABLE_N / 2; i++) {
		double r = 0.5 * M_PI * (i + 1) / (LOGSINTABLE_N / 2);
		u16 v = u16(-POWTABLE_N * log(sin(r)) / log2);
		logsintable[i] = v;
		logsintable[LOGSINTABLE_MASK - i] = v;
	}
	for (i = 0; i < 256; i++)
		deltatable[i] = u32((1 << 22) * 440.0 * pow(2.0, double(i - 2 * 69) / 24.0) / FS);
#ifdef DUMP
	FILE *fo = fopen("powtable", "wb");
	if (fo) {
		fwrite(powtable, 1, sizeof(powtable), fo);
		fclose(fo);
	}
	fo = fopen("logsintable", "wb");
	if (fo) {
		fwrite(logsintable, 1, sizeof(logsintable), fo);
		fclose(fo);
	}
	fo = fopen("deltatable", "wb");
	if (fo) {
		fwrite(deltatable, 1, sizeof(deltatable), fo);
		fclose(fo);
	}
#endif
#endif
}

#define pgid(name)	(name = ((0x100 - ratio) * p[0].name + ratio * p[1].name) >> 8)
#define pgid2(name)	(name = ((0x100 - ratio) * (p[0].name##_l | p[0].name##_u << 8) + ratio * (p[1].name##_l | p[1].name##_u << 8)) >> 8)

void Operator8::PG::SetParam(OpParam *p, u8 ratio) {
	pgid2(mul);
	pgid(det);
	pgid(vs);
}

Operator8::Operator8() {
	for (int i = 0; i < 8; i++) con[i] = 0;
}

void Operator8::NoteOn(OpParam *p, u8 ratio, u8 velo, u8 vol, u8 exp, bool _carrier) {
	for (int i = 0; i < 8; i++) con[i] = p->con >> i & 1;
	eg.SetParam(p, ratio);
	pg.SetParam(p, ratio);
	pg.velo = velo;
	pg.carrier = _carrier;
	pg.SetVolExp(vol, exp);
}
