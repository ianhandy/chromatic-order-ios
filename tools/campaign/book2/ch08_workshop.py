# Chapter 8: Workshop (levels 101-120)
SHAPES = [
    ("Screwdriver", "\n.......fe\n....c+c++\naaaaa+.fe\n.....b.fe\n....d+d++\n", "Place the longest run first, then work outward from the cells it fixes."),

    ("Try Square", "\nd++......\n.ab......\n.ab......\n.a+ffffff\n.a+cccccc\ne++......\n.ab......\n", None),

    ("Oil Can", "\n..+eeeeee\n..f......\nb.f......\n+a+a+a...\nb.f.c....\n+ddd+d...\n....c....\n", None),

    ("Power Drill", "\nf.......\n+aaaa++a\n+bbbb++b\n...ee+d.\n.....cd.\n.....cd.\n", None),

    ("C Clamp", "\n++aaaaa..\nbc.......\nbc.......\nbc...g...\n+dddd+d..\nb....g...\n...hh+hhh\n", None),

    ("Vise", "\na.b...e..\na.b...e..\na.+ccc+cc\na.b...e..\n+d+dd....\n+ffffffff\n", None),

    ("Toolbox", "\n...+e+e..\n...f.g...\na+a+a++aa\n.c.f.gd..\n.c....d..\n.+bbbb+b.\n.c....d..\n", "When a run carries more than one shared cell, settle that run before the ones hanging off it."),

    ("Handsaw", "\nh...f+ff+\n+aaaa+a.e\n+bbbb+b.e\n.....d..e\n....g+gg+\n........e\n", None),

    ("Pliers", "\n..a.b..\n..a.be.\n.++c++c\n.d...e.\n.d...e.\n.+ff.e.\n.d.gg+.\n", None),

    ("Level", "\n+aaa++aaa\nc.gg++g.d\nc...ef..d\nbbbbb+bb+\n", None),

    ("Tool Rack", "\n++a+a++a+\nfb.c.de.g\nfb.c.de.g\n.b.c..e..\n...c..e..\n", None),

    ("Pipe Clamp", "\n.+cc..+ee\n.b....d..\n.b....d.f\na+aaaa+a+\n.b....d.f\n......gg+\n", None),

    ("Hacksaw", "\n.+aaaaa+a\n.b.....e.\n.b.....e.\ngb.....e.\ng+ccccc+c\n++ff...e.\n+hh......\n", None),

    ("Caliper", "\nh+hhh+...\na+aaa+a+a\n.b...+f+f\n.b...d.g.\n.+cc.+ee.\n", "Eight ramps is a lot to hold at once, so finish one corner of the board completely before moving on."),

    ("Grinder", "\n.......d.\n..+aaaa+a\ne.c...h++\n+f+f...dg\neb+bbbb+g\ne.c......\n", None),

    ("Lathe", "\nd+dd.....\n.c....f..\n.+eeee+e.\na+a+aa++a\n.bb+bbb+.\n...g...h.\n", None),

    ("Bandsaw", "\n+aa++..\nb..dc..\n+hh++..\nb..dcg.\nbee+e+.\nbff+f+f\n", None),

    ("Hand Plane", "\n..+dd.+ff\nh.c.g.e..\n+b+b+b+b.\n+a+a+a+aa\n", None),

    ("Belt Sander", "\nh.+ee+e..\nhcf..g...\n+++aa+a+a\n.cf..g.d.\nb+bbbbb+.\n.......d.\n", None),

    ("Workbench", "\n+gg...h..\nf...ii+..\n++aaaa++a\nfc.....d.\n.c.....d.\n.+eeeee+e\n.c.....d.\n", None),
]
