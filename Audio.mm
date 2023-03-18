#include "Audio.h"

#define REVERB			10		// 0-100

static AudioCallback callback;

static OSStatus MyAURenderCallback (void *, AudioUnitRenderActionFlags *,
	const AudioTimeStamp *, UInt32, UInt32 inNumberFrames, 
	AudioBufferList *ioData) {
	if (callback) {
		callback(
			(float *)ioData->mBuffers[0].mData, 
			(float *)ioData->mBuffers[1].mData,
			inNumberFrames);
	}
	return noErr;
}

#if	MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
#define ADDNODE(graph, desc, node)			(AUGraphAddNode(graph, desc, node))
#define NODEINFO(graph, node, audiounit)	(AUGraphNodeInfo(graph, node, NULL, audiounit))
#else
#define ADDNODE(graph, desc, node)			(AUGraphNewNode(graph, desc, 0, NULL, node))
#define NODEINFO(graph, node, audiounit)	(AUGraphGetNodeInfo(graph, node, NULL, NULL, NULL, audiounit))
#endif

#if	MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
#define COMPONENT	AudioComponentDescription
#else
#define COMPONENT	ComponentDescription
#endif

void AudioSetup(AudioCallback func) {
	AUGraph graph;
	AUNode effectNode, outputNode;
	NewAUGraph(&graph);
	COMPONENT cd = { 0, 0, kAudioUnitManufacturer_Apple };
	cd.componentType = kAudioUnitType_Effect;
	cd.componentSubType = kAudioUnitSubType_MatrixReverb;
	ADDNODE(graph, &cd, &effectNode);
	cd.componentType = kAudioUnitType_Output;
	cd.componentSubType = kAudioUnitSubType_DefaultOutput;
	ADDNODE(graph, &cd, &outputNode);
	AUGraphConnectNodeInput(graph, effectNode, 0, outputNode, 0);
	AURenderCallbackStruct cs = { MyAURenderCallback };
//	AUGraphSetNodeInputCallback(graph, effectNode, 0, &cs);
	AUGraphOpen(graph);
	AUGraphInitialize(graph);
	AUGraphStart(graph);
	AudioUnit effectAudioUnit;
	NODEINFO(graph, effectNode, &effectAudioUnit);
	AudioUnitSetProperty(effectAudioUnit, 
		kAudioUnitProperty_SetRenderCallback, 
		kAudioUnitScope_Global, 0, &cs, sizeof(cs));
	static float d[] = {
		REVERB, 50.f, .0172f, .087f,
		.011f, .0214f, .735f, .64f,
		.565f, .68f, .739f, .585f,
		.75f, .31f, 3.f, 0.f
	};
	for (int i = 0; i < sizeof(d) / sizeof(float); i++)
		AudioUnitSetParameter(effectAudioUnit, i, kAudioUnitScope_Global, 0, d[i], 0);
	callback = func;
}
