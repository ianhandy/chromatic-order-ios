"""Score blind shape-naming answers against the levels' intended names.

Feed it lines of `#12 = kite` (whatever a cold reader saw) on stdin or in a
file, and it reports, per level, whether the guess landed on the intended
name, in the same family, or somewhere else entirely.

    python3 score_blind.py answers.txt

Synonym groups are deliberately generous: the question is "does the shape
read as the sort of thing it's called", not "did the reader pick my noun".
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CAMPAIGN = Path(__file__).resolve().parents[2] / "ChromaticOrder" / "Resources" / "campaign.json"

# Guesses that count as hitting the intended name. Key = intended level name.
SYNONYMS = {
    "Bar": {"line", "bar", "row", "horizontal line", "rectangle", "dash"},
    "Post": {"line", "post", "column", "vertical line", "pillar", "bar"},
    "Beam": {"line", "beam", "bar", "row", "rectangle", "horizontal line"},
    "Tower": {"line", "tower", "column", "vertical line", "pillar", "bar", "post"},
    "Rail": {"line", "rail", "bar", "row", "rectangle", "horizontal line"},
    "Spine": {"line", "spine", "column", "vertical line", "pillar", "post", "bar"},
    "Domino": {"domino", "two lines", "equals", "equal sign", "parallel lines", "tracks"},
    "Rails": {"rails", "tracks", "two lines", "parallel lines", "ladder", "railway"},
    "Corner": {"corner", "l shape", "l", "angle", "right angle", "elbow", "boot"},
    "Tee": {"tee", "t shape", "t", "t-shape", "hammer", "cross"},
    "Cross": {"cross", "plus", "plus sign", "crosshair", "star"},
    "Ell": {"l shape", "l", "corner", "angle", "ell", "boot", "right angle"},
    "Track": {"track", "tracks", "two lines", "parallel lines", "equals", "road", "rails"},
    "Hurdle": {"hurdle", "t shape", "t", "upside-down t", "inverted t", "hammer", "tee", "signpost"},
    "Signpost": {"signpost", "sign", "post", "cross", "plus", "street sign", "lamppost"},
    "Anvil": {"anvil", "t shape", "t", "hammer", "tee", "table"},
    "Sword": {"sword", "cross", "crucifix", "dagger", "plus", "sword hilt"},
    "Hook": {"hook", "corner", "l shape", "seven", "7", "flag", "gallows"},
    "Goalpost": {"goalpost", "goal", "arch", "bridge", "gate", "doorway", "u shape", "staple", "table", "upside-down u"},
    "Table": {"table", "bench", "desk", "stool", "bridge", "goalpost"},
    "Chair": {"chair", "seat", "stool", "four", "4", "step", "stairs"},
    "Bed": {"bed", "trough", "l shape", "sofa", "couch", "u shape", "boot"},
    "Frame": {"frame", "square", "rectangle", "box", "window", "ring", "picture frame", "o"},
    "Hammer": {"hammer", "mallet", "t shape", "axe", "tee", "cross"},
    "Key": {"key", "hook", "corner", "wrench", "l shape", "seven"},
    "Lamp": {"lamp", "lantern", "hourglass", "i shape", "i-beam", "spool", "dumbbell", "table"},
    "Fork": {"fork", "trident", "pitchfork", "rake", "cross", "plant", "cactus"},
    "Swing": {"swing", "goalpost", "arch", "bridge", "gate", "table", "pi"},
    "Window": {"window", "frame", "square", "box", "rectangle", "grid", "eight", "b"},
    "Ladder": {"ladder", "h shape", "h", "rungs", "stairs", "grid"},
    "Flag": {"flag", "banner", "corner", "l shape", "p", "sign", "pennant"},
    "Rake": {"rake", "comb", "fork", "pitchfork", "trident", "fence", "crown"},
    "House": {"house", "box", "square", "rectangle", "frame", "building", "arch", "door", "doorway"},
    "Boat": {"boat", "ship", "sailboat", "yacht", "raft", "sail"},
    "Tree": {"tree", "mushroom", "plant", "bush", "umbrella", "toadstool", "broccoli"},
    "Rocket": {"rocket", "anchor", "plane", "airplane", "sword", "cross", "missile", "spaceship"},
    "Bridge": {"bridge", "cross", "plus", "h shape", "h", "aqueduct", "double cross"},
    "Train": {"train", "truck", "car", "bus", "wagon", "bench", "table", "cart", "locomotive"},
    "Truck": {"truck", "train", "car", "bus", "wagon", "bench", "table", "cart", "van"},
    "Clock": {"clock", "box", "square", "frame", "window", "b", "eight", "watch", "face"},
    "Bell": {"bell", "mushroom", "lamp", "umbrella", "bulb", "toadstool"},
    "Cup": {"cup", "mug", "glass", "trophy", "goblet", "table", "cauldron", "pot"},
    "Bottle": {"bottle", "flask", "vase", "jar", "bomb", "perfume", "lamp"},
    "Envelope": {"envelope", "frame", "box", "square", "letter", "window", "rectangle"},
    "Book": {"book", "window", "glasses", "spectacles", "goggles", "frame", "two boxes", "b"},
    "Pencil": {"pencil", "bar", "line", "rectangle", "ruler", "brick", "flag", "block"},
    "Anchor": {"anchor", "cross", "crucifix", "sword", "plus", "grave", "trident"},
    "Wrench": {"wrench", "spanner", "key", "hammer", "screwdriver", "lollipop", "magnifier"},
    "Candle": {"candle", "lamp", "trophy", "cup", "goblet", "torch", "match"},
    "Drum": {"drum", "box", "frame", "window", "barrel", "grid", "crate"},
    "Camera": {"camera", "box", "frame", "window", "tv", "television", "screen", "microwave"},
    "Lantern": {"lantern", "lamp", "box", "frame", "window", "chest", "crate"},
    "Fish": {"fish", "whale", "arrow", "leaf", "eye", "shark", "kite"},
    "Crab": {"crab", "spider", "table", "bench", "insect", "robot", "bug"},
    "Snail": {"snail", "boot", "shell", "seat", "chair", "sofa", "l shape"},
    "Bird": {"bird", "arrow", "plane", "airplane", "penguin", "chicken", "duck", "rocket"},
    "Owl": {"owl", "face", "box", "frame", "window", "robot", "monitor", "tv"},
    "Cat": {"cat", "animal", "table", "bench", "robot", "face", "bull", "cow"},
    "Dog": {"dog", "animal", "table", "bench", "horse", "cow", "cat", "sheep"},
    "Bunny": {"bunny", "rabbit", "animal", "robot", "cat", "table", "bench", "antenna"},
    "Frog": {"frog", "animal", "robot", "table", "insect", "spider", "chair", "bench", "u shape"},
    "Turtle": {"turtle", "tortoise", "animal", "table", "bench", "bug", "beetle", "car"},
    "Whale": {"whale", "fish", "arrow", "shark", "boat", "submarine", "leaf"},
    "Bee": {"bee", "insect", "bug", "wasp", "fly", "butterfly", "tree", "mushroom"},
    "Ant": {"ant", "insect", "bug", "beetle", "spider", "three blocks", "unclear"},
    "Spider": {"spider", "insect", "bug", "crab", "robot", "antenna", "table"},
    "Butterfly": {"butterfly", "insect", "bug", "moth", "bowtie", "bow tie", "plane", "arrow"},
    "Snake": {"snake", "s shape", "s", "zigzag", "staircase", "stairs", "serpent", "z"},
    "Penguin": {"penguin", "bird", "robot", "figure", "person", "bottle", "chess piece"},
    "Fox": {"fox", "animal", "cat", "dog", "four", "4", "chair", "flag"},
    "Lighthouse": {"lighthouse", "tower", "building", "lamp", "castle", "rocket", "chess piece"},
    "Windmill": {"windmill", "cross", "plus", "turbine", "propeller", "fan", "church"},
    "Sailboat": {"sailboat", "boat", "ship", "yacht", "sail", "flag", "windmill"},
    "Castle": {"castle", "crown", "fortress", "battlements", "building", "tower", "comb", "rake"},
    "Church": {"church", "cross", "chapel", "cathedral", "building", "temple", "crucifix"},
    "Skyline": {"skyline", "cityscape", "city", "buildings", "bar chart", "graph", "chart", "towers"},
    "Pyramid": {"pyramid", "triangle", "stairs", "mountain", "steps", "ziggurat", "tree"},
    "Fountain": {"fountain", "candles", "table", "bench", "sofa", "couch", "bed", "cake"},
    "Aqueduct": {"aqueduct", "bridge", "viaduct", "comb", "rake", "fence", "table", "pier"},
    "Cathedral": {"cathedral", "church", "cross", "temple", "building", "chapel", "castle"},
    "Ferris": {"ferris", "ferris wheel", "wheel", "window", "grid", "frame", "table", "box"},
    "Temple": {"temple", "building", "parthenon", "colonnade", "table", "bridge", "pyramid", "shrine"},
    "Observatory": {"observatory", "building", "dome", "lamp", "box", "frame", "microwave", "tv"},
    "Garden": {"garden", "flowers", "plants", "trees", "fence", "row", "candles", "orchard"},
    "Harbor": {"harbor", "harbour", "boats", "port", "dock", "sailboat", "boat", "flags", "ship"},
    "Waterfall": {"waterfall", "rain", "curtain", "comb", "fence", "bars", "fountain", "shower"},
    "Trainyard": {"trainyard", "train", "rails", "tracks", "yard", "railway", "cars", "wagons"},
    "Cityscape": {"cityscape", "skyline", "city", "buildings", "grid", "towers", "windows"},
    "Cascade": {"cascade", "stairs", "staircase", "steps", "zigzag", "waterfall", "snake"},
    "Circuit": {"circuit", "maze", "path", "pipe", "pipes", "wire", "spiral", "labyrinth"},
    "Loom": {"loom", "grid", "lattice", "weave", "mesh", "net", "waffle", "window"},
    "Lattice": {"lattice", "grid", "loom", "weave", "mesh", "net", "waffle", "window"},
    "Reactor": {"reactor", "frame", "box", "square", "nested squares", "maze", "spiral", "window"},
    "Palace": {"palace", "building", "castle", "temple", "gate", "arch", "bridge"},
    "Carousel": {"carousel", "merry-go-round", "tent", "table", "bridge", "temple", "cage"},
    "Organ": {"organ", "pipes", "pipe organ", "bar chart", "chart", "graph", "city", "skyline"},
    "Citadel": {"citadel", "castle", "fortress", "building", "gate", "battlements", "crown"},
    "Colossus": {"colossus", "robot", "figure", "person", "giant", "statue", "man"},
    "Vault": {"vault", "cross", "frame", "box", "square", "window", "safe", "door"},
    "Mandala": {"mandala", "cross", "grid", "window", "compass", "snowflake", "star", "wheel"},
}


def normalise(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9 -]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def main(path: str) -> int:
    names = {l["index"]: l["name"] for l in json.loads(CAMPAIGN.read_text())["levels"]}
    answers: dict[int, str] = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"\s*#?(\d+)\s*[=:]\s*(.+)", line)
        if m:
            answers[int(m.group(1))] = normalise(m.group(2))

    hits, misses, unclear = [], [], []
    for index in sorted(names):
        intended = names[index]
        guess = answers.get(index)
        if guess is None:
            continue
        allowed = {normalise(s) for s in SYNONYMS.get(intended, set())}
        allowed.add(normalise(intended))
        if guess in ("unclear", "unknown", "nothing"):
            unclear.append((index, intended, guess))
        elif guess in allowed or any(g in allowed for g in guess.split()):
            hits.append((index, intended, guess))
        else:
            misses.append((index, intended, guess))

    total = len(hits) + len(misses) + len(unclear)
    print(f"read as intended (or a fair synonym): {len(hits)}/{total}")
    print(f"read as something else:               {len(misses)}/{total}")
    print(f"read as nothing:                      {len(unclear)}/{total}\n")
    if misses:
        print("MISREADS — cold reader saw something different:")
        for index, intended, guess in misses:
            print(f"  {index:3d} called {intended:12} → read as {guess!r}")
    if unclear:
        print("\nUNREADABLE — cold reader saw no object:")
        for index, intended, guess in unclear:
            print(f"  {index:3d} called {intended}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/blind-answers.txt"))
