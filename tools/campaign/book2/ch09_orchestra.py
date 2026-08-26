# Chapter 9: Orchestra (levels 121-140)
#
# Instruments and the gear that stands around them. Gradient counts climb
# from seven to nine across the chapter. Every run here is asymmetric in
# its crossings, so no stroke can be laid down backwards.

SHAPES = [
    # ── 121-127: seven gradients ──────────────────────────────────
    ("Metronome", """
..a....
.g+gg..
..a....
+b+bbb+
c.....d
c...e.d
c...e.d
+fff+f+
""", "Two runs span the whole board. Pin those and the short ones have nowhere left to go."),

    ("Music Stand", """
aa+aaaa
..b....
cc+cccc
..b....
.g+g+..
d.b.e..
d.b.e..
+f+f+ff
""", None),

    ("Music Note", """
...+aa
...c..
...+bb
...c..
g..c..
+dd+d.
g..c..
+hh+h.
g..c..
+ee+e.
""", None),

    ("Cymbal", """
.aaa+aaaa.
....c.....
bbbb+bbbbb
....c.....
...g+gg...
....c.....
..d.c.e...
..d.c.e...
..+f+f+f..
""", None),

    ("Flute", """
..d..e...f..
+a+aa+aaa+a+
g.d..e...f.h
+b+bb+bbb+b+
g..........h
""", None),

    ("Trumpet", """
...d.e..f.g
+aa+a+aa+a+
c..d.e..f.g
+bb+b+bb+b+
c.........g
..........g
""", None),

    ("Harp", """
+a+a+a+a+a+
g.b.c.d.e.h
g.b.c.d.e.h
g.b.c.d.e..
g.b.c.d....
g.b.c......
..b........
""", None),

    # ── 128-135: eight gradients ──────────────────────────────────
    ("Microphone", """
.+aaa+a
.b...c.
.+fff+f
.b...c.
.++d++d
..k.l..
..+m+m.
..k.l..
""", "Pick a crossing and settle both runs through it before moving on."),

    ("Xylophone", """
a..........
a...b......
a...b.c....
a...b.c.d..
+f+f+f+f+f+
a.k.b.c.d.m
+h+h+h+h+h+
..k.......m
""", None),

    ("Accordion", """
+a+a+a+a
c.d.e.g.
c.d.+j+j
c.d.e.g.
c.d.+k+k
c.d.e.g.
+b+b+b+b
c.d.e.g.
""", None),

    ("Amplifier", """
+aaa+aaa+a
b...j...c.
+h+h+h+h+h
b.d.j.e.c.
b.d...e.c.
+g+ggg+g+g
""", None),

    ("Guitar", """
ee+e..
..f...
b.f.c.
+a+a+a
b.f.c.
+h+h+.
b...c.
+ggg+.
b...c.
+ddd+d
""", None),

    ("Cello", """
.a+aa
..b
..b
+c+cc+c
d.b..e.
+j+jj+.
d....e.
+gggg+g
d....e.
+ffff+f
""", None),

    ("Banjo", """
+a+aa+
b.k..+jj+
b.k..c..g
+f+ff+ff+
b.k..c..g
b.k..c..g
+d+dd+
""", None),

    ("Trombone", """
.........d
+a+a+aa+a+
c.k.e..h.d
+j+j+..h.d
c.k.e..h.d
+b+b+bb+b+
c.k.e..h.d
.........d
""", None),

    # ── 136-140: nine gradients ───────────────────────────────────
    ("Violin Case", """
..+aa+aa
..b..c..
+d+dd+d+
e.b..c.f
+n+n++n+
e...m..f
+jjj+jj+
....m...
""", "With this many ramps in play, finish one completely before you start the next."),

    ("Saxophone", """
aa+a....
..b.....
..+cc...
..b.....
..+ddd..
..b.....
..+ee..j
..b....j
..+fff.j
..b....j
.g+gggg+
..b....j
....hhh+
""", None),

    ("Bagpipes", """
..b.c..h..
e.b.c..h.f
+a+a+aa+a+
e........f
+mmmm+mmm+
e....g...f
+dddd+ddd+
.....g....
.....g....
""", None),

    ("Tuba", """
a+a+a+aa
.f.g.h..
.+b+b+b.
.f.g.h..
.f.+k+k+
.f.g.h.j
.+e+e+.j
.f.g.h.j
.+d+d+d.
""", None),

    ("Piano", """
+g+g+gg+g+
a.b.c..d.e
a.b.c..d.e
.f....h
.f....h
j+jjjj+jjj
""", None),
]
