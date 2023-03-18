using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

class Op : Base {
	public class Param {
		public Param() {
			Mul = Ml = Dl = Sl = 1.0;
			St = -1.0;
			Rt1 = 0.1;
		}
		public Param Clone() { return (Param)MemberwiseClone(); }
		void putt(double x) {
			if (x >= 0.0) {
				int sample = (int)(44100.0 * x);
				if (sample == 0) sample = 1;
				int delta = (int)((1 << 24 - 3) / sample);
				if (delta == 0) delta = 1;
				delta = (int)(16.0 * Math.Log(delta) / Math.Log(2.0));
				put1(delta < 1 ? 1 : delta > 255 ? 255 : delta);
			}
			else put1(0);
		}
		void putl(double x) {
			int v = (int)(256.0 * x);
			put1(v < 0 ? 0 : v > 255 ? 255 : v);
		}
		public void Dump() {
			int v = (int)(512.0 * Mul);
			put2(v > 0xffff ? 0xffff : v); // 0.002 - 127
			put2((int)(256.0 * Ml)); // 0.004 - 255
			put1(Con);
			put1((int)(128.0 * Vs));
			put1((int)(256.0 * Ph));
			v = (int)(128.0 * Det);
			put1(v < -128 ? -128 : v > 127 ? 127 : v);
			putt(At1);
			putt(At2);
			putt(Dt1);
			putt(Dt2);
			putt(St);
			putt(Rt1);
			putt(Rt2);
			putt(Ht);
			putl(Al);
			putl(Tl);
			putl(Dl);
			putl(Sl);
			putl(Rl);
			put1(0);
		}
		public int Con { get; set; }
		public double Mul { get; set; }
		public double Det { get; set; }
		public double Ml { get; set; }
		public double Vs { get; set; }
		public double Ph { get; set; }
		public double Ht { get; set; }
		public double At { set { At2 = value; } }
		public double At1 { get; set; }
		public double At2 { get; set; }
		public double Dt { set { Dt2 = value; } }
		public double Dt1 { get; set; }
		public double Dt2 { get; set; }
		public double St { get; set; }
		public double Rt { set { Rt1 = value; } }
		public double Rt1 { get; set; }
		public double Rt2 { get; set; }
		public double Il { get; set; }
		public double Al { get; set; }
		public double Tl { get; set; }
		public double Dl { get; set; }
		public double Sl { get; set; }
		public double Rl { get; set; }
	}
	public void parse(int _index) {
		index = _index;
		parsesub();
	}
	protected override bool parse1(string keyword) {
		if (keyword == "Con") param_def.Con = getint2();
		else {
			var pi = typeof(Param).GetProperty(keyword);
			if (pi == null) return false;
			double v = getdouble2();
			if (index >= 0) {
				if (index == param.Count) param.Add(param_def.Clone());
				pi.SetValue(param[index], v, null);
			}
			else pi.SetValue(param_def, v, null);
		}
		return true;
	}
	public void Dump(int n) {
		foreach (Param p in param) p.Dump();
		for (n -= param.Count; n > 0; n--) param_def.Dump();
	}
	public int Con {
		get { return param_def.Con; }
		set {
			param_def.Con = value;
			foreach (Param p in param) p.Con = value;
		}
	}
	int index = -1;
	public List<Param> param = new List<Param>();
	Param param_def = new Param();
}

class Sec : Base {
	public int parse(Op[] _op, int _index) {
		op = _op;
		index = _index;
		parsesub();
		return sc;
	}
	protected override bool parse1(string keyword) {
		if (keyword == "Sc") sc = getint2();
		else if (keyword == "Op") op[getint3()].parse(index);
		else return false;
		return true;
	}
	int sc, index;
	Op[] op;
}

class Lfo : Base {
	protected override bool parse1(string keyword) {
		var pi = typeof(Lfo).GetProperty(keyword);
		if (pi == null) return false;
		pi.SetValue(this, getdouble2(), null);
		return true;
	}
	void put(int x) {
		put1(x < 0 ? 0 : x > 255 ? 255 : x);
	}
	void putlog(double v) {
		put1(v > 0.0001 ? (int)(-16.0 * Math.Log(v) / Math.Log(2.0)) : 255);
	}
	public void Dump() {
		putlog(Dpt * Amd);
		putlog(Dpt * Pmd / 24.0);
		int t = (int)((1 << 20) * Spd / 44100.0);
		put(t);
		t = (int)(128.0 * Dly);
		put(t);
	}
	public double Dly { get; set; }
	public double Spd { get; set; }
	public double Dpt { get; set; }
	public double Pmd { get; set; }
	public double Amd { get; set; }
}

class Tone : Base {
	public override void parse() {
		num = getint3();
		parsesub();
		Dump();
	}
	protected override bool parse1(string keyword) {
		int i, n;
		switch (keyword) {
		case "Con":
			con = getint2();
			break;
		case "On":
			n = getint2();
			op = new Op[n];
			for (i = 0; i < n; i++) op[i] = new Op();
			break;
		case "Op":
			op[getint3()].parse(-1);
			break;
		case "Sn":
			n = getint2();
			sc = new int[n];
			break;
		case "Sec":
			i = getint3();
			sc[i] = new Sec().parse(op, i);
			break;
		case "Lfo":
			lfo.parse();
			break;
		case "Perc":
			perc = getint2();
			break;
		case "Fzl": case "Fza":
			getdouble2();
			fz = 1;
			break;
		case "Ss":
			getdouble2();
			ss = 1;
			break;
		case "Nz":
			getint2();
			nz = 1;
			break;
		case "Lpf": case "Nzh": case "Nzl":
			getdouble2();
			break;
		}
		return true;
	}
	void sort() {
		var map = new int[op.Length];
		var sorted = new List<Op>();
		for (int i = 0; sorted.Count < op.Length; i = i < op.Length - 1 ? i + 1 : 0) 
			if (!sorted.Contains(op[i]) && 
				op.Except(sorted).Where(p => p != op[i]).All(p => (p.Con & 1 << i) == 0)) {
				map[i] = 1 << sorted.Count;
				sorted.Add(op[i]);
			}
		op = sorted.ToArray();
		Func<int, int> remap = x => {
			int y = 0;
			for (int j = 0; j < op.Length; j++) 
				if ((x & 1 << j) != 0) y |= map[j];
			return y;
		};
		foreach (Op p in op) p.Con = remap(p.Con);
		con = remap(con);
	}
	public void Dump() {
		if (nz == 0) sort();
		put1(fz << 6 | nz << 5 | ss << 4 | perc << 3);
		put1(con);
		put1(op.Length);
		put1(0);
		lfo.Dump();
		int n = 4 + 4 + 1;
		if (sc != null) {
			put1(sc.Length);
			foreach (int t in sc) put1(t);
			n += sc.Length;
		}
		else put1(0);
		for (int i = 0; i < 16 - n; i++) put1(0);
		n = op.Select(p => p.param.Count).Max();
		foreach (Op p in op) p.Dump(n > 0 ? n : 1);
		if ((Binary.to.Count & 2) != 0) put2(0);
	}
	int con, perc, ss, fz, nz;
	Op[] op;
	Lfo lfo = new Lfo();
	int[] sc;
	public int num;
}

class Tonemap2 : Base {
	protected override bool parse1(string keyword) {
		if (keyword == "Tn") {
			getint2();
			return true;
		}
		return false;
	}
}

class Tonemap : Base {
	protected override bool parse1(string keyword) {
		if (keyword == "Tone") {
			getint3();
			new Tonemap2().parse();
			return true;
		}
		return false;
	}
}

class DrumNote : Base {
	protected override bool parse1(string keyword) {
		var pi = typeof(DrumNote).GetProperty(keyword);
		if (pi == null) return false;
		pi.SetValue(this, getint2(), null);
		return true;
	}
	public void Dump(int[] table) {
		if (Tn != 0 && Pan == 0) Pan = 64;
		put1(table[Tn]);
		put1(Sc);
		put1(Pan);
		put1(Alt);
	}
	public int Tn { get; set; }
	public int Sc { get; set; }
	public int Pan { get; set; }
	public int Alt { get; set; }
}

class DrumSet : Base {
	public DrumSet(int[] _table) {
		table = _table;
		for (int i = 0; i < 128; i++) drumnote[i] = new DrumNote();
	}
	public override void parse() {
		getint3();
		parsesub();
		foreach (DrumNote d in drumnote) d.Dump(table);
	}
	protected override bool parse1(string keyword) {
		if (keyword == "Note") {
			drumnote[getint3()].parse();
			return true;
		}
		return false;
	}
	DrumNote[] drumnote = new DrumNote[128];
	int[] table;
}

class Parse : Base {
	protected override bool parse1(string keyword) {
		switch (keyword) {
		case "tone":
			ofstable.put2(target.Count);
			Tone tone = new Tone();
			tone.parse();
			tonetable[tone.num] = tonecount++;
			break;
		case "tonemap":
			new Tonemap().parse();
			break;
		case "drumset":
			header.put2(target.Count);
			new DrumSet(tonetable).parse();
			break;
		default:
			getdouble();
			break;
		}
		return true;
	}
	public void top() {
		Binary magic = new Binary();
		using (header = new Binary()) {
			using (ofstable = new Binary()) {
				using (target = new Binary()) {
					header.put2(0);
					string s;
					while ((s = getword().ToLower()) != "") parse1(s);
					if ((ofstable.Count & 2) != 0) ofstable.put2(0);
					if (header.Count >= 4) 
						header.put2(2, header.get2(2) + ofstable.Count);
					ofstable.offset2();
				}
				header.offset2();
			}
			magic.put1('T');
			magic.put1('O');
			magic.put1('N');
			magic.put1('E');
		}
	}
	int tonecount;
	int[] tonetable = new int[256];
	Binary header, ofstable, target;
}

class cnv {
	public static void Main() {
		string[] argv = Environment.GetCommandLineArgs();
		if (argv.Length != 3) {
			Console.WriteLine("Usage: cnv <infile> <outfile>");
			Environment.Exit(1);
		}
		Base.Open(argv[1]);
		new Parse().top();
		Base.Dump(argv[2]);
	}
}
