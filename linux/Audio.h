typedef void (*AudioCallback)(short *buffer, int numSamples);

int AudioSetup(AudioCallback func);
