#define GP_CH_N		512
#define GP_OP_N		(8 * GP_CH_N)

struct GPOperator {
	enum Phase {
		OFF, R2, R1, S, D2, D1, A2, A1, H, N
	};
#ifdef __METAL_VERSION__
	float EG();
	int16_t PG(float t, int32_t mod, device int16_t &r, thread float3 &f0, thread float3 &f1, bool wave);
#endif
	float f00, f01, f02, f10, f11, f12;
	int32_t count, delta, lv;
	uint16_t ml, fvol;
	int32_t l[N];
	bool sw[N];
	uint8_t rate[N];
	int16_t value;
	int8_t phase;
	bool con[8];
	bool carrier, noise;
};

typedef struct GPOperator GPOperator; // for OpenCL

struct GPVars {
	int numSamples;
	GPOperator op[GP_OP_N];
	bool fz[GP_CH_N];
	int16_t r;
	bool psg;
};
