// FM tone generator
// Copyright (C) 2015-2023 by Yasuo Kuwahara

// MIT License

#include <metal_stdlib>

using namespace metal;

#include "gp_types.h"

float GPOperator::EG() {
	float t = phase != Phase::H ? fvol / 4096.f - 2.f * log2(float(lv) / (1 << 21)) : 100.f;
	int32_t tl = lv + (phase >= Phase::A2 ? 1 : -1) * (rate[phase] > 0 ? int(pow(2.f, rate[phase] / 16.f)) : 0);
	if (phase == OFF || phase == S || phase >= Phase::A2 ^ tl > l[phase]) lv = clamp(tl, 0, 1 << 21);
	else if (--phase >= Phase::A1) lv = 0;
	return t;
}

int16_t GPOperator::PG(float t, int32_t mod, device int16_t &r, thread float3 &f0, thread float3 &f1, bool wave) {
	const float2 c0a = float2(.206619f, .173525f);
	const float3 c0b = float3(2.83983f, -2.83983f, 0.f);
	const float3 c1a = float3(.0563561f, .458134f, -.359833f);
	const float3 c1b = float3(8.0646f, -16.1292f, 8.0646f);
	int16_t v;
	if (noise) {
		r = r << 1 | ((r >> 15 ^ r >> 11 ^ r >> 2 ^ r) & 1);
		f0.x = dot(c0a, float2(r, f0.y));
		f1.x = dot(c1a, float3(dot(c0b, f0), f1.yz));
		v = dot(c1b, f1) * pow(2.f, -1.f - t);
		f0.yz = f0.xy;
		f1.yz = f1.xy;
	}
	else {
		float x = float(count + ml * mod) / (1 << 21);
		v = sign(.5f - fract(.5f * x)) * pow(2.f, 14.f - t - (wave ? 1.f : -log2(sinpi(fract(x)))));
		count += delta;
	}
	return v;
}

kernel void MetalOperator(device GPVars *vars [[ buffer(0) ]],
						  device int32_t *sampleBuffer [[ buffer(1) ]],
						  uint id [[ thread_position_in_grid ]]) {
	GPOperator op = vars->op[id];
	float3 f0 = float3(op.f00, op.f01, op.f02), f1 = float3(op.f10, op.f11, op.f12);
	for (int i = 0; i < vars->numSamples; i++) {
		int32_t mod = 0;
		if (!vars->psg)
			for (int j = 0; j < 8; j++)
				mod += op.con[j] ? vars->op[(id & ~7) + j].value : 0;
		int16_t value = op.PG(op.EG(), mod, vars->r, f0, f1, vars->psg);
		threadgroup_barrier(mem_flags::mem_none);
		vars->op[id].value = value;
		threadgroup_barrier(mem_flags::mem_none);
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
	op.f00 = f0.x;
	op.f01 = f0.y;
	op.f02 = f0.z;
	op.f10 = f1.x;
	op.f11 = f1.y;
	op.f12 = f1.z;
	op.value = vars->op[id].value;
	vars->op[id] = op;
}
