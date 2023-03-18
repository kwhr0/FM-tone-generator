#include "Audio.h"
#include <alsa/asoundlib.h>

#define SAMPLE_UNIT 2048

static snd_pcm_t *pcm;
static short buffer[2 * SAMPLE_UNIT];
static AudioCallback callback;

static void *thread_func(void *) {
	while (1) {
		callback(buffer, SAMPLE_UNIT);
		int result = snd_pcm_writei(pcm, buffer, SAMPLE_UNIT);
		if (result < 0 && snd_pcm_recover(pcm, result, 0) < 0) break;
	}
	return NULL;
}

int AudioSetup(AudioCallback func) {
	int result = snd_pcm_open(&pcm, "default", SND_PCM_STREAM_PLAYBACK, 0);
	if (result) return result;
	result = snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE, 
		SND_PCM_ACCESS_RW_INTERLEAVED, 2, 44100, 1, 100000);
	if (result) {
		snd_pcm_close(pcm);
		return result;
	}
	pthread_t thread;
	result = pthread_create(&thread, NULL, thread_func, NULL);
	if (result) {
		snd_pcm_close(pcm);
		return result;
	}
	callback = func;
	return 0;
}
