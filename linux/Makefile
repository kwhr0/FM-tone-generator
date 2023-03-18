CXXFLAGS = -O3 -DMULTI_THREAD -march=armv7-a -mfpu=neon -flax-vector-conversions -Wno-multichar # Raspberry Pi 2
#CXXFLAGS = -O3 -Wno-multichar # Raspberry Pi / general Linux

OBJS = Audio.o Channel8.o ChannelManager.o FMMain.o main.o Midi.o Operator8.o
LDFLAGS = -lasound -lpthread
DEPEND = Depend

default: $(DEPEND) fm_raspi $(CNV) $(TONES)
fm_raspi: $(OBJS)
	$(LINK.cc) $(OBJS) -o $@
%.o: %.cpp
	$(COMPILE.cc) -include fm_raspi.h $<
$(DEPEND):; $(CXX) $(CXXFLAGS) -MM $(OBJS:.o=.cpp) > $(DEPEND)
clean:; rm -fr *.o $(DEPEND)
-include $(DEPEND)
