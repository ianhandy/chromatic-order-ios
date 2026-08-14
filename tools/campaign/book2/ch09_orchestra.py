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
bb+bbbb
c.....d
c...e.d
c...e.d
+fff+f+
""", "Place the longest run first, then work outward from the cells it fixes."),

    ("Music Stand", """
aa+aaaa
..b....
cc+cccc
.g+gg..
d.b.e..
d.b.e..
+f+f+ff
""", None),

    ("Music Note", """
...+aa
...+bb
...c
g..c
+dd+d
+hh+h
+ee+e
""", None),

    ("Cymbal", """
.aaa+aaaa.
bbbb+bbbbb
...g+gg...
....c.....
..d.c.e...
..d.c.e...
..+f+f+f..
""", None),

    ("Flute", """
..d..e...f.
+a+aa+aaa++
+b+bb+bbb++
g.........h
""", None),

    ("Trumpet", """
...d.e..f.g
+aa+a+aa+a+
+bb+b+bb+b+
c.........g
..........g
""", None),

    ("Harp", """
++a+a+a+a+
gb.c.d.e.h
gb.c.d.e.h
gb.c.d.e..
gb.c.d....
gb.c......
.b........
""", None),

    # ── 128-135: eight gradients ──────────────────────────────────
    ("Microphone", """
.+aaa+a
.b...c.
.+fff+f
.++d++d
..k.l..
..+m+m.
..k.l..
""", "Pick a crossing and settle both runs through it before moving on."),

    ("Xylophone", """
a........
a.b......
a.b.c....
a.b.c.d..
+++f+f+f+
+++h+h+h+
.k......m
""", None),

    ("Accordion", """
+a+a+a+a
c.d.+j+j
c.d.+k+k
+b+b+b+b
c.d.e.g
""", None),

    ("Amplifier", """
+aa+a+a
b..j.c
+hh+h+h
b.djec
b.d.ec
+g+g++g
""", None),

    ("Guitar", """
ee+e..
..f...
b.f.c.
+a+a+a
bh+h+.
+gggc.
+ddd+d
""", None),

    ("Cello", """
.a+aa
..b
..b
+c+cc+c
dj+jje
+gggg+g
+ffff+f
""", None),

    ("Banjo", """
+a+aa+
b.k..cjj+
+f+ff+ff+
b.k..c..g
b.k..c..g
+d+dd+
""", None),

    ("Trombone", """
.........d
+a+a+aa+a+
+j+je..h.d
+b+b+bb+b+
c.k.e..h.d
.........d
""", None),

    # ── 136-140: nine gradients ───────────────────────────────────
    ("Violin Case", """
..+aa+a
..b..c
+d+dd++
+n+n+++
e...m.f
+jjj+j+
....m
""", "With this many ramps in play, finish one completely before you start the next."),

    ("Saxophone", """
aa+a
..+cc
..+ddd
..+ee..j
..+fff.j
.g+gggg+
..bhhhh+
""", None),

    ("Bagpipes", """
.b.c..h
eb.c..hf
++a+aa++
+mmm+mm+
+ddd+dd+
....g
....g
""", None),

    ("Tuba", """
a+a+a+aa
.+b+b+b.
.f.gk+k+
.+e+eh.j
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
