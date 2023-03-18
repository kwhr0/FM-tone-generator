TONEDIR = ../fmtone
TONES = tone1.bin tone2.bin tone3.bin

CXXFLAGS = -DDEF_N=256 -O3
#CXXFLAGS = -DDEF_N=256 -DUSE_METAL -O3
#CXXFLAGS = -DDEF_N=256 -DUSE_OPENCL -O3
#CXXFLAGS = -DDEF_N=256 -mavx2 -O3
#CXXFLAGS = -DDEF_N=256 -msse4.1 -O3 # for i3/i5/i7
#CXXFLAGS = -DDEF_N=128 -O3 -DMULTI_THREAD # for Core2Duo
#CXXFLAGS = -DDEF_N=64 -maltivec -O3 -DALTIVEC_RAW # for PowerPC G4

OBJS = Audio.o Channel8.o ChannelManager.o FMMain.o main.o Midi.o Operator8.o
LDFLAGS = -framework Foundation -framework AudioUnit -framework AudioToolBox
DEPEND = Depend
PCH = fm_OSX-Prefix.pch
CNV = cnv/cnv.exe
TARGET_MPW = mpw
TARGET_VS = vs
TARGET_RASPI = raspi
SRC68K = Channel8.mm ChannelManager.mm Midi.mm Operator8.mm
SRCWIN = $(SRC68K) FMMain.mm
SRCRASPI = $(SRCWIN)

ifeq ($(CXX),g++)
default: $(DEPEND) fm_OSX $(CNV) $(TONES)
else
default: $(DEPEND) $(PCH) fm_OSX $(CNV) $(TONES)
endif

ifneq ($(findstring USE_METAL,$(CXXFLAGS)),)
METAL_LIB = default.metallib
CXXFLAGS += -fobjc-arc
OBJS += MetalManager.o
LDFLAGS += -framework Metal
%.air: %.metal
	xcrun -sdk macosx metal -c $< -o $@
$(METAL_LIB): MetalOperator.air
	xcrun -sdk macosx metallib $< -o $@
MetalOperator.air: gp_types.h
default: $(METAL_LIB)
endif

ifneq ($(findstring USE_OPENCL,$(CXXFLAGS)),)
OBJS += CLManager.o
LDFLAGS += -framework OpenCL
endif

all: default $(TARGET_MPW) $(TARGET_VS) $(TARGET_RASPI)
fm_OSX: $(OBJS)
	$(LINK.cc) $(OBJS) -o $@
%.o: %.mm
ifeq ($(CXX),g++)
	$(COMPILE.cc) -include $(PCH:.pch=.h) $<
else
	$(COMPILE.cc) -include-pch $(PCH) $<
endif
ifneq ($(CXX),g++)
%.pch: %.h
	$(COMPILE.cc) -x objective-c++-header $< -o $@
endif
$(CNV):; make -C cnv
%.bin: $(TONEDIR)/%.dat
	mono $(CNV) $< $@
$(TARGET_MPW): $(SRC68K) $(SRC68K:.mm=.h) $(TONES)
	mkdir -p $@/obj
	perl t2r $(TONES) > $@/tone.r
	cp -p 68k/* types.h $@/
	for file in $(SRC68K:.mm=.h); do \
		sed -e 's/std:://g' $$file >$@/$$file; \
	done
	for file in $(SRC68K); do \
		dst=`echo $$file | sed -e 's/mm$$/cpp/'`; \
		sed -e 's/std:://g' $$file >$@/$$dst; \
	done
	touch $@
$(TARGET_VS): $(SRCWIN) $(SRCWIN:.mm=.h) $(TONES)
	mkdir -p $@
	cp -p $(TONES) $@/
	cp -p win/* $(SRCWIN:.mm=.h) $@/
	for file in $(SRCWIN); do \
		dst=`echo $$file | sed -e 's/mm$$/cpp/'`; \
		cp -p $$file $@/$$dst; \
	done
	cp -p main.mm $@/main.cpp
	touch $@
$(TARGET_RASPI): fm_raspi
fm_raspi: $(SRCRASPI) $(SRCRASPI:.mm=.h) $(TONES)
	mkdir -p $@
	cp -p $(TONES) types.h $@/
	cp -p linux/* $(SRCRASPI:.mm=.h) $@/
	for file in $(SRCRASPI); do \
		dst=`echo $$file | sed -e 's/mm$$/cpp/'`; \
		cp -p $$file $@/$$dst; \
	done
	cp -p main.mm $@/main.cpp
	touch $@
	tar cf fm_raspi.tar $@

$(DEPEND):; $(CXX) $(CXXFLAGS) -MM $(OBJS:.o=.mm) > $(DEPEND)
clean:
	rm -f *.o $(DEPEND) $(PCH) $(CNV) *.bin fm_raspi.tar
	rm -fr $(TARGET_MPW) $(TARGET_VS) fm_raspi
	rm -f *.air *.metal-ar *.metallib
-include $(DEPEND)
