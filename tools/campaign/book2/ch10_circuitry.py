# Chapter 10: Circuitry (levels 141-160)
SHAPES = [
    ("Antenna", """
.aa+aaaa.
...m.....
..b+bbb..
...m.....
...+c+...
.e.m.f...
.e.m.f...
.+g+g+g..
""", "Every crossing belongs to two runs at once. Solve one and you have solved a cell in both."),

    ("Fuse", """
g+g+..+h+hh
.b.a..d.f..
.+k+kk+k+..
.b.a..d.f..
.b......f..
.b......f..
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
a.b.c.d..h
+w+w+w+w++
..b.c.d.e.
..b.c.d.e.
..b...d...
""", None),

    ("Resistor", """
..+c+ccc+..
aa+.f...+bb
..d.f.h.e..
..d...h.e..
..+ggg+g+..
""", "When one placement forces a neighbor, follow that chain as far as it goes before starting somewhere new."),

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
..+eeee...
..d....f..
aa+aaa.f..
..d....f..
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
..+f+f+ff+..
hh+.c.d..b..
..a.+e+e.b..
..a.c.d..b..
..a.c.d..+ii
..a.c....b..
..+g+gggg+..
""", None),

    ("Heatsink", """
..a.b.c.d..
..+e+e+e+e.
g.a.b.c.d..
g.a.b.c.d..
+f+++f+f++f
...h.....i.
...h.....i.
""", None),

    ("Satellite", """
....+gg.+j...
....e...f....
aaaa+.i.+cccc
....e.i.f....
bbbb+...+dddd
....e...f....
..kk+...+hh..
""", None),

    ("Radar Dish", """
b...d...c
+eee+eee+
b...d...c
+aaa++aa+
.....f...
.....f...
..g+g+g+.
...h.f.i.
...h.f.i.
""", None),

    ("Junction Box", """
....e......
..+a+a+a+..
..c...h.d..
ff+.ii+i+..
..c...h.+gg
..c...h.d..
..+bbb+b+..
""", None),

    ("Patch Bay", """
h.......i
+a+a+a+a+
h.c.d.e.i
h.c.d.e.i
+b+b+b+b+
..c.d.e..
..+f+f+..
......+gg
""", None),

    ("Server Rack", """
+a+aaaaaaa+
d.f.......e
+b+b+bbbbb+
d.f.g.....e
d...g.h.j.e
d.....h.j.e
+ccccc+c+c+
""", None),

    ("Microchip", """
..+e+eee+..
aa+.i...h..
..g.i...h..
bb+.i.j.+cc
..g...j.h..
..g...j.+dd
..+fff+f+..
""", "Leave the short runs for last, once the long ones have pinned their neighbors."),

    ("Power Strip", """
.....f........
...+a+a+......
...c.f.g.h.i.d
ee.c.f.g.h.i.d
.........h.i.d
...bbbbb++b+b+
........j.....
........j.....
""", None),

    ("Oscilloscope", """
+a+aa+a+..
c.g..f.+hh
+e+ee+.d..
c.g..f.d..
c....f.+ii
+bbbb+b+..
c......d..
+jjjjjj+j.
""", None),

    ("Motherboard", """
ee......jjjj.
.............
.............
.a.b.c.g.i.h.
.a.b.c.+f+f+f
.a.b.c...i.h.
d+d+d+ddd+d+d
""", None),
]
