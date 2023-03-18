using System;
using System.Collections.Generic;

class Binary : List<int>, IDisposable {
	public Binary() {
		parent = to;
		to = this;
	}
	public void Dispose() {
		Release();
		if (to != null && Count > 0) {
			to.AddRange(this);
			Clear();
		}
	}
	public void Release() {
		if (to == this) to = parent;
	}
	public void put1(int v) {
		Add(v & 0xff);
	}
	public void put2(int v) {
		Add(v & 0xff);
		Add(v >> 8 & 0xff);
	}
	public void put2(int index, int v) {
		this[index] = v & 0xff;
		this[index + 1] = v >> 8 & 0xff;
	}
	public int get2(int index) {
		return this[index] | this[index + 1] << 8;
	}
	public void offset2() {
		for (int i = 0; i < Count; i += 2) 
			put2(i, Count + get2(i));
	}
	Binary parent;
	public static Binary to;
}
