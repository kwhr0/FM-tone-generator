// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;

#include "gp_types.h"

inline float EG(GPOperator *op) {
	float t = op->phase != H ? op->fvol / 4096.f - 2.f * log2((float)op->lv / (1 << 21)) : 100.f;
	int32_t tl = op->lv + (op->sw[op->phase] ? 1 : -1) *
	(op->rate[op->phase] > 0 ? (int)pow(2.f, op->rate[op->phase] / 16.f) : 0);
	if (op->phase == OFF || op->phase == S || op->sw[op->phase] ^ (tl > op->l[op->phase])) op->lv = clamp(tl, 0, 1 << 21);
	else if (--op->phase >= A1) op->lv = 0;
	return t;
}

inline int16_t PG(GPOperator *op, float t, int32_t mod, __global int16_t *r, bool wave) {
	int16_t v;
	if (op->noise) {
		*r = *r << 1 | ((*r >> 15 ^ *r >> 11 ^ *r >> 2 ^ *r) & 1);
		op->f00 = .206619f * *r + .173525f * op->f01;
		float f = 2.83983f * op->f00 - 2.83983f * op->f01;
		op->f10 = .0563561f * f + .458134f * op->f11 - .359833f * op->f12;
		f = 8.0646f * op->f10 - 16.1292f * op->f11 + 8.0646f * op->f12;
		v = f * pow(2.f, -1.f - t);
		op->f02 = op->f01;
		op->f01 = op->f00;
		op->f12 = op->f11;
		op->f11 = op->f10;
	}
	else {
		float dummy;
		float x = (float)(op->count + op->ml * mod) / (1 << 21);
		v = sign(.5f - fract(.5f * x, &dummy)) * pow(2.f, 14.f - t - (wave ? 1.f : -log2(sinpi(fract(x, &dummy)))));
		op->count += op->delta;
	}
	return v;
}


__kernel void CLOperator(__global struct GPVars *vars, __global int32_t *sampleBuffer) {
	int id = get_global_id(0);
	GPOperator op = vars->op[id];
	for (int i = 0; i < vars->numSamples; i++) {
		int32_t mod = 0;
		if (!vars->psg) 
			for (int j = 0; j < 8; j++) 
				mod += op.con[j] ? vars->op[(id & ~7) + j].value : 0;
		int16_t value = PG(&op, EG(&op), mod, &vars->r, vars->psg);
		barrier(CLK_LOCAL_MEM_FENCE);
		vars->op[id].value = value;
		barrier(CLK_LOCAL_MEM_FENCE);
		if (!(id & 7)) {
			int32_t v = 0;
			for (int j = 0; j < 8; j++) 
				if (vars->op[(id & ~7) + j].carrier) {
					int32_t t = vars->op[(id & ~7) + j].value;
					v += vars->fz[id >> 3] ? 6 * clamp(t, -512, 511) : t;
				}
			sampleBuffer[id >> 3] = v;
			sampleBuffer += GP_CH_N;
		}
	}
	op.value = vars->op[id].value;
	vars->op[id] = op;
}
