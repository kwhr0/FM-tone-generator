#include <stdlib.h>
#include <string.h>
#include "ChannelManager.h"
#include "Channel8.h"
#include "Midi.h"

#define v2(p)	(((u8 *)(p))[0] | ((u8 *)(p))[1] << 8)

QDGlobals qd;
extern int gSampleRate;

void FMMain(int att);

static void InitToolbox() {
	InitGraf(&qd.thePort);
	InitFonts();
	InitWindows();
	InitMenus();
	FlushEvents(everyEvent, 0);
	TEInit();
	InitDialogs(0L);
	InitCursor();
}

void fatal(Str255 msg) {
	ParamText(msg, nil, nil, nil);
	Alert(128, nil);
	ExitToShell();
}

static int sQuit;

static void doMenuCommand(long menuChoice) {
	short menu, item;
	Str255 accName;
	if (menuChoice) {
		menu = HiWord(menuChoice);
		item = LoWord(menuChoice);
		switch (menu) {
			case 128:
				switch(item) {
					case 1:
						ParamText("\pFM sound generator for 68k", nil, nil, nil);
						Alert(128, nil);
						break;
					default:
						GetMenuItemText(GetMenuHandle(128), item, accName);
						OpenDeskAcc(accName);
						break;
				}
				break;
			case 129:
				if (item == 1) sQuit = 1;
				break;			
		}
		HiliteMenu(0);
	}
}

static void doMouseDown(EventRecord *e) {
	WindowPtr win;
	switch (FindWindow(e->where, &win)) {
		case inMenuBar:
			doMenuCommand(MenuSelect(e->where));
			break;
	}
}

int doEvent(EventRecord *e) {
	switch(e->what) {
		case mouseDown:
			doMouseDown(e);
			break;
		case keyDown: case autoKey:
			if (e->modifiers & cmdKey) 
				doMenuCommand(MenuKey(e->message & charCodeMask));
			break;
	}
	return sQuit;
}

void debug() {}

int main() {
	InitToolbox();
	Handle menuBar = GetNewMBar(128);
	SetMenuBar(menuBar);
	DisposeHandle(menuBar);
	AppendResMenu(GetMenuHandle(128), 'DRVR');	
	DrawMenuBar();
	gMan = new ChannelManager();
	FILE *fi = fopen("fm_68k.ini", "r");
	if (!fi) fatal("\pfm_68k.ini not found.");
	char s[256], cmd[256], param[256], filename[256];
	int att = 0, tone = 0;
	while (fgets(s, sizeof(s), fi)) {
		if (sscanf(s, "%s%s", cmd, param) != 2) continue;
		if (*cmd == ';' || *cmd == '#') continue;
		int value = atoi(param);
		if (!strcmp(cmd, "chmax")) gMan->SetChN(value);
		else if (!strcmp(cmd, "att")) att = value;
		else if (!strcmp(cmd, "tone")) {
			tone = value;
		}
		else if (!strcmp(cmd, "psg")) {
			if (value) {
				Channel8::SetModulate(0);
				Operator8::SetWave(1);
			}
		}
		else if (!strcmp(cmd, "samplerate")) {
			if (value >= 0 && value <= 3) gSampleRate = value;
		}
		else if (!strcmp(cmd, "file")) strcpy(filename, param);
	}
	fclose(fi);
	Operator8::MakeTable();
	Handle h = GetResource('tone', 127 + tone);
	if (!h) fatal("\pno tone data.");
	HLock(h);
	unsigned char *p = (unsigned char *)*h + 4;
	Channel8::AppendToneData(&p[v2(&p[0])]);
	ChannelManager::AppendDrumData((Drum *)&p[v2(&p[2])]);
	gMidi = new Midi(0);
	if (gMidi->Prepare(filename)) fatal("\pmidi file not found.");
	gMidi->Position(-1.f);
	FMMain(att + 8);
	return 0;
}
