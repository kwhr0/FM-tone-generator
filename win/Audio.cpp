#include <windows.h>
#include "Audio.h"

#pragma comment(lib, "winmm.lib")

#define SAMPLE_UNIT		2048
#define FS				44100

static HWAVEOUT sWave;
static AudioCallback sCallback;

void CALLBACK waveOutProc(HWAVEOUT hwave, UINT msg, DWORD_PTR instance, DWORD_PTR param1, DWORD_PTR param2) {
	if (sCallback && msg == WOM_DONE) {
		sCallback((short *)((PWAVEHDR)param1)->lpData, ((PWAVEHDR)param1)->dwBufferLength >> 2);
		waveOutWrite(hwave, (PWAVEHDR)param1, sizeof(WAVEHDR));
	}
}

void AudioSetup(AudioCallback callback) {
	WAVEFORMATEX waveformat;
	waveformat.wFormatTag      = WAVE_FORMAT_PCM;
	waveformat.nChannels       = 2;
	waveformat.nSamplesPerSec  = FS;
	waveformat.nAvgBytesPerSec = 4 * FS;
	waveformat.nBlockAlign     = 4;
	waveformat.wBitsPerSample  = 16;
	waveformat.cbSize          = 0;
	if (waveOutOpen(&sWave, WAVE_MAPPER, &waveformat, (DWORD_PTR)waveOutProc, NULL, CALLBACK_FUNCTION) != MMSYSERR_NOERROR)
		exit(1);
	for (int i = 0; i < 2; i++) {
		PWAVEHDR p = (PWAVEHDR)malloc(sizeof(WAVEHDR));
		p->lpData          = (LPSTR)malloc(4 * SAMPLE_UNIT);
		p->dwBufferLength  = 4 * SAMPLE_UNIT;
		p->dwBytesRecorded = 0;
		p->dwUser          = 0;
		p->dwFlags         = 0;
		p->dwLoops         = 1;
		p->lpNext          = NULL;
		p->reserved        = 0;
		callback((short *)p->lpData, p->dwBufferLength >> 2);
		waveOutPrepareHeader(sWave, p, sizeof(WAVEHDR));
		waveOutWrite(sWave, p, sizeof(WAVEHDR));
	}
	sCallback = callback;
}
