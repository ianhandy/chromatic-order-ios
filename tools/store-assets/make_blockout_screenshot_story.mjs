#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const output = process.argv[2]
  ?? join(homedir(), "Programming", "repos", "blockout", "work", "kromatika-ios-app-store.blockout.json");

const FRAME_W = 393;
const FRAME_H = 852;
const TILE = 73;
const PITCH = 80;
const GRID_X = 0;
const GRID_Y = 20;
const ROOT_ROW = 4;
const MIN_DELTA_E = 5;
const SHARED_GRAY = color(0.56, 0, 0);
let sequence = 0;

function id(prefix) {
  sequence += 1;
  return `${prefix}_${String(sequence).padStart(4, "0")}`;
}

function ensure(condition, message) {
  if (!condition) throw new Error(message);
}

function text(prefix, value, x, y, options = {}) {
  return {
    id: id(prefix),
    type: "text",
    text: value,
    role: options.role ?? "heading",
    fontSize: options.fontSize ?? 34,
    weight: options.weight ?? 700,
    w: options.w ?? "hug",
    h: "hug",
    color: options.color ?? "ink",
    x,
    y,
    ...(options.colorHex ? { colorHex: options.colorHex } : {}),
    ...(options.name ? { name: options.name } : {}),
    ...(options.note ? { note: options.note } : {}),
  };
}

function tile(prefix, x, y, fill, size = TILE, radius = 19, options = {}) {
  return {
    id: id(prefix),
    type: "rect",
    w: size,
    h: size,
    radius,
    fill,
    x,
    y,
    ...(options.opacity === undefined ? {} : { opacity: options.opacity }),
    ...(options.overlay ? { overlay: true } : {}),
    ...(options.name ? { name: options.name } : {}),
    ...(options.note ? { note: options.note } : {}),
  };
}

function h(row, col0, col1) {
  return Array.from({ length: col1 - col0 + 1 }, (_, index) => [row, col0 + index]);
}

function v(col, row0, row1) {
  return Array.from({ length: row1 - row0 + 1 }, (_, index) => [row0 + index, col]);
}

function color(L, c, hValue) {
  return { L, c, h: normH(hValue) };
}

function step(dL, dC, dH) {
  return { dL, dC, dH };
}

function run(name, direction, cells, start, fixedStep) {
  return { name, direction, cells, start, step: fixedStep };
}

function normH(value) {
  const wrapped = value % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

function colorAt(oneRun, position) {
  return color(
    oneRun.start.L + oneRun.step.dL * position,
    oneRun.start.c + oneRun.step.dC * position,
    oneRun.start.h + oneRun.step.dH * position,
  );
}

const PANORAMA_ROOT = run(
  "panorama-root",
  "h",
  h(ROOT_ROW, 0, 4),
  color(0.68, 0.085, 195),
  step(-0.01, 0, 40),
);

function panoramaRoot(panelIndex) {
  return run(
    "root",
    "h",
    h(ROOT_ROW, 0, 4),
    colorAt(PANORAMA_ROOT, panelIndex * 5),
    PANORAMA_ROOT.step,
  );
}

function runThrough(name, direction, cells, intersectionPosition, intersectionColor, fixedStep) {
  return run(
    name,
    direction,
    cells,
    color(
      intersectionColor.L - fixedStep.dL * intersectionPosition,
      intersectionColor.c - fixedStep.dC * intersectionPosition,
      intersectionColor.h - fixedStep.dH * intersectionPosition,
    ),
    fixedStep,
  );
}

function challengeRuns() {
  const root = panoramaRoot(3);
  const left = runThrough("left-t", "v", v(1, 1, 4), 3, colorAt(root, 1), step(-0.07, -0.003, 55));
  const right = runThrough("right-t", "v", v(3, 4, 8), 0, colorAt(root, 3), step(-0.055, -0.012, -35));
  const upper = runThrough("upper-bar", "h", h(1, 0, 3), 1, colorAt(left, 0), step(-0.0579115, 0.0003067, 2.5220971));
  const lower = runThrough("lower-bar", "h", h(8, 1, 4), 2, colorAt(right, 4), step(-0.015, -0.005, -55));
  const upperCross = runThrough("upper-cross", "v", v(3, 0, 2), 1, colorAt(upper, 3), step(0.0363509, -0.0290983, -28.6788129));
  const lowerCross = runThrough("lower-cross", "v", v(1, 7, 9), 1, colorAt(lower, 0), step(-0.06, 0.01, -6));
  return [root, left, right, upper, lower, upperCross, lowerCross];
}

function welcomeRuns() {
  const root = panoramaRoot(4);
  const left = runThrough("left-column", "v", v(0, 1, 4), 3, colorAt(root, 0), step(-0.05, 0, 45));
  const center = runThrough("center-column", "v", v(2, 4, 7), 0, colorAt(root, 2), step(-0.06, -0.015, 20));
  const right = runThrough("right-column", "v", v(4, 1, 4), 3, colorAt(root, 4), step(0.06, 0.01, -20));
  const upper = runThrough("upper-bar", "h", h(1, 0, 2), 0, colorAt(left, 0), step(0.10, -0.02, -20));
  const lower = runThrough("lower-bar", "h", h(7, 2, 4), 0, colorAt(center, 3), step(0.07, 0.015, -70));
  const crown = runThrough("crown", "v", v(2, 0, 2), 1, colorAt(upper, 2), step(-0.025, 0.01, -50));
  return [root, left, center, right, upper, lower, crown];
}

function toLab(oneColor) {
  const radians = oneColor.h * Math.PI / 180;
  return {
    L: oneColor.L,
    a: oneColor.c * Math.cos(radians),
    b: oneColor.c * Math.sin(radians),
  };
}

function toLinearRGB(oneColor) {
  const radians = oneColor.h * Math.PI / 180;
  const a = oneColor.c * Math.cos(radians);
  const b = oneColor.c * Math.sin(radians);
  const lPrime = oneColor.L + 0.3963377774 * a + 0.2158037573 * b;
  const mPrime = oneColor.L - 0.1055613458 * a - 0.0638541728 * b;
  const sPrime = oneColor.L - 0.0894841775 * a - 1.2914855480 * b;
  const ll = lPrime ** 3;
  const mm = mPrime ** 3;
  const ss = sPrime ** 3;
  return {
    r: 4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
    g: -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
    b: -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
  };
}

function linearRGBToLab(rgb) {
  const l = 0.4122214708 * rgb.r + 0.5363325363 * rgb.g + 0.0514459929 * rgb.b;
  const m = 0.2119034982 * rgb.r + 0.6806995451 * rgb.g + 0.1073969566 * rgb.b;
  const s = 0.0883024619 * rgb.r + 0.2817188376 * rgb.g + 0.6299787005 * rgb.b;
  const lPrime = Math.cbrt(l);
  const mPrime = Math.cbrt(m);
  const sPrime = Math.cbrt(s);
  return {
    L: 0.2104542553 * lPrime + 0.7936177850 * mPrime - 0.0040720468 * sPrime,
    a: 1.9779984951 * lPrime - 2.4285922050 * mPrime + 0.4505937099 * sPrime,
    b: 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.8086757660 * sPrime,
  };
}

const CB_MATRICES = {
  protanopia: [
    0.152286, 1.052583, -0.204868,
    0.114503, 0.786281, 0.099216,
    -0.003882, -0.048116, 1.051998,
  ],
  deuteranopia: [
    0.367322, 0.860646, -0.227968,
    0.280085, 0.672501, 0.047413,
    -0.011820, 0.042940, 0.968881,
  ],
  tritanopia: [
    1.255528, -0.076749, -0.178779,
    -0.078411, 0.930809, 0.147602,
    0.004733, 0.691367, 0.303900,
  ],
};

function labUnderMode(oneColor, mode) {
  if (mode === "none") return toLab(oneColor);
  const rgb = toLinearRGB(oneColor);
  if (mode === "achromatopsia") {
    const luminance = 0.212656 * rgb.r + 0.715158 * rgb.g + 0.072186 * rgb.b;
    return linearRGBToLab({ r: luminance, g: luminance, b: luminance });
  }
  const matrix = CB_MATRICES[mode];
  ensure(matrix, `Unknown color-vision mode: ${mode}`);
  return linearRGBToLab({
    r: matrix[0] * rgb.r + matrix[1] * rgb.g + matrix[2] * rgb.b,
    g: matrix[3] * rgb.r + matrix[4] * rgb.g + matrix[5] * rgb.b,
    b: matrix[6] * rgb.r + matrix[7] * rgb.g + matrix[8] * rgb.b,
  });
}

function distance(a, b, mode = "none") {
  const p = labUnderMode(a, mode);
  const q = labUnderMode(b, mode);
  return 100 * Math.hypot(p.L - q.L, p.a - q.a, p.b - q.b);
}

function inUsableBand(oneColor) {
  return oneColor.L >= 0.24 && oneColor.L <= 0.86
    && oneColor.c >= 0.03 && oneColor.c <= 0.33;
}

function inGamut(oneColor) {
  const rgb = toLinearRGB(oneColor);
  const epsilon = 0.005;
  return [rgb.r, rgb.g, rgb.b].every((channel) => channel >= -epsilon && channel <= 1 + epsilon);
}

function encode(channel) {
  const clamped = Math.max(0, Math.min(1, channel));
  return clamped <= 0.0031308
    ? 12.92 * clamped
    : 1.055 * clamped ** (1 / 2.4) - 0.055;
}

function toHex(oneColor) {
  const rgb = toLinearRGB(oneColor);
  return `#${[rgb.r, rgb.g, rgb.b]
    .map((channel) => Math.round(encode(channel) * 255).toString(16).padStart(2, "0"))
    .join("")}`.toUpperCase();
}

function rgbToHex(rgb) {
  return `#${[rgb.r, rgb.g, rgb.b]
    .map((channel) => Math.round(encode(channel) * 255).toString(16).padStart(2, "0"))
    .join("")}`.toUpperCase();
}

function simulateVision(oneColor, mode) {
  const rgb = toLinearRGB(oneColor);
  if (mode === "achromatopsia") {
    const luminance = 0.212656 * rgb.r + 0.715158 * rgb.g + 0.072186 * rgb.b;
    return { r: luminance, g: luminance, b: luminance };
  }
  const matrix = CB_MATRICES[mode];
  ensure(matrix, `Unknown color-vision mode: ${mode}`);
  return {
    r: matrix[0] * rgb.r + matrix[1] * rgb.g + matrix[2] * rgb.b,
    g: matrix[3] * rgb.r + matrix[4] * rgb.g + matrix[5] * rgb.b,
    b: matrix[6] * rgb.r + matrix[7] * rgb.g + matrix[8] * rgb.b,
  };
}

function coordKey(coord) {
  return `${coord[0]},${coord[1]}`;
}

function closeEnough(a, b, mode = "none") {
  return distance(a, b, mode) < 2;
}

function validatePuzzle(puzzle) {
  const minimumDeltaE = puzzle.minimumDeltaE ?? MIN_DELTA_E;
  ensure(puzzle.runs.length >= 1 && puzzle.runs.length <= 7,
    `${puzzle.id}: generated puzzles must have one through seven gradients`);

  const occupancy = new Map();
  const colorsByRun = [];
  const intersections = new Set();

  puzzle.runs.forEach((oneRun, runIndex) => {
    ensure(oneRun.cells.length >= 3 && oneRun.cells.length <= 8,
      `${puzzle.id}/${oneRun.name}: gradient length must be 3...8`);
    ensure(["h", "v"].includes(oneRun.direction),
      `${puzzle.id}/${oneRun.name}: direction must be horizontal or vertical`);
    ensure(Math.abs(oneRun.step.dL) <= 0.16
      && Math.abs(oneRun.step.dC) <= 0.16
      && Math.abs(oneRun.step.dH) <= 70,
    `${puzzle.id}/${oneRun.name}: step exceeds Kromatika's hard cap`);
    ensure(Math.abs(oneRun.step.dL) + Math.abs(oneRun.step.dC) + Math.abs(oneRun.step.dH) > 0,
      `${puzzle.id}/${oneRun.name}: gradient cannot have a zero step`);

    const expectedDelta = oneRun.direction === "h" ? [0, 1] : [1, 0];
    for (let position = 1; position < oneRun.cells.length; position += 1) {
      const prior = oneRun.cells[position - 1];
      const current = oneRun.cells[position];
      ensure(current[0] - prior[0] === expectedDelta[0]
        && current[1] - prior[1] === expectedDelta[1],
      `${puzzle.id}/${oneRun.name}: gradient cells must be straight and contiguous`);
    }

    const runColors = oneRun.cells.map((_, position) => colorAt(oneRun, position));
    colorsByRun.push(runColors);
    runColors.forEach((oneColor, position) => {
      ensure(inUsableBand(oneColor),
        `${puzzle.id}/${oneRun.name}[${position}]: color left Kromatika's usable OKLCh band`);
      ensure(inGamut(oneColor),
        `${puzzle.id}/${oneRun.name}[${position}]: marketing color is outside sRGB gamut`);
    });

    const overlaps = oneRun.cells
      .map((coord, position) => ({ coord, position, owners: occupancy.get(coordKey(coord)) }))
      .filter(({ owners }) => owners);

    if (runIndex === 0) {
      ensure(overlaps.length === 0, `${puzzle.id}: root gradient must start on an empty grid`);
    } else {
      ensure(overlaps.length === 1,
        `${puzzle.id}/${oneRun.name}: every branch must cross exactly one earlier gradient`);
      const overlap = overlaps[0];
      ensure(overlap.owners.length === 1,
        `${puzzle.id}/${oneRun.name}: cannot branch from an existing intersection`);
      const parent = puzzle.runs[overlap.owners[0].runIndex];
      ensure(parent.direction !== oneRun.direction,
        `${puzzle.id}/${oneRun.name}: branches must be perpendicular to their parent`);
      const childColor = runColors[overlap.position];
      const parentColor = colorsByRun[overlap.owners[0].runIndex][overlap.owners[0].position];
      ensure(distance(childColor, parentColor) < 0.05,
        `${puzzle.id}/${oneRun.name}: shared intersection colors do not match exactly`);
      intersections.add(coordKey(overlap.coord));

      const sharedKey = coordKey(overlap.coord);
      for (const coord of oneRun.cells) {
        const key = coordKey(coord);
        if (key === sharedKey) continue;
        ensure(!occupancy.has(key), `${puzzle.id}/${oneRun.name}: non-intersection cell is occupied`);
        for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
          const neighborKey = `${coord[0] + dr},${coord[1] + dc}`;
          if (neighborKey === sharedKey) continue;
          ensure(!occupancy.has(neighborKey),
            `${puzzle.id}/${oneRun.name}: violates Kromatika's sparse-crossword adjacency rule`);
        }
      }
    }

    oneRun.cells.forEach((coord, position) => {
      const key = coordKey(coord);
      const owners = occupancy.get(key) ?? [];
      owners.push({ runIndex, position });
      ensure(owners.length <= 2, `${puzzle.id}: a cell cannot belong to more than two gradients`);
      occupancy.set(key, owners);
    });
  });

  const rows = [...occupancy.keys()].map((key) => Number(key.split(",")[0]));
  const cols = [...occupancy.keys()].map((key) => Number(key.split(",")[1]));
  ensure(Math.max(...rows) - Math.min(...rows) + 1 <= 11
    && Math.max(...cols) - Math.min(...cols) + 1 <= 11,
  `${puzzle.id}: puzzle exceeds Kromatika's 11-cell marketing grid`);

  const boardColors = new Map();
  for (const [key, owners] of occupancy) {
    const owner = owners[0];
    boardColors.set(key, colorsByRun[owner.runIndex][owner.position]);
  }

  const minDeltaByMode = {};
  for (const mode of puzzle.validationModes) {
    const entries = [...boardColors.entries()];
    let minimum = Number.POSITIVE_INFINITY;
    for (let first = 0; first < entries.length; first += 1) {
      for (let second = first + 1; second < entries.length; second += 1) {
        const delta = distance(entries[first][1], entries[second][1], mode);
        minimum = Math.min(minimum, delta);
        ensure(delta >= minimumDeltaE,
          `${puzzle.id}: ${entries[first][0]} and ${entries[second][0]} are only DeltaE ${delta.toFixed(2)} in ${mode}`);
      }
    }
    minDeltaByMode[mode] = Number(minimum.toFixed(2));

    puzzle.runs.forEach((oneRun, runIndex) => {
      const runColors = colorsByRun[runIndex];
      let differsFromReverse = false;
      for (let position = 0; position < runColors.length; position += 1) {
        if (!closeEnough(runColors[position], runColors[runColors.length - 1 - position], mode)) {
          differsFromReverse = true;
          break;
        }
      }
      ensure(differsFromReverse, `${puzzle.id}/${oneRun.name}: perceptually palindromic in ${mode}`);
    });
  }

  const locked = new Set();
  puzzle.runs.forEach((oneRun, runIndex) => {
    const positions = [0, oneRun.cells.length - 1,
      ...Array.from({ length: oneRun.cells.length - 2 }, (_, index) => index + 1)];
    const canLock = (position, avoidIntersection) => {
      const key = coordKey(oneRun.cells[position]);
      const mirrored = oneRun.cells.length - 1 - position;
      return !locked.has(key)
        && (!avoidIntersection || !intersections.has(key))
        && distance(colorsByRun[runIndex][position], colorsByRun[runIndex][mirrored], "none") >= 2;
    };
    const chosen = positions.find((position) => canLock(position, true))
      ?? positions.find((position) => canLock(position, false));
    ensure(chosen !== undefined, `${puzzle.id}/${oneRun.name}: could not place an orientation lock`);
    locked.add(coordKey(oneRun.cells[chosen]));
  });
  ensure(locked.size / boardColors.size <= 0.4,
    `${puzzle.id}: theoretical start state would lock more than 40% of the board`);
  puzzle.runs.forEach((oneRun) => {
    ensure(oneRun.cells.some((coord) => !locked.has(coordKey(coord))),
      `${puzzle.id}/${oneRun.name}: every gradient must retain a free cell`);
  });

  function orientationMaskValid(mask, mode) {
    const proposed = new Map();
    for (let runIndex = 0; runIndex < puzzle.runs.length; runIndex += 1) {
      const oneRun = puzzle.runs[runIndex];
      const reversed = ((mask >> runIndex) & 1) === 1;
      oneRun.cells.forEach((coord, position) => {
        const key = coordKey(coord);
        const sourcePosition = reversed ? oneRun.cells.length - 1 - position : position;
        const intended = colorsByRun[runIndex][sourcePosition];
        if (locked.has(key) && !closeEnough(intended, boardColors.get(key), mode)) {
          proposed.set("invalid", true);
          return;
        }
        if (proposed.has(key) && !closeEnough(proposed.get(key), intended, mode)) {
          proposed.set("invalid", true);
          return;
        }
        proposed.set(key, intended);
      });
      if (proposed.has("invalid")) return false;
    }
    return true;
  }

  for (const mode of puzzle.validationModes) {
    let validMasks = 0;
    for (let mask = 0; mask < 2 ** puzzle.runs.length; mask += 1) {
      if (orientationMaskValid(mask, mode)) validMasks += 1;
    }
    ensure(validMasks === 1,
      `${puzzle.id}: lock and intersection structure has ${validMasks} solutions in ${mode}`);
  }

  return { occupancy, colorsByRun, boardColors, minDeltaByMode, locked };
}

const puzzles = [
  {
    id: "eye",
    validationModes: ["none"],
    runs: [panoramaRoot(0)],
  },
  {
    id: "access",
    validationModes: ["none"],
    runs: [panoramaRoot(1)],
  },
  {
    id: "calm",
    validationModes: ["none"],
    runs: [
      panoramaRoot(2),
      runThrough(
        "cell-two-column",
        "v",
        v(1, 2, 6),
        2,
        colorAt(panoramaRoot(2), 1),
        step(0.07, 0, 0),
      ),
      runThrough(
        "cell-four-column",
        "v",
        v(3, 2, 6),
        2,
        colorAt(panoramaRoot(2), 3),
        step(-0.07, 0, 0),
      ),
    ],
  },
  {
    id: "challenge",
    validationModes: ["none"],
    minimumDeltaE: 3.5,
    runs: challengeRuns(),
  },
  {
    id: "welcome",
    validationModes: ["none"],
    minimumDeltaE: 3.5,
    runs: welcomeRuns(),
  },
];

const puzzleValidation = new Map(puzzles.map((puzzle) => [puzzle.id, validatePuzzle(puzzle)]));

function intersectionsFor(puzzle) {
  const counts = new Map();
  for (const oneRun of puzzle.runs) {
    for (const coord of oneRun.cells) {
      const key = coordKey(coord);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  return new Set([...counts.entries()].filter(([, count]) => count === 2).map(([key]) => key));
}

function puzzleNodes(puzzle, prefix) {
  const validation = puzzleValidation.get(puzzle.id);
  const intersections = intersectionsFor(puzzle);
  return [...validation.boardColors.entries()].map(([key, oneColor]) => {
    const [row, column] = key.split(",").map(Number);
    return tile(
      `${prefix}_tile`,
      GRID_X + column * PITCH,
      GRID_Y + row * PITCH,
      toHex(oneColor),
      TILE,
      19,
      { name: intersections.has(key) ? "Shared intersection" : undefined },
    );
  });
}

function grayBranchColors(puzzle, column, steps = 3) {
  const source = colorAt(puzzle.runs[0], column);
  return Array.from({ length: steps }, (_, index) => {
    const progress = (index + 1) / steps;
    return color(
      source.L + (SHARED_GRAY.L - source.L) * progress,
      source.c * (1 - progress),
      source.h,
    );
  });
}

function grayBranchNodes(puzzle, prefix, column, direction) {
  return grayBranchColors(puzzle, column).map((oneColor, index) => {
    const distanceFromRoot = index + 1;
    const row = ROOT_ROW + (direction === "down" ? distanceFromRoot : -distanceFromRoot);
    return tile(
      prefix,
      GRID_X + column * PITCH,
      GRID_Y + row * PITCH,
      toHex(oneColor),
      TILE,
      19,
      { name: `Cell ${column + 1} gradient to shared gray` },
    );
  });
}

function rootHexes(puzzle) {
  return puzzle.runs[0].cells.map((_, position) => toHex(colorAt(puzzle.runs[0], position)));
}

function miniRow(prefix, x, y, colors, size = 24, gap = 4) {
  return colors.map((fill, index) => tile(prefix, x + index * (size + gap), y, fill, size, 7));
}

function screenshotScreen(screenId, name, puzzle, copyNodes) {
  const validation = puzzleValidation.get(puzzle.id);
  const modeSummary = Object.entries(validation.minDeltaByMode)
    .map(([mode, value]) => `${mode} ${value.toFixed(2)}`)
    .join(", ");
  return {
    id: screenId,
    name,
    frame: { preset: "iphone", w: FRAME_W, h: FRAME_H },
    note: `${puzzle.runs.length} legal straight gradients, ${validation.boardColors.size} unique cells, ${intersectionsFor(puzzle).size} shared intersections. Minimum DeltaE: ${modeSummary}. Fixed OKLCh steps, sparse-crossword geometry, sRGB gamut, <=40% locks, and a unique orientation mask all pass.`,
    root: {
      id: id(`${screenId}_root`),
      type: "free",
      dir: "free",
      pad: 0,
      w: "fill",
      h: "fill",
      children: [...puzzleNodes(puzzle, screenId), ...copyNodes],
    },
  };
}

function visionSourceColors() {
  const sourceRun = run(
    "vision-source",
    "h",
    h(0, 0, 4),
    color(0.32, 0.10, 255),
    step(0.12, -0.012, 22),
  );
  return sourceRun.cells.map((_, position) => colorAt(sourceRun, position));
}

function visionRows(prefix) {
  const source = visionSourceColors();
  const rows = [
    ["PROTAN", "protanopia"],
    ["DEUTAN", "deuteranopia"],
    ["TRITAN", "tritanopia"],
    ["ACHROMA", "achromatopsia"],
  ];
  return rows.flatMap(([label, mode], rowIndex) => [
    text(`${prefix}_${mode}_label`, label, 20, 500 + rowIndex * 62, {
      role: "caption",
      fontSize: 11,
      weight: 650,
      color: "muted",
      w: 78,
    }),
    ...source.map((oneColor, column) => tile(
      `${prefix}_${mode}_tile`,
      112 + column * 52,
      487 + rowIndex * 62,
      rgbToHex(simulateVision(
        color(labUnderMode(oneColor, mode).L, 0, 0),
        "achromatopsia",
      )),
      44,
      12,
      { name: `${label} gradient ${column + 1}` },
    )),
  ]);
}

function findNode(root, wantedId) {
  if (root.id === wantedId) return root;
  for (const child of root.children ?? []) {
    const result = findNode(child, wantedId);
    if (result) return result;
  }
  return null;
}

const scene = JSON.parse(await readFile(output, "utf8"));
const productPage = scene.screens.find((screen) => screen.id === "scr_store") ?? scene.screens[0];

const primaryCopy = findNode(productPage.root, "screenshot_primary_copy");
const primaryArt = findNode(productPage.root, "screenshot_primary_art");
const teaserCopy = findNode(productPage.root, "screenshot_teaser_copy");
const teaserImage = findNode(productPage.root, "screenshot_teaser_image");
const carousel = findNode(productPage.root, "screenshot_carousel");

if (!primaryCopy || !primaryArt || !teaserCopy || !teaserImage || !carousel) {
  throw new Error("The product-page blockout no longer has the expected screenshot nodes.");
}

primaryCopy.text = "got an eye\nfor color?";
primaryArt.name = "Validated first puzzle";
primaryArt.note = "Thumbnail of the first legal five-cell Kromatika root run.";
primaryArt.children = miniRow("page_eye", 7, 0, rootHexes(puzzles[0]));
teaserCopy.text = "...or\nmaybe not?";
teaserImage.type = "free";
teaserImage.dir = "free";
teaserImage.pad = 0;
teaserImage.name = "Three gradients converging on one gray";
teaserImage.note = "Unlabeled color gradients from cells two, three, and four converge on the same neutral gray.";
delete teaserImage.text;
teaserImage.children = [1, 2, 3].flatMap((column, rowIndex) => miniRow(
  `page_access_gray_${column}`,
  2,
  9 + rowIndex * 21,
  [toHex(colorAt(puzzles[1].runs[0], column)), ...grayBranchColors(puzzles[1], column)],
  15,
  3,
));
carousel.note = "All five frames align edge to edge as one panorama, with a single uninterrupted 25-cell OKLCh gradient from the first frame's left edge to the fifth frame's right edge.";
productPage.note = "Kromatika product page in the iOS App Store. The screenshot story progresses from simple perception through accessibility, calm, challenge, and ordered chromatic complexity.";

const eyeForColor = screenshotScreen(
  "scr_eye_for_color",
  "01 Got an eye for color?",
  puzzles[0],
  [
    text("eye_title", "got an eye\nfor color?", 20, 258, { fontSize: 34, w: 260 }),
    text("eye_brand", "kromatika", 286, 812, { role: "caption", fontSize: 12, weight: 600, color: "muted" }),
  ],
);

const accessibility = screenshotScreen(
  "scr_accessibility",
  "02 ...or maybe not?",
  puzzles[1],
  [
    text("access_title", "...or maybe\nnot?", 20, 20, { fontSize: 29, w: 130 }),
    ...grayBranchNodes(puzzles[1], "access_cell_two_gray", 1, "down"),
    ...grayBranchNodes(puzzles[1], "access_cell_three_gray", 2, "up"),
    ...grayBranchNodes(puzzles[1], "access_cell_four_gray", 3, "down"),
    text("access_brand", "kromatika", 286, 812, { role: "caption", fontSize: 12, weight: 600, color: "muted" }),
  ],
);
accessibility.note += " Cells two and four branch downward while cell three branches upward; all three regular gradients terminate at the exact same gray.";

const eyesRest = screenshotScreen(
  "scr_eyes_rest",
  "03 Give your eyes a rest",
  puzzles[2],
  [
    text("calm_title", "give your eyes\na rest", 20, 72, { fontSize: 32, w: 210 }),
    text("calm_brand", "kromatika", 286, 812, { role: "caption", fontSize: 12, weight: 600, color: "muted" }),
  ],
);

const challenge = screenshotScreen(
  "scr_challenge",
  "04 Or a challenge?",
  puzzles[3],
  [
    text("challenge_title", "or a\nchallenge?", 20, 419, { fontSize: 32, w: 210 }),
    text("challenge_brand", "kromatika", 286, 830, { role: "caption", fontSize: 12, weight: 600, color: "muted" }),
  ],
);

const welcome = screenshotScreen(
  "scr_welcome",
  "05 Either way, we are glad you are here",
  puzzles[4],
  [
    text("welcome_title", "either way,\nwe're glad\nyou're here", 241, 419, { fontSize: 27, w: 142 }),
    text("welcome_brand", "kromatika", 22, 812, { role: "caption", fontSize: 12, weight: 600, color: "muted" }),
  ],
);

scene.name = "Kromatika iOS App Store Story";
scene.screens = [productPage, eyeForColor, accessibility, eyesRest, challenge, welcome];
scene.legend = [
  "Story: easy perception, universal visibility, calm play, hard play, chromatic order.",
  "The five-cell root gradients on all five screenshot screens align at the same height and form one uninterrupted 25-cell OKLCh gradient from the first screen's left edge to the last screen's right edge.",
  "Every gradient is straight, contiguous, and generated from one fixed OKLCh step. New gradients cross exactly one earlier gradient at one matching-color cell and obey sparse-crossword adjacency.",
  "The second screen has no color-vision labels. Cells two and four branch down and cell three branches up, with each color fading through a regular gradient to the same neutral gray.",
  "Theoretical locks remain at or below 40%, leave every gradient playable, and produce exactly one valid orientation mask.",
  "Decorative background grids are intentionally omitted so every selectable rectangle represents visible screenshot content.",
  "Headlines sit in the negative-space corners made by the root gradients and their junctions.",
  "Final App Store screenshot exports remain 1320 by 2868 pixels. This Blockout scene works at logical iPhone points.",
];

await writeFile(output, `${JSON.stringify(scene, null, 1)}\n`, "utf8");
console.log(`wrote ${scene.screens.length} screens to ${output}`);
for (const puzzle of puzzles) {
  const validation = puzzleValidation.get(puzzle.id);
  console.log(`${puzzle.id}: ${puzzle.runs.length} gradients, ${validation.boardColors.size} cells, min DeltaE ${JSON.stringify(validation.minDeltaByMode)}`);
}
