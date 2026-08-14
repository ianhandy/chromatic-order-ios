# Chapter 10: Circuitry (levels 141-160)
SHAPES = [
    ("Antenna", """
.aa+aaaa.
...m.....
..b+bbb..
...m.....
...+cc...
.e.m.f...
.e.m.f...
.+g+g+g..
""", "Start with the longest run, then work outward from the cells it fixes."),

    ("Fuse", """
gg+..+hhhh
.ba..d.f..
.++kk+k+..
.ba..d.f..
.b.....f..
.b.....f..
""", None),

    ("Switch", """
...w......
...w......
..b+b+bb..
.....p....
..q..p....
uu+..+ttt.
..q..p....
.r+rr+rrrr
""", None),

    ("Battery", """
a........h
a.b...d..h
a.b.c.d.eh
+w+w+w+w++
..b.c.d.e.
..b.c.d.e.
..b...d...
""", None),

    ("Resistor", """
..+c+ccc+..
aa+.f...+bb
..d.f.h.e..
..d.f.h.e..
..+ggg+g+..
""", "When one placement forces a neighbour, follow that chain as far as it goes before starting somewhere new."),

    ("Capacitor", """
....a.b...
....a.b...
c+cc+.+d+d
.e..a.b.f.
.e..a.b.f.
.+h++h+h+.
.e.g..b.f.
...g......
""", None),

    ("Plug", """
..a..b..
..a..b..
.++cc+c+
.d.....e
.d.g...e
.+f+fff+
.d.g...e
...+hhh.
""", None),

    ("Relay", """
..+eeee+e.
aa+aaa.f..
bb+bbb.f..
..d....+gg
cc+ccc.f..
..d....+hh
..d.......
""", None),

    ("Speaker", """
+c+cccc+
a.e....b
+f+ff..b
a.e..g.b
a...h+h+
a....g.b
+dddd+d+
""", None),

    ("Transformer", """
..+f++ff+..
hh+.cd..b..
..a.++e.b..
..a.cd..b..
..a.cd..+ii
..a.cd..b..
..+g+ggg+..
""", None),

    ("Heatsink", """
..a.b.c.d..
..+e+e+e+e.
.ga.b.c.d..
.ga.b.c.d..
.++++f+f++f
...h.....i.
...h.....i.
""", None),

    ("Satellite", """
.....i.....
....+++g...
....eif....
aaaa+i+cccc
bbbb+.+dddd
...h+h+....
""", None),

    ("Radar Dish", """
b...d...c
beee+eee+
+aaa++aa+
.....f...
.....f...
..g+g+g+.
...h.f.i.
...h.f.i.
""", None),

    ("Junction Box", """
....e......
..+a+aaa+..
..c...h.d..
ff+.ii+id..
..c...h.+gg
..c...h.d..
..+bbb+b+..
""", None),

    ("Patch Bay", """
h......i
++a+a+a+
hc.d.e.i
hc.d.e.i
++b+b+b+
.+f+fe..
.....+gg
""", None),

    ("Server Rack", """
+a+aaaa+
d.f....e
+b+b+bb+
d.f.g..e
d...ghje
d....hje
+cccc+++
""", None),

    ("Microchip", """
..+e+eee+..
aa+.i...h..
bb+.i.j.+cc
..g...j.+dd
..+fff+f+..
""", "Leave the short runs for last, once the long ones have pinned their neighbours."),

    ("Power Strip", """
...f.......
..+++a+a+a+
..cfg.h.i.d
ee+fg.h.i.d
..+bb+bbbb+
.....j....d
.....j.....
""", None),

    ("Oscilloscope", """
++aaa+..
cg..f+hh
++ee+d..
cg..fd..
c...f+ii
+bbb++..
+jjjj+j.
""", None),

    ("Motherboard", """
......j+jj.
.......+e+e
.a.b.c.gih.
.a.b.c.+++f
.a.b.c..ih.
d+d+d+dd+dd
""", None),
]
