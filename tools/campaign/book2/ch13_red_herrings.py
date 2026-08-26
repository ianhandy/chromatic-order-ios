# Chapter 13: Red Herrings (levels 201-220)
#
# The bank stops being a promise. Up to here every swatch handed to the
# player belonged in some cell, so "I have used everything" was a way of
# checking your own work. From here some swatches belong nowhere, and the
# only way to reject one is to prove no run can take it.
#
# The boards themselves step back from Grand Works' scale on purpose:
# the new demand is on the bank, not on the geometry, and stacking both
# would just make the chapter a wall. Shapes are open and legible so the
# player can see every run at once while they reason about the spares.
SHAPES = [
    ("Spare Rail", """
a+aaa+a
.b...c.
.b...c.
""", "One of these swatches fits nowhere. Find the runs first, then see what is left over."),

    ("Two Stacks", """
a+aa+a
.b..c.
.b..c.
.b..c.
""", None),

    ("Open Frame", """
+aaaaa+
b.....c
b.....c
+ddddd+
""", None),

    ("Tuning Fork", """
.a...b.
.a...b.
.+c+c+.
...d...
...d...
...d...
""", None),

    ("Bench", """
a+aaa+a
.b...c.
.b...c.
.b...c.
""", None),

    ("Ladder", """
a+aaa+a
.b...c.
.+ddd+.
.b...c.
.+eee+.
.b...c.
""", None),

    ("Crossbar", """
.a.b.
.a.b.
c+c+c
.a.b.
.a.b.
""", None),

    ("Twin Posts", """
+aaa+
b...c
b...c
b...c
+ddd+
""", None),

    ("Gate", """
a+aaaaa+a
.b.....c.
.b.....c.
.+ddddd+.
""", None),

    ("Trellis", """
a+a+a+a
.b.c.d.
.b.c.d.
e+e+e+e
""", None),

    ("Mast", """
...a...
.b.a.c.
.b.a.c.
.+d+d+.
...a...
""", None),

    ("Pair of Arches", """
+aaa+.+bbb+
c...d.e...f
c...d.e...f
""", None),

    ("Comb", """
a+a+a+a+a
.b.c.d.e.
.b.c.d.e.
.b.c.d.e.
""", None),

    ("Lattice", """
a+a+a+a
.b.c.d.
e+e+e+e
.b.c.d.
f+f+f+f
""", None),

    ("Long Bench", """
a+aaaaa+a
.b.....c.
.b.....c.
.b.....c.
.+ddddd+.
""", None),

    ("Three Masts", """
.a...b...c.
.a...b...c.
.+ddd+ddd+.
.a...b...c.
""", None),

    ("Windows", """
+aaa+.+bbb+
c...d.e...f
+ggg+.+hhh+
""", None),

    ("Frame and Bar", """
+aaaaa+
b.....c
+ddddd+
b.....c
+eeeee+
""", None),

    ("Wide Lattice", """
a+a+a+a+a
.b.c.d.e.
f+f+f+f+f
.b.c.d.e.
g+g+g+g+g
""", None),

    ("Last Word", """
a+aaa+aaa+a
.b...c...d.
.b...c...d.
.+eee+eee+.
.b...c...d.
""", "Everything you have learned, and a bank that lies. Nothing else new."),
]
