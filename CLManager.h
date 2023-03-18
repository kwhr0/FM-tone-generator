#include "GPManager.h"
#include <OpenCL/OpenCL.h>

class CLManager : public GPManager {
public:
	class Buffer {
	public:
		Buffer() : cl(NULL), m(NULL), size(0) {}
		~Buffer() {
			clReleaseMemObject(m);
			m = NULL;
		}
		operator cl_mem() const { return m; }
		void Init(CLManager *_cl, size_t _size) {
			cl = _cl;
			size = _size;
			m = clCreateBuffer(cl->mContext, CL_MEM_READ_WRITE, size, NULL, NULL);
			if (!m) throw "clCreateBuffer";
		}
		void Read(void *dst) {
			if (cl && clEnqueueReadBuffer(cl->mQueue, m, CL_TRUE, 0, size, dst, 0, NULL, NULL) != CL_SUCCESS) throw "clEnqueueReadBuffer";
		}
		void Write(void *src) {
			if (cl && clEnqueueWriteBuffer(cl->mQueue, m, CL_TRUE, 0, size, src, 0, NULL, NULL) != CL_SUCCESS) throw "clEnqueueWriteBuffer";
		}
	private:
		CLManager *cl;
		cl_mem m;
		size_t size;
	};
	CLManager() : mDeviceID(0), mContext(NULL), mQueue(NULL), mProgram(NULL), mKernel(NULL), mParamNo(0) {
		Init();
	}
	~CLManager() {
		clReleaseContext(mContext);
		clReleaseCommandQueue(mQueue);
		clReleaseProgram(mProgram);
		clReleaseKernel(mKernel);
	}
	void Init();
	void Load(const char *kernelname, const char *code) {
		unsigned deviceCount;
		int result = clGetDeviceIDs(NULL, CL_DEVICE_TYPE_GPU, 1, &mDeviceID, &deviceCount);
		if ((result != CL_SUCCESS || deviceCount != 1) && clGetDeviceIDs(NULL, CL_DEVICE_TYPE_CPU, 1, &mDeviceID, &deviceCount) != CL_SUCCESS) throw "clGetDeviceIDs";
		if (deviceCount != 1) throw "deviceCount";
		size_t len;
#ifdef PRINT_DEVICE
		char deviceName[256] = { 0 };
		clGetDeviceInfo(mDeviceID, CL_DEVICE_NAME, sizeof(deviceName), deviceName, &len);
		printf("DEVICE: %s\n", deviceName);
#endif
		mContext = clCreateContext(NULL, 1, &mDeviceID, NULL, NULL, NULL);
		if (!mContext) throw "clCreateContext";
		mQueue = clCreateCommandQueue(mContext, mDeviceID, 0, NULL);
		if (!mQueue) throw "clCreateCommandQueue";
		mProgram = clCreateProgramWithSource(mContext, 1, (const char **)&code, NULL, NULL);
		if (!mProgram) throw "clCreateProgramWithSource";
		result = clBuildProgram(mProgram, 0, NULL, NULL, NULL, NULL);
		char log[65536];
		clGetProgramBuildInfo(mProgram, mDeviceID, CL_PROGRAM_BUILD_LOG, sizeof(log), log, &len);
		if (len) fputs(log, stderr);
		if (result != CL_SUCCESS) throw "clBuildProgram";
		mKernel = clCreateKernel(mProgram, kernelname, NULL);
		if (!mKernel) throw "clCreateKernel";
	}
	void SetArg(Buffer &buffer) {
		const cl_mem &m = cl_mem(buffer);
		if (clSetKernelArg(mKernel, mParamNo++, sizeof(cl_mem), &m) != CL_SUCCESS) throw "clSetKernelArg";
	}
	void Execute(size_t globalSize, size_t localSize = 0) {
		if (clEnqueueNDRangeKernel(mQueue, mKernel, 1, NULL, &globalSize, localSize ? &localSize : NULL, 0, NULL, NULL) != CL_SUCCESS) throw "clEnqueueNDRangeKernel";
		mParamNo = 0;
	}
	void Finish() { clFinish(mQueue); }
	void Run(GPVars *vars, int numChannels, void (^)(int32_t *));
private:
	cl_device_id mDeviceID;
	cl_context mContext;
	cl_command_queue mQueue;
	cl_program mProgram;
	cl_kernel mKernel;
	cl_uint mParamNo;
};
