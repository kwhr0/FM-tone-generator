typedef void (*AudioCallback)(float *buffer0, float *buffer1, int numSamples);

void AudioSetup(AudioCallback func);
