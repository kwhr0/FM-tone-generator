struct GPManager {
	virtual void Run(GPVars *vars, int numChannels, void (^)(int32_t *)) = 0;
};
