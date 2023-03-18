#import "GPManager.h"
#import <Metal/Metal.h>

class MetalManager : public GPManager {
public:
	MetalManager(int n);
	void Run(GPVars *vars, int numChannels, void (^)(int32_t *));
private:
	id<MTLDevice> device;
	id<MTLLibrary> defaultLibrary;
	id<MTLCommandQueue> commandQueue;
	id<MTLComputePipelineState> computePipelineState;
};
