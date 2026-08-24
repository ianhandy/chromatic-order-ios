"""The campaign: 200 hand-drawn shapes in twelve chapters.

Every shape is drawn with horizontal and vertical strokes only, because a
gradient in kromatika is always a straight run of cells. `+` marks a cell
two gradients share. See art.py for the notation.

Each entry is (name, art, tip). `tip` is a one-line coaching note shown
above the board the first time a player opens that level; None = silent.
Names are one or two words and say what the shape is.
"""

# ─── What the tips promise ──────────────────────────────────────────
# A tip that describes the board is a claim about it, and the colours and
# starter cells are chosen by search — so a rebuild could quietly make a
# tip false. Every such claim is declared here and enforced in build.py:
# a palette that doesn't satisfy the level's claims is rejected, and a
# claim that can never be satisfied fails the build instead of shipping a
# tip that lies. Keep this in sync when you edit a tip.
#
#   ends-locked   every gradient has both of its endpoints given
#   bank1         exactly one swatch to place
#   crossing      at least one shared cell
#   crossing4     exactly four shared cells (a closed loop of them)
#   no-crossing   no shared cells at all
#   all-crossed   every gradient touches at least one shared cell
#   families      gradients sit in visibly different hue families
#   chroma-ramp   at least one gradient ramps chroma at a fixed hue
#   equal-lengths the two gradients are the same length
#   grid-9-rows   the board is nine rows tall
TIP_CLAIMS = {
    "Bar": {"bank1", "ends-locked"},
    "Beam": {"ends-locked"},
    "Tower": {"ends-locked"},
    "Spine": {"ends-locked"},
    "Domino": {"families"},
    "Corner": {"no-crossing"},
    "Tee": {"crossing"},
    "Cross": {"crossing"},
    "Track": {"equal-lengths", "no-crossing"},
    "Goalpost": {"crossing", "ends-locked"},
    "Frame": {"crossing4"},
    "Rake": {"crossing"},
    "Fish": {"chroma-ramp"},
    "Snake": {"all-crossed"},
    "Pyramid": {"no-crossing", "families"},
    "Cascade": {"all-crossed"},
    "Loom": {"crossing"},
    "Mandala": {"crossing", "grid-9-rows"},
}

CHAPTERS = [
    # (title, first level, last level, blurb)
    ("First Steps", 1, 6, "One gradient. Read the ends, fill the middle."),
    ("Two Strokes", 7, 18, "Two gradients at a time, and cells they share."),
    ("Crossings", 19, 32, "Shapes built from strokes that cross."),
    ("Everyday Things", 33, 52, "Bigger objects, more gradients, tighter steps."),
    ("Creatures", 53, 70, "Chroma joins in. Neighbors start to look alike."),
    ("Landmarks", 71, 88, "Wide scenes with long ramps to keep straight."),
    ("Mastery", 89, 100, "Everything at once, with barely any given cells."),
    ("Workshop", 101, 120, "Tools built from connected runs and shared joints."),
    ("Orchestra", 121, 140, "Instruments with more parts to sort and align."),
    ("Circuitry", 141, 160, "Dense networks where each crossing carries information."),
    ("Interiors", 161, 180, "Rooms and structures assembled one section at a time."),
    ("Grand Works", 181, 200, "Large machines and landmarks at the campaign's limit."),
]

# What the app actually shows. The CHAPTERS keys above are the authoring
# pipeline's identifiers — build.py branches on them for per-chapter
# difficulty tuning, and check_book2.py audits by them — so they stay put.
# The shipped titles don't: naming a chapter after what its boards depict
# ("Everyday Things", "Creatures", "Orchestra") promised the player a
# picture the board can't deliver, and told them nothing about what the
# chapter asks of them. These name the step in the ladder instead.
DISPLAY_CHAPTERS = {
    # authoring key      → (shipped title, shipped blurb)
    "First Steps":     ("First Steps",  "One gradient. Read the ends, fill the middle."),
    "Two Strokes":     ("Two Runs",     "Two gradients at a time, and the cells they share."),
    "Crossings":       ("Crossings",    "Runs that cross, and the shared cell that settles both."),
    "Everyday Things": ("Wider Boards", "Bigger boards, more gradients, tighter steps."),
    "Creatures":       ("Chroma",       "Chroma ramps join in. Neighbors start to look alike."),
    "Landmarks":       ("Long Ramps",   "Wide boards with long ramps to keep straight."),
    "Mastery":         ("Mastery",      "Everything at once, with barely any given cells."),
    "Workshop":        ("Shared Ends",  "Connected runs that hand each other their ends."),
    "Orchestra":       ("Many Runs",    "More runs to sort and align at once."),
    "Circuitry":       ("Networks",     "Dense networks where every crossing carries information."),
    "Interiors":       ("Sections",     "Large boards settled one section at a time."),
    "Grand Works":     ("The Limit",    "The widest boards and the longest ramps in the campaign."),
}


def display_title(key: str) -> str:
    """Shipped title for an authoring chapter key."""
    return DISPLAY_CHAPTERS[key][0]

# ─── Chapter 1 — First Steps (1-6) ─────────────────────────────────
# One gradient, both ends given. Teaches the core read: a gradient is an
# even walk from one colour to another, so the middle is forced.

CH1 = [
    ("Bar", """
aaa
""", "Drag the swatch into the empty cell. Both ends are already placed."),

    ("Post", """
a
a
a
""", "Gradients run down as well as across."),

    ("Beam", """
aaaa
""", "A longer run, same idea: even steps from one end to the other."),

    ("Tower", """
a
a
a
a
a
""", "The ends are given. Every cell between them is one step from the next."),

    ("Rail", """
aaaaaa
""", None),

    ("Spine", """
a
a
a
a
a
a
a
""", "Long ramps step gently. Trust the ends."),
]

# ─── Chapter 2 — Two Strokes (7-18) ────────────────────────────────
# A second gradient arrives, deliberately in a different colour family so
# the two never get mixed up. Shared cells (+) get introduced at "Tee".

CH2 = [
    ("Domino", """
aaa
...
bbb
""", "Two gradients now. They are different color families on purpose."),

    ("Rails", """
a.b
a.b
a.b
a.b
""", None),

    ("Corner", """
a...
a...
a...
abbb
""", "Two strokes, one bend. Each stroke ramps on its own."),

    ("Tee", """
aa+aa
..b..
..b..
..b..
""", "Where the strokes meet, one cell belongs to both: one color doing two jobs."),

    ("Cross", """
..a..
..a..
bb+bb
..a..
..a..
""", "Solve the easier stroke first, then use the shared cell."),

    ("Ell", """
a....
a....
a....
a....
abbbb
""", None),

    ("Track", """
aaaaa
bbbbb
""", "Neighbors. Check which row a swatch belongs to before dropping it."),

    ("Hurdle", """
..b..
..b..
aa+aa
""", None),

    ("Signpost", """
..a..
bb+bb
..a..
..a..
..a..
""", None),

    ("Anvil", """
aaa+aaa
...b...
...b...
""", None),

    ("Sword", """
...a...
bbb+bbb
...a...
...a...
...a...
...a...
""", None),

    ("Hook", """
bbbbb
....a
....a
....a
....a
""", None),
]

# ─── Chapter 3 — Crossings (19-32) ─────────────────────────────────
# Three to five strokes, and crossings that pin a gradient at both ends.
# This is where the crossword logic of the game takes over.

CH3 = [
    ("Goalpost", """
+aaaaa+
b.....c
b.....c
""", "A stroke pinned at both ends has nothing left to guess."),

    ("Table", """
a+aaa+a
.b...c.
.b...c.
""", None),

    ("Chair", """
a...
a...
a...
+bb+
...c
...c
""", None),

    ("Bed", """
a......
a.....c
a.....c
+bbbbb+
""", None),

    ("Frame", """
+aaa+
b...c
b...c
+ddd+
""", "Every corner is shared. Work around the loop."),

    ("Hammer", """
aa+aa
cc+cc
..b..
..b..
..b..
""", None),

    ("Key", """
b.....
+aaaa+
b....c
.....c
""", None),

    ("Lamp", """
aa+aa
..b..
..b..
..b..
cc+cc
""", None),

    ("Fork", """
a.b.c
a.b.c
+d+d+
..b..
..b..
..b..
""", None),

    ("Swing", """
a+a+a
.b.c.
.b.c.
.+d+.
""", None),

    ("Window", """
+a+a+
b.e.c
b.e.c
+d+d+
""", None),

    ("Ladder", """
a.b
+c+
a.b
+d+
a.b
""", None),

    ("Flag", """
abbbb
acccc
a....
a....
a....
a....
""", None),

    ("Rake", """
a+a+a+a+a
.b.c.d.e.
.b.c.d.e.
""", "Five gradients. The long one holds the other four in place."),
]

# ─── Chapter 4 — Everyday Things (33-52) ───────────────────────────
# Real objects, three to six strokes. Steps get smaller, so ordering
# within a gradient starts to matter as much as telling them apart.

CH4 = [
    ("House", """
+aaaaa+
b.....c
b.....c
b..e..c
b..e..c
+dd+dd+
""", "Bigger boards now. Place what you are sure of and the rest narrows."),

    ("Boat", """
....d....
....+eee.
b...d...c
+aaa+aaa+
""", None),

    ("Tree", """
.aaaaa.
bbbbbbb
.cc+cc.
...d...
...d...
""", None),

    ("Rocket", """
..a..
.b+b.
..a..
..a..
cc+cc
.d+d.
""", None),

    ("Bridge", """
..a...b..
..a...b..
cc+ccc+cc
..a...b..
..a...b..
""", None),

    ("Train", """
.aaa...
bbbbbbb
ccccccc
.d...e.
.d...e.
""", "The two long rows are the same length. Read left to right, not up and down."),

    ("Truck", """
aaaaa..
bbbbbbb
.c...d.
.c...d.
""", None),

    ("Clock", """
+aaa+
b...c
+eee+
b...c
+ddd+
""", None),

    ("Bell", """
.aaa.
.bbb.
cc+cc
..d..
..d..
""", None),

    ("Cup", """
aaaaaaa
.b...c.
.b...c.
.+ddd+.
""", None),

    ("Bottle", """
..ab..
..ab..
..ab..
+c++c+
d....e
d....e
+ffff+
""", None),

    ("Envelope", """
+aaaaa+
b.eee.c
b.....c
+ddddd+
""", None),

    ("Book", """
+aaa+aaa+
b...e...c
b...e...c
+ddd+ddd+
""", None),

    ("Pencil", """
.aaaaaa
bbbbbbb
.cccccc
""", None),

    ("Anchor", """
...a...
.bb+bb.
...a...
...a...
...a...
.d.a.e.
.+c+c+.
""", None),

    ("Wrench", """
+a+a+
b.e.c
+d+d+
..e..
..e..
..e..
""", None),

    ("Candle", """
.bbb.
..a..
..a..
..a..
cc+ccc
""", None),

    ("Drum", """
+aaaaa+
b.e.f.c
b.e.f.c
+d+d+d+
""", None),

    ("Camera", """
..aaa..
+bbbbb+
c.....d
c.eee.d
c.....d
+fffff+
""", None),

    ("Lantern", """
..aaa..
+bbbbb+
c.....d
c.....d
+eeeee+
""", None),
]

# ─── Chapter 5 — Creatures (53-70) ─────────────────────────────────
# Chroma ramps join lightness and hue, and shapes get wide enough that
# two gradients can look related until you check their steps.

CH5 = [
    ("Fish", """
...aaaa
f.bbbbb
fccccccc
f.ddddd
...eeee
""", "Chroma ramps now too: same hue, draining color."),

    ("Crab", """
a.....b
+ccccc+
ddddddd
.e...f.
.e...f.
""", None),

    ("Snail", """
+aaa+..
b...c..
b...c.e
+ddd+d+
""", None),

    ("Bird", """
..aa...
.bbbb..
ccccccc
.dddd..
..e.f..
..e.f..
""", None),

    ("Owl", """
+aaaaa+
b.....c
b.d.e.c
b.d.e.c
+fffff+
""", None),

    ("Cat", """
a...b
+ccc+
+ddd+
.e.f.
.e.f.
""", None),

    ("Dog", """
aaa....
bbbbbbb
ccccccc
.d.e.f.
.d.e.f.
""", None),

    ("Bunny", """
.a...b.
.a...b.
.+ccc+.
ddddddd
eeeeeee
..f.g..
..f.g..
""", None),

    ("Frog", """
a...b
+ccc+
ddddd
e...f
e...f
""", None),

    ("Turtle", """
..aaaaa..
.bbbbbbb.
..cccccff
..d...e..
..d...e..
""", None),

    ("Whale", """
....aa..
fbbbbbbb
fccccccc
.ddddddd
""", None),

    ("Bee", """
aaa.bbb
.ccccc.
ddddddd
.eeeee.
...f...
...f...
""", None),

    ("Ant", """
aa.bbb.ccc
.d.e...f..
.d.e...f..
""", None),

    ("Spider", """
..e.f..
a.e.f.b
+c+c+c+
a.ddd.b
""", None),

    ("Butterfly", """
f.e.g
+a+a+
bb+bbb
..e..
""", None),

    ("Snake", """
+aaaaa
b.....
+cccc+
.....d
eeeee+
""", "A chain of pinned strokes. Each one hands the next its start."),

    ("Penguin", """
.aaa.
.bbb.
+eee+
c...d
+fff+
.ggg.
""", None),

    ("Fox", """
a...b.
a...b.
+ccc+.
ddddd+
.....e
.....e
""", None),
]

# ─── Chapter 6 — Landmarks (71-88) ─────────────────────────────────
# Wide scenes. Long gradients with small steps, several colour families
# in play at once, and fewer given cells.

CH6 = [
    ("Lighthouse", """
..aaa..
.+bbb+.
.c...d.
.c...d.
.c...d.
.+eee+.
fffffff
""", None),

    ("Windmill", """
..a..
..a..
bb+bbb
..a..
..a..
.c.d.
.c.d.
.+e+.
""", None),

    ("Sailboat", """
...a...
.bb+...
.cc+...
.dd+...
...a...
eeeeeee
""", None),

    ("Castle", """
a.b.c.d
+e+e+e+
fff+fff
...g...
...g...
""", None),

    ("Church", """
...a...
bbb+bbbb
...a...
c.....d
c.....d
+eeeee+
""", None),

    ("Skyline", """
..b......
..b...d..
a.b...d..
a.b.c.d..
a.b.c.d.e
a.b.c.d.e
+f+f+f+f+
""", None),

    ("Pyramid", """
...aaa...
..bbbbb..
.ccccccc.
ddddddddd
""", "Four parallel ramps, four families. Nothing crosses, nothing helps."),

    ("Fountain", """
..a.b.c..
..a.b.c..
+d+d+d+d+
e.......f
+ggggggg+
""", None),

    ("Aqueduct", """
aaaaaaaaa
+b+b+b+b+
c.d.e.f.g
c.d.e.f.g
""", None),

    ("Cathedral", """
.a...b.
.a...b.
.a...b.
c+ccc+c
ddddddd
eee+eee
...f...
...f...
""", None),

    ("Ferris", """
+a+a+
b.e.c
+h+h+
b.e.c
+d+d+
.f.g.
.f.g.
""", None),

    ("Temple", """
..aaaaa..
.bbbbbbb.
ccccccccc
.d.e.f.g.
.d.e.f.g.
hhhhhhhhh
""", None),

    ("Observatory", """
..aaa..
.bbbbb.
+ccccc+
d.....e
d.....e
+fffff+
""", None),

    ("Garden", """
a+a.b+b.c+c
.d...e...f.
.d...e...f.
ggggggggggg
""", None),

    ("Harbor", """
..a........
bb+........
..a..dd+...
..a....c...
..a....c...
eeeeeeeeeee
""", None),

    ("Waterfall", """
a.b.c.d.e
a.b.c.d.e
a.b.c.d.e
+f+f+f+f+
ggggggggg
""", None),

    ("Trainyard", """
ccccc.ddddd
.e.....f...
.e.....f...
aaaaaaaaaaa
bbbbbbbbbbb
""", None),

    ("Cityscape", """
..b......
a.b.....d
a.b..c..d
+e+ee+ee+
a.b..c..d
a.b..c..d
+f+ff+ff+
a.b..c..d
""", None),
]

# ─── Chapter 7 — Mastery (89-100) ──────────────────────────────────
# Machines and monuments. Dense crossings, multi-channel ramps, and only
# the cells uniqueness demands are given.

CH7 = [
    ("Cascade", """
aa+........
..b........
..+cc+.....
.....d.....
.....+ee+..
........f..
........+gg
""", "Nothing here is loose: every stroke shares an end with another one."),

    ("Circuit", """
+aaaa+...
b....c...
b....+d+d
b......f.
+eeeeee+.
""", None),

    ("Loom", """
.a.b.c.
d+d+d+d
.a.b.c.
e+e+e+e
.a.b.c.
f+f+f+f
.a.b.c.
""", "Every crossing is a fact about two gradients at once."),

    ("Lattice", """
.a.b.c.d.
e+e+e+e+e
.a.b.c.d.
f+f+f+f+f
.a.b.c.d.
g+g+g+g+g
.a.b.c.d.
""", None),

    ("Reactor", """
+aaaaaaa+
b.......c
b.+ddd+.c
b.e...f.c
b.+ggg+.c
b.......c
+hhhhhhh+
""", None),

    ("Palace", """
.a.....b.
.a.....b.
++ccccc++
d...g...e
d...g...e
+fff+fff+
""", None),

    ("Carousel", """
.+aa+aa+.
.b..c..d.
.b..c..d.
.b..c..d.
.b..c..d.
e+ee+ee+e
fffffffff
""", None),

    ("Organ", """
..c......
..c.d....
a.c.d.e..
a.c.d.e.f
a.c.d.e.f
+g+g+g+g+
hhhhhhhhh
""", None),

    ("Citadel", """
.a..b..c.
++dd+dd++
e.......f
e.......f
e...g...f
e...g...f
+hhh+hhh+
""", None),

    ("Colossus", """
..aaaaa..
..bbbbb..
+ccccccc+
d.fffff.e
d.ggggg.e
..h+h+h..
...i.j...
...i.j...
""", None),

    ("Vault", """
+aaaaaaa+
b...e...c
b...e...c
b.ff+ff.c
b...e...c
b...e...c
+hhhhhhh+
""", None),

    ("Mandala", """
....a....
.+cc+cc+.
.e..a..f.
.e..a..f.
b+bb+bb+b
.e..a..f.
.e..a..f.
.+dd+dd+.
....a....
""", "Last one. Nine rows, six ramps, every crossing earning its keep."),
]

from book2.ch08_workshop import SHAPES as CH8
from book2.ch09_orchestra import SHAPES as CH9
from book2.ch10_circuitry import SHAPES as CH10
from book2.ch11_interiors import SHAPES as CH11
from book2.ch12_grand_works import SHAPES as CH12

ALL = CH1 + CH2 + CH3 + CH4 + CH5 + CH6 + CH7 + CH8 + CH9 + CH10 + CH11 + CH12


def chapter_of(level: int) -> tuple[str, int, int, str]:
    for entry in CHAPTERS:
        if entry[1] <= level <= entry[2]:
            return entry
    raise ValueError(f"level {level} outside the campaign")
