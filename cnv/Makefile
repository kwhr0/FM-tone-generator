MCS = mcs	# current Mono for Intel
#MCS = gmcs	# old Mono for PowerPC

SRCS = base.cs binary.cs cnv.cs
cnv.exe: $(SRCS)
	$(MCS) -out:$@ $(SRCS)
