# Chapter 8: Workshop (levels 101-120)
SHAPES = [
    ("Screwdriver", "\n.......f.e\n.....+c+.e\naaaaa+.f.e\n.....b.f.e\n....d+d+.e\n", "Place the longest run first, then work outward from the cells it fixes."),

    ("Try Square", "\nd+........\n.a.b......\n.a.b......\n.a.+ffffff\n.a.b......\n.a.+cccccc\ne+.b......\n.a.b......\n", None),

    ("Oil Can", "\n..+eeeeee\n..f......\nb.f......\n+a+a+a...\nb.f.c....\n+d+d+d...\n....c....\n", None),

    ("Power Drill", "\nf........\n+aaaa+a+a\nf....c.d.\n+bbbb+b+b\n.....c.d.\n...ee+.d.\n.....c.d.\n.....c.d.\n", None),

    ("C Clamp", "\nb.+aaaaa..\nb.c.......\nb.c.......\nb.c...g...\n+d+ddd+d..\nb.....g...\n....hh+hhh\n", None),

    ("Vise", "\na.b...e..\na.b...e..\na.+ccc+cc\na.b...e..\n+d+dd....\na........\n+ffffffff\n", None),

    ("Toolbox", "\n...+e+e..\n...f.g...\na+a+a++aa\n.c.f..d..\n.c....d..\n.+bbbb+b.\n.c....d..\n", "When a run carries more than one shared cell, settle that run before the ones hanging off it."),

    ("Handsaw", "\nh....+ff+\n+aaaa+..e\nh....d..e\n+bbbb+..e\n.....+gg+\n........e\n", None),

    ("Pliers", "\n.a.b...\n.a.b.e.\n++c+c+c\nd....e.\nd....e.\n+ff..e.\nd....e.\nd.ggg+.\n", None),

    ("Level", "\n+aa+a+aa+\nc..e.f..d\nc.g+g+g.d\nc....f..d\n+bbbb+bb+\n", None),

    ("Tool Rack", "\n+a+a+a+a+a+\nf.b.c.d.e.g\nf.b.c.d.e.g\n..b.c...e..\n....c...e..\n", None),

    ("Pipe Clamp", "\n.+cc..+ee\n.b....d..\n.b....d.f\na+aaaa+a+\n.b....d.f\n......+g+\n", None),

    ("Hacksaw", "\n..+aaaaa+a\n..b.....e.\n..b.....e.\ng.b.....e.\ng.+ccccc+c\n..b.....e.\n..+ff...e.\n..........\n..hhh.....\n", None),

    ("Caliper", "\nh+hhh+...\n.b...d...\na+aaa+aaa\n.b...d...\n.b...+f+f\n.b...d.g.\n.b...d.g.\n.+cc.+e+e\n", "Eight ramps is a lot to hold at once, so finish one corner of the board completely before moving on."),

    ("Grinder", "\n.......d..\n..+aaa.d..\ne.c...h+h+\n+f+f...d.g\ne.c....d.g\n+b+bbbb+b+\ne.c.......\n", None),

    ("Lathe", "\nd+dd.....\n.c....f..\n.+eeee+e.\n.c....f..\na+a+aa++a\n...g...h.\n.bb+bbb+.\n...g...h.\n", None),

    ("Bandsaw", "\n+aa+a+..\nb..d.c..\n+hh+h+..\nb..d.c..\nb.e+e++.\n......g.\n.fffff+f\n", None),

    ("Hand Plane", "\n..+d+.+ff\nh.c.g.e..\n+b+b+b+b.\nh.c.g.e..\n+a+a+a+aa\n", None),

    ("Belt Sander", "\nh.+ee+e..\nh.f..g...\n+++aa+a+a\n.c.....d.\nb+bbbbb+.\n.......d.\n", None),

    ("Workbench", "\n+gg.ii+..\nf.....h..\n++aaaa++a\n.c.....d.\n.c.....d.\n.+eeeee+e\n.c.....d.\n", None),
]
