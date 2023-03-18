#import "gp_types.h"
#import "MetalManager.h"
#import "Util.h"

MetalManager::MetalManager(int n) {
	device = MTLCreateSystemDefaultDevice();
	defaultLibrary = [device newDefaultLibrary];
	commandQueue = [device newCommandQueue];
	id<MTLFunction> func = [defaultLibrary newFunctionWithName:@"MetalOperator"];
	computePipelineState = [device newComputePipelineStateWithFunction:func error:nil];
}

void MetalManager::Run(GPVars *vars, int numChannels, void (^post)(int32_t *)) {
	if (numChannels <= 0) return;
	@autoreleasepool {
		id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
		id<MTLComputeCommandEncoder> computeCommandEncoder = [commandBuffer computeCommandEncoder];
		[computeCommandEncoder setComputePipelineState:computePipelineState];
		//
		id<MTLBuffer> varsD = [device newBufferWithBytes:vars length:sizeof(GPVars) options:0];
		[computeCommandEncoder setBuffer:varsD offset:0 atIndex:0];
		id<MTLBuffer> sampleBufferD = [device newBufferWithLength:sizeof(int32_t) * GP_CH_N * vars->numSamples options:0];
		[computeCommandEncoder setBuffer:sampleBufferD offset:0 atIndex:1];
		//
		int tpt = 8;
		if (tpt > GP_OP_N) tpt = GP_OP_N;
		MTLSize threadsPerGroup = MTLSizeMake(tpt, 1, 1);
		MTLSize numThreadgroups = MTLSizeMake(((numChannels << 3) + tpt - 1) / tpt, 1, 1);
		[computeCommandEncoder dispatchThreadgroups:numThreadgroups threadsPerThreadgroup:threadsPerGroup];
		[computeCommandEncoder endEncoding];
		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];
		memmove(vars, varsD.contents, sizeof(GPVars));
		post((int32_t *)sampleBufferD.contents);
	}
}
