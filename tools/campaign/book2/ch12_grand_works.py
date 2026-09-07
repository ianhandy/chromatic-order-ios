# Grand Works (levels 201-220)
SHAPES = [
    ("Refinery", """
++gg
++eeee+ee
fh....d
+++ccc+cc
..b...d
..b...d
..b
..+aaaaaaa
""", "Start with the upper bridge. It pins the two towers before the pipework branches outward."),

    ("Dam", """
...c...g
...c...g
...c...g
+bb+...g
a..c.+f+
a..c.e
a..+d+
a..c.e
a..+h+hh
a..c.e
""", None),

    ("Drydock", """
....gg++
....e+++
..b..dhf
..b..dhf
..+cc+c+
..b..d
..b..d
..b..d
..b
aa+aaaaa
""", None),

    ("Water Tower", """
.hh+h+
...ag++
...a.if
+dd+..f
c..+ee+
c..a..f
c..a..f
+bb+bb+
...a
...a
""", None),

    ("Foundry", """
...bff+f
+hh+..e
g..b..e
g..b..e
+aa+a++a
...b.de
...b.de
...b.d
.cc+c+
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
....+f++
....+h++
+bbb+.eg
a...c.eg
a...c.e
a...c.e
a.dd+d+
a...c.e
a...c.e
a
""", None),

    ("Silos", """
...+aaaaaa
...b
...b
ccc+cc+c+c
......d.h
....+e+e+e
....f...h
gggg+...h
""", None),

    ("Shipyard", """
..+aa...d..
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
k........
""", None),

    ("Terminal", """
.........a
.........a
..bb+bbbb+
....c....a
ge..c....a
g+dd+ddd.a
++hhc....a
++ff+....a
""", None),

    ("Telescope", """
...+ccc+
h..d...b
h..d...b
+aa++aa+aa
hg..e..b
++i.e..b
.+ff+ff+
""", None),

    ("Smelter", """
.a........
b+bb......
.a..k....h
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
.+gg+
.h..a...c
.h..a...c
b+bb+bbb+
f...a...c
f...+ddd+
+eee+ee
f...a
""", None),

    ("Engine Shed", """
..+aaaaaaa
..b
..b...d
..b...d
+++ccc+cc
fh....d
++eeee+ee
++gg
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
g...c
g...c
g...c
g...+bb+
+f+.c..a
..e.c..a
..+d+..a
..e.c..a
hh+h+..a
..e.c..a
""", None),

    ("Scaffold", """
++gg
+++e
fhd..b
fhd..b
+c+cc+
..d..b
..d..b
..d..b
.....b
aaaaa+aa
""", None),

    ("Ironworks", """
.a.........
.a....mm+m.
.a..f...b..
++ee+ee++e+
h...f..j..g
+iii+ii+i.g
h...f..j...
""", "The final board. Take it slowly, and finish it the way you like."),
]
