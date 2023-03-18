#include "types.h"

struct Drum;
class GPManager;
class Channel8;

typedef std::list<Channel8 *> ChannelList;

class ChannelManager {
public:
	ChannelManager(int n);
	virtual ~ChannelManager();
	virtual Channel8 *KeyOn(u8 &prog, u8 &note, u8 velo, u8 vol, u8 exp, u8 pan, s16 bend, u16 id);
	void KeyOff(u16 id);
	void KeyOffAll();
	virtual void Clear();
	void SetPan(u8 id_low, u8 pan);
	void SetVolExp(u8 id_low, u8 vol, u8 exp);
	void Bend(u8 id_low, s16 bend);
	void StartEnum() { sharedI = active.begin(); }
	bool Update1(s32 *buf, int numSamples);
	void Update(s32 *buf, int numSamples);
	void Poll();
	int GetChN() const { return chN; }
	int GetCountA() const { return cntA; }
	int GetCountR() const { return cntR; }
	int GetTotalCount() const { return cntTotal; }
	void ClearCount() { cntA = cntR = cntTotal = 0; }
	float ActiveRatio() const { return float(active.size()) / chN; }
	static void AppendDrumData(Drum *d) { drumData.push_back(d); }
	static void SetDrumBank(int b) { drumBank = b; }
protected:
	ChannelList active;
	int chN, cntA, cntR, cntTotal;
	ChannelList::iterator sharedI;
#ifdef MULTI_THREAD
	pthread_mutex_t mutex;
#endif
	GPManager *gpm;
	static std::vector<Drum *> drumData;
	static int drumBank;
};

extern ChannelManager *gMan;
