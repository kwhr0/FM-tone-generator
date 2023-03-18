using System;
using System.IO;
using System.Text;

abstract class Base {
	const char EOF = '\xffff';
	protected static void fatal(string format, params object[] arg) {
		var s = new StringBuilder();
		s.AppendLine(line);
		s.AppendFormat("{0}({1}): ", filename, lineY);
		s.AppendFormat(format, arg);
		Console.WriteLine(s);
		Environment.Exit(1);
	}
	static char chkraw() {
		if (line == null) return EOF;
		while (lineX >= line.Length) {
			if ((line = reader.ReadLine()) == null) return EOF;
			lineX = 0;
			lineY++;
		}
		return line[lineX];
	}
	protected static char chkc() {
		if (line == null) return EOF;
		char c;
		int skipf = 0;
		do {
			while (lineX >= line.Length) {
				if ((line = reader.ReadLine()) == null) return EOF;
				lineX = 0;
				lineY++;
				if (skipf == 1) skipf = 0;
			}
			c = line[lineX++];
			if (lineX < line.Length) {
				char c2 = line[lineX];
				switch (skipf) {
					case 0:
					if (c == '/' && (c2 == '/' || c2 == '*')) {
						lineX++;
						skipf = c2 == '/' ? 1 : 2;
					}
					break;
					case 2:
					if (c == '*' && c2 == '/') {
						lineX++;
						skipf = 0;
						c = '\0';
					}
					break;
				}
			}
		} while (skipf != 0 || c <= ' ');
		return line[--lineX];
	}
	protected static char getraw() {
		char c = chkraw();
		if (c != EOF) lineX++;
		return c;
	}
	protected static char getc() {
		char c = chkc();
		if (c != EOF) lineX++;
		return c;
	}
	protected static void needc(char c) {
		if (getc() != c) fatal("needs '{0}'", c);
	}
	protected static int getint() {
		if (!Char.IsNumber(chkc())) return 0;
		var s = new StringBuilder();
		do s.Append(getraw());
		while (Char.IsNumber(chkraw()));
		return int.Parse(s.ToString());
	}
	protected static int getint2() {
		needc('(');
		int v = getint();
		needc(')');
		return v;
	}
	protected static int getint3() {
		needc('[');
		int v = getint();
		needc(']');
		return v;
	}
	protected static double getdouble() {
		char c = chkc();
		if (!Char.IsNumber(c) && c != '.' && c != '-') return 0.0;
		var s = new StringBuilder();
		do {
			s.Append(getraw());
			c = chkraw();
		}
		while (Char.IsNumber(c) || c == '.');
		return double.Parse(s.ToString());
	}
	protected static double getdouble2() {
		needc('(');
		double v = getdouble();
		needc(')');
		return v;
	}
	protected static string getword() {
		char c = chkc();
		if (!Char.IsLetter(c)) return "";
		var s = new StringBuilder();
		do {
			s.Append(getraw());
			c = chkraw();
		}
		while (Char.IsLetter(c) || Char.IsNumber(c));
		return s.ToString();
	}
	protected abstract bool parse1(string keyword);
	protected void parsesub() {
		needc('{');
		while (chkc() != '}') {
			string s = getword();
			if (s.Length > 0) {
				string t = char.ToUpper(s[0]) + s.ToLower().Substring(1);
				if (!parse1(t)) fatal("Illegal keyword \"{0}\"", t);
			}
			else fatal("needs keyword");
		}
		getc();
	}
	public virtual void parse() {
		parsesub();
	}
	protected static void put1(int v) {
		Binary.to.put1(v);
	}
	protected static void put2(int v) {
		Binary.to.put2(v);
	}
	public static void Open(string name) {
		filename = name;
		reader = new StreamReader(filename);
		line = "";
	}
	public static void Dump(string filename) {
		var fs = new FileStream(filename, FileMode.Create);
		var bw = new BinaryWriter(fs);
		foreach (int t in Binary.to) bw.Write((byte)t);
		bw.Close();
		fs.Close();
	}
	static StreamReader reader;
	static string filename, line;
	static int lineX, lineY;
}

