# Chapter 12: Grand Works (levels 181-200)
SHAPES = [
    ("Refinery", """
...+hh+h...
...a..d....
.+e+ee+....
.c.a..d..b.
.+i+i.d..b.
.c.a..d..b.
.+f+ff+ff+.
.c.a..d..b.
.+g+gg+gg+g
""", "The widest run reaches almost every vertical. Place it and the rest lose most of their freedom."),

    ("Dam", """
a+a+a+a+aa
.b.c.d.e..
g+g+g+g+..
.b.c.d.e..
.b.c.d.e..
h+++h+++hh
..i...j...
..+kkk+k..
..i...j...
""", None),

    ("Drydock", """
aa+a...b+bb
..c.....d..
.g+g+g+g+..
..c.e.f.d..
..c.+i+.d..
..c.e.f.d..
..+h+h+h+h.
""", None),

    ("Water Tower", """
.a+aaaaa+..
..c.....d..
..+bb+bb+b.
..c..e..d.j
..c.g+gg+.j
..c..e..d.j
ii+ii+ii+..
""", None),

    ("Foundry", """
..a....b..
.c+cc.d+dd
..a....b..
..a....b.i
+e++eee+e+
f..g.....i
+kk+k....i
f..g.....i
+jj+jjjjj+
""", None),

    ("Gantry", """
...b+bb+b+
....c..d.j
aa+a+aa+a+
..e.c..d.j
..+f+ff+.j
..e.c..d..
.i+i+..d..
..e.+gg+g.
....c..d..
..........
..hhhhhhhh
""", None),

    ("Lock Gate", """
a+a+a+a+a
.h.c.d.i.
.+e+.+g+.
.h.c.d.i.
.h.+f+.i.
.h.c.d.i.
.+j+.d.i.
.h.c.d.i.
b+b+b+b+b
""", None),

    ("Silos", """
..g+g+gg+
...c.d..e
a+a+a+aa+
.b.c.d..e
.b.c.d..e
.b.+k+kk+
.b.c.d..e
i+i+i+ii+
""", None),

    ("Shipyard", """
..+aa......
..c..bbb+..
..c.....d..
...j.k.l...
eee+e+e+e..
...j.k.l...
.mm+m+m+m..
...j.k.l...
..n+n+n+...
.......+ooo
""", None),

    ("Spire", """
....a....
...b+bb..
....a....
..+c+c+c.
..d...e..
.f+f+f+f+
k.d.g.e.l
+h+h+h+h+
""", None),

    ("Terminal", """
..aaaaaa..
..........
+b+b+bb+b+
c.n.d..e.f
+g+g+..e.f
c.n.+hh+h+
c.n.d..e.f
+i+i+ii+i+
""", None),

    ("Telescope", """
a+a+aa+a+.
.b.d..e.c.
f+f+ff+f+.
.b.d..e.c.
...d..e...
...d..e...
...+gg+ggg
""", None),

    ("Smelter", """
.a........
b+bb......
.a..k....h
.+cc++c+c+
.a...e.f.h
.a..i+i+i+
.a...e.f.h
g+ggg+g+g+
""", None),

    ("Derrick", """
...+a+a..
...b.c...
..d+d+...
.f.b.c.g.
.+e+++e+e
.f..i..g.
h+hh+hh+.
.f..i..g.
.+jj+jj+j
""", None),

    ("Powerhouse", """
..a.b......
.l+l+..c...
..a.b..c...
+d+++d++dd+
e..h..i...f
+kk+kk+kkk+
e..h..i...f
""", None),

    ("Engine Shed", """
..aaaaa...
..........
+d+dd+d+d+
e.h..i.j.f
+g+gg+.j.f
e.h..i.j.f
e.h..i.j.f
+l+ll+l+l+
""", "Where two runs meet, the shared cell has to satisfy both, so let it steer the pair."),

    ("Kiln", """
...aaaa.
..d.....
.i+iii+.
..d...g.
..+m+m+m
..d.l.g.
jj+j+j+j
....l.g.
kkkk+k+k
""", None),

    ("Breakwater", """
...e.ll+l+l
...e...g.h.
a+a+a+a+a+.
.d.e.f.g.h.
b+b+b+b+b+.
.d...f.....
....n+nnn..
""", None),

    ("Scaffold", """
.e..f..g
.+aa+aa+
.e..f..g
.+bb+bb+
.e..f..g
.+cc+cc+
.e..f..g
.+dd+dd+
""", None),

    ("Ironworks", """
.a.........
.a....mm+m.
.a..f...b..
++ee+ee++e+
h...f..j..g
+iii+ii+i.g
h...f..j...
""", "Two hundred boards. Take this one slowly, and finish it the way you like."),
]
