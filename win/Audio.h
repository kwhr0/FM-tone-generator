typedef void (*AudioCallback)(short *buf, int len);

void AudioSetup(AudioCallback callback);
