# Chapter 12: Grand Works (levels 181-200)
SHAPES = [
    ("Refinery", """
...+hh+h...
.+e+ee+....
.c.a..d..b.
.+i+i.d..b.
.cf+ff+ff+.
.c.a..d..b.
.+g+gg+gg+g
""", "Place the longest run first, then work outward from the cells it fixes."),

    ("Dam", """
a+a+a+a+aa
g+g+g+g+..
.b.c.d.e..
.b.c.d.e..
h+++h+++hh
..+kkk+k..
..i...j...
""", None),

    ("Drydock", """
aa+a...b+bb
..c.....d..
.g+g+g+g+..
..c.+j+jd..
..ci+i+.d..
..c.e.f.d..
..+h+h+h+h.
""", None),

    ("Water Tower", """
.a+aaaaa+..
..+kkk..d..
..+bb+bb+b.
..c..e..d.j
..cgg+gg+.j
..c.h+hh+h+
ii+ii+ii+..
""", None),

    ("Foundry", """
..a....b..
.c+cc.d+dd
..a....b..
..a....b.i
+ee+eeeee+
f..g.....i
+kk+k....i
+jj+jjjjj+
""", None),

    ("Gantry", """
...b+bb+b+
aa+a+aa+a+
..e.c..d.j
..ef+ff+.j
.i+i+..d..
..e.+gg+g.
....c..d..
..hhhhhhhh
""", None),

    ("Lock Gate", """
a+a+aaa++a
f+f+...di.
.he+eee+i.
.hj+jj.di.
.h.c.gg++g
b+b+bbb++b
""", None),

    ("Silos", """
..g+g+gg+
a+a+a+aa+
.b.c.d..e
.b.ch+hh+
.b.+k+kk+
j+j+.d..e
i+i+i+ii+
""", None),

    ("Shipyard", """
..+aaaa....
..c..bbb+..
..c.....d..
..cj.k.ld..
eee+e+e+e..
.mm+m+m+m..
..n+n+n+...
...oo+ooooo
""", None),

    ("Spire", """
.....a....
....b+bb..
.....a....
...+c+c+c.
...d...e..
..f+f+f+ff
.k.d.g.e.l
.+hhhhhhhl
""", None),

    ("Terminal", """
..aaa+aa...
.+bb++b+b+.
.cn.dm.e.f.
.++g+g.e.f.
.cn.dhh+h+.
.cn.d..e.f.
.++i+ii+i+.
""", None),

    ("Telescope", """
.a+a+aa+a+.
..b.djj+j+.
.f+f++f+f+.
..bi++i+ic.
....dh.e...
....d.k+kkk
....+gg+ggg
""", None),

    ("Smelter", """
.a.........
b+bb.......
.a..k....h.
.+cc++c+c+.
.a..ke.f.h.
.a..++i+i+.
d+dd.+j+jh.
g+ggg+g+g+.
""", None),

    ("Derrick", """
...+a++..
...b.ck..
..d+d+k..
.f.b.c.g.
.+e+e+e+e
.f.bic.g.
h+hh+hh+.
.f..i..g.
.+jj+jj+j
""", None),

    ("Powerhouse", """
..a.b......
.l+l+..c...
..a.b..c...
+d+d+d++dd+
e..h..i...f
+kk+kk+kkk+
+jj+jj+jjj+
""", None),

    ("Engine Shed", """
..a+aa+..
+dd+dd+d+
e.hb.icjf
+g+gg+.jf
e.h..i.jf
e.h..+m++
+l+ll+l++
""", "Where two runs meet, the shared cell has to satisfy both, so let it steer the pair."),

    ("Kiln", """
...+a+a.
..dc.f..
.i++i++.
..dc.fg.
..+mmm+m
.ed.l.gh
j++j+j++
.e..l.gh
k+kk+kk+
""", None),

    ("Breakwater", """
.......kk+k
...e.ll+l+l
a+a+a+a+a+.
.dm+m+.g.h.
b+b+b+b+b+.
.+jjjf.....
....n+nnn..
""", None),

    ("Scaffold", """
.e.lf..g
.+a++aa+
.ei++..g
.+b++bb+
.e..++j+
.+cc++c+
k+kkfm.g
.+dd++d+
""", None),

    ("Ironworks", """
.a.........
.a....mm+m.
.+ccf...b..
++ee+eee+e+
hlll+..jb.g
+iii+ii+i.g
+kkk+kk+...
""", "Two hundred boards. Take this one slowly, and finish it the way you like."),
]
