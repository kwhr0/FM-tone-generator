#include "Audio.h"
#include "ChannelManager.h"
#include "FMMain.h"
#include "Midi.h"
#include "Channel8.h"
#if defined(USE_METAL) || defined(USE_OPENCL)
#include "Util.h"
#endif

#ifndef DEF_N
#define DEF_N			64
#endif

int main(int argc, char *const *argv) {
	int c, n = DEF_N, t = 1, p = 0;
#ifdef WIN32
	if (argc < 2) {
		fprintf(stderr, "Usage: fm_win <midi file>\n");
		return 0;
	}
	int index = 1, multi = 0;
#else
	while ((c = getopt(argc, argv, "n:pt:")) != -1) {
		switch (c) {
			case 'n':
				sscanf(optarg, "%d", &n);
				break;
			case 'p':
				p = 1;
				break;
			case 't':
				sscanf(optarg, "%d", &t);
				break;
		}
	}
	if (argc <= optind) {
		fprintf(stderr, 
		"Usage: %s [options] <midi file>\n"
		"options:\n"
		"\t-n <number>      max. channel (default:%d)\n"
		"\t-t <tone number>              (default:1)\n"
		"\t-p PSG mode\n"
		, argv[0], DEF_N);
		return 0;
	}
	int index = optind, multi = optind < argc - 1;
#endif
	AudioSetup(FMMain::Callback);
	gFMMain = new FMMain;
	char s[16];
	sprintf(s, "tone%d.bin", t % 10);
	if (gFMMain->LoadTone(s)) {
		fprintf(stderr, "%s not found.\n", s);
		return 1;
	}
	gFMMain->NewChannelManager(n);
	Channel8::SetModulate(!p);
	Operator8::SetWave(p);
	gMidi = new Midi((double)MIDI_UNIT / FS);
	do {
		const char *path = argv[index];
		if (multi) printf("%s\n", path);
		if (gMidi->Prepare(path)) {
			fprintf(stderr, "%s not found or not MIDI file.\n", path);
			return 1;
		}
		FMMain::RequestPosition(-1.f);
	} while (!gFMMain->MainLoop() && ++index < argc);
#if defined(USE_METAL) || defined(USE_OPENCL)
//	MeasureTime<0>::Print(double(MIDI_UNIT) / FS);
//	MeasureTime<1>::Print(double(MIDI_UNIT) / FS);
#endif
    return 0;
}
