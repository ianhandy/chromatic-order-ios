# Chapter 11: Interiors (levels 161-180)
SHAPES = [
    ("Staircase", """
.......+gg
.......f..
...e+ee+..
.b..d..f.a
c+cc+..f.a
.b..d..f.a
h+hh+hh+h+
""", None),

    ("Bookshelf", """
a....f.b
a....f.b
+cccc+c+
a....f.b
a.g.h..b
a.g.h..b
+d+d+dd+
a......b
+eeeeee+e
""", None),

    ("Colonnade", """
a+aa+a+a+a
.c..d.e.f.
.c..d.e.f.
g+gg+.+h+h
.c..d.e.f.
b+bb+b+b+b
""", None),

    ("Balcony", """
a.......b
a.......b
+c+c+c+c+
a.e.f.g.b
a.e.f.g.b
+d+d+d+d+
a.e.f.g.b
+h+h+.g.b
""", None),

    ("Fireplace", """
...c..g...
...c..g...
a+a++a++a.
.b..h..d..
.b..h..d..
e+ee+ee+..
.b..h..d..
f+ff+ff+ff
""", None),

    ("Archway", """
...+aaa+aa..
...b...c....
.f.b...c.g..
d+d+...+e+e.
.f.b...c.g..
.f.......g..
h+hhhhhhh+hh
""", None),

    ("Arcade", """
.+aa+a+a+a
.c..d.e.f.
.c..d.e.f.
g+gg+.+h+h
.c..d.e.f.
b+bb+b+b+b
..........
...ii.....
""", None),

    ("Chandelier", """
a+aa+a+aaa
.d..b.e...
.d..b.e...
c++c+c++c.
..g.b..h..
.f+f+ff+..
..g.b..h..
..+i+ii...
""", None),

    ("Alcove", """
a+aaaaa+aa
.b.....c..
.+d+d+d+d.
.b.f.g.c..
.+e+e+.c..
.b.....c..
h+hhhhh+hh
.b.....c..
""", None),

    ("Wardrobe", """
a+aaa+aa
.b...c..
.b.d.c..
.+g+g+..
.b...c..
.+fff+f.
.b...c..
h+hhh+hh
""", None),

    ("Skylight", """
...+e+ee+..
...c.f..d..
...c.f..d..
...c.f..d..
a+a+....+bb
.i.c....d..
g+g+....+hh
.i.........
""", None),

    ("Mezzanine", """
h...........
+b+b+bbb+...
h.c.e...f...
+a+a+aaa+a..
h.c.e...f..j
h...e...f..j
+ggg+ggg+gg+
""", None),

    ("Atrium", """
a+aaaaa...
.b.....c..
.+dd...c..
.b.....+mm
.b...ee+..
.+kk...c..
.b.....c..
h+hhhhh...
""", None),

    ("Rafters", """
....a+a+aa..
.....b.c....
...+d+d+d+d.
...i.b.c.h..
.g.+j+j+.h..
.g.i.b...h..
e+e+e+eee+ee
...i.b...h..
""", None),

    ("Curtain", """
a+aaa+aa+
.b...c..e
.+hhh+hh+
.b...c..e
.+g+g+g.e
.b.j.c..e
f+f+f+ff+
.b.j.c..e
.b.j.+ii+
........e
""", None),

    ("Elevator", """
a+a+aaa+.
.b.d...c.
.b.d...c.
.b.d.g.c.
e+e+e+e+.
.b.d.g.c.
.b.+j+j+.
.b...g.c.
.+fff+f+.
""", None),

    ("Banister", """
.......a+aa.
........d...
....b+bb+...
.....e..d..
.....e.g+gg.
+c+cc+..d...
j.f..e.....
j.f.h+hh....
j.f..e......
+i+ii.......
j.f.........
""", None),

    ("Landing", """
...bb+bbbbb..
.....c.......
.............
..aaaaa+aaaa.
.......d.....
...g...d.i...
e+e+.....+h+h
.f.g.....i.j.
.f.........j.
""", None),

    ("Stove", """
.....b..
....i+ii
.....b..
.....+kk
.....b..
.....+c.
.d..e...
.d..e...
.d..e...
.d..e...
.d..e...
f+ff+ff.
.d..e...
""", None),

    ("Dome", """
..a+a+aa..
...d.e....
.+b+b+b...
.f.d.e.g..
c+c+c+c+cc
.f.....g..
....+kk+..
....j..g..
..ii+ii+i.
""", None),
]
