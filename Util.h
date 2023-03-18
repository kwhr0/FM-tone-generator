template <int ID = 0> struct MeasureTime {
	MeasureTime() {
		start = now();
	}
	~MeasureTime() {
		total += duration = now() - start;
		count++;
	}
	double now() {
		struct timeval t;
		gettimeofday(&t, NULL);
		return t.tv_sec + 1e-6 * t.tv_usec;
	}
	static void Print(double period) {
		double a = total / count;
		printf("average<%d>=%.3fmS (%.0f%%)\n", ID, 1000. * a, 100. * a / period);
	}
	double start;
	static double duration, total;
	static int count;
};

template<int ID> double MeasureTime<ID>::duration;
template<int ID> double MeasureTime<ID>::total;
template<int ID> int MeasureTime<ID>::count;
