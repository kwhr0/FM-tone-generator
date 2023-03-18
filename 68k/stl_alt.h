#ifndef _STL_ALT_H_
#define _STL_ALT_H_

namespace std {

template <class T> struct vector {
	enum { N = 100 }; // this vector has limit
	struct iterator {
		iterator() {}
		iterator(T *_p) : p(_p) {}
		operator T *() { return p; }
		iterator &operator++() { ++p; return *this; }
		T *p;
	};
	vector() : c((T *)NewPtrClear(sizeof(T) * N)), s(0) {}
	void push_back(T &t) { if (s < N) c[s++] = t; }
	int size() const { return s; }
	void clear() { s = 0; }
	T &operator[](int index) { return c[index]; }
	T *begin() { return c; }
	T *end() { return &c[s]; }
	T *c;
	int s;
};

template <class T> struct list {
	struct elm {
		elm *next, *prev;
		T c;
	};
	struct iterator {
		iterator() {}
		iterator(elm *_p) : p(_p) {}
		operator elm *() { return p; }
		T &operator*() { return p->c; }
		iterator &operator++() { p = p->next; return *this; }
		elm *p;
	};
	struct reverse_iterator {
		reverse_iterator() {}
		reverse_iterator(elm *_p) : p(_p), b(0) {}
		operator elm *() { return p; }
		T &operator*() { return p->c; }
		reverse_iterator &operator++() { b = p, p = p->prev; return *this; }
		iterator base() { return b; }
		elm *p, *b;
	};
	list() : f(0), b(0) {}
	int size() {
		int r = 0;
		for (iterator i = begin(); i != end(); ++i) ++r;
		return r;
	}
	void clear() {
		for (iterator i = begin(); i != end(); ++i) delete i.p;
		f = b = 0;
	}
	iterator erase(iterator &i) {
		elm *p = i.p->prev;
		if (p) p->next = i.p->next;
		else f = i.p->next;
		p = i.p->next;
		if (p) p->prev = i.p->prev;
		else b = i.p->prev;
		delete i.p;
		return p;
	}
	elm *begin() { return f; }
	elm *end() { return 0; }
	elm *rbegin() { return b; }
	elm *rend() { return 0; }
	T &back() { return b->c; }
	void pop_back() {
		if (b) {
			elm *p = b;
			b = b->prev;
			if (b) b->next = 0;
			else f = 0;
			delete p;
		}
	}
	void insert(iterator &i, T &t) {
		elm *p = new elm;
		p->c = t;
		if (i.p) {
			p->next = i.p;
			p->prev = i.p->prev;
			i.p->prev = p;
			if (p->prev) p->prev->next = p;
			else f = p;
		}
		else {
			if (b) b->next = p;
			p->next = 0;
			p->prev = b;
			b = p;
			if (!f) f = p;
		}
	}
	elm *f, *b;
};

}

#endif
