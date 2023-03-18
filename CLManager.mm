#import "gp_types.h"
#import "CLManager.h"
#import "Util.h"

void CLManager::Init() {
	try {
		Load("CLOperator", "CLOperator.cl");
	}
	catch (const char *msg) {
		fprintf(stderr, "failed: %s\n", msg);
		exit(1);
	}
}

void CLManager::Run(GPVars *vars, int numChannels, void (^post)(int32_t *)) {
	if (numChannels <= 0) return;
	try {
		MeasureTime<0> _;
		Buffer varsD, sampleBufferD;
		varsD.Init(this, sizeof(GPVars));
		sampleBufferD.Init(this, sizeof(int32_t) * GP_CH_N * vars->numSamples);
		varsD.Write(vars);
		SetArg(varsD);
		SetArg(sampleBufferD);
		{
			MeasureTime<1> _;
			Execute(numChannels << 3);
			Finish();
		}
		varsD.Read(vars);
		int32_t *sampleBuffer = new int32_t[GP_CH_N * vars->numSamples];
		sampleBufferD.Read(sampleBuffer);
		Finish();
		post(sampleBuffer);
		delete[] sampleBuffer;
	}
	catch (const char *msg) {
		fprintf(stderr, "failed: %s\n", msg);
		exit(1);
	}
}
