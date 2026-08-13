"""OKLCh primitives — Python mirror of ChromaticOrder/Core/OKLCh.swift.

Kept numerically identical to the Swift version so the campaign builder's
validation (delta-E floors, gamut, usable band) agrees with what the app
measures at runtime. The XCTest audit re-checks everything against the
real Swift code; this module exists so design iteration is fast.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

# Usable perceptual band (OK.lMin ... OK.cMax in the Swift source).
L_MIN, L_MAX = 0.24, 0.86
C_MIN, C_MAX = 0.03, 0.33


@dataclass(frozen=True)
class OKLCh:
    L: float
    c: float
    h: float

    def with_(self, L=None, c=None, h=None) -> "OKLCh":
        return OKLCh(
            self.L if L is None else L,
            self.c if c is None else c,
            self.h if h is None else h,
        )


def norm_h(h: float) -> float:
    x = math.fmod(h, 360.0)
    return x + 360.0 if x < 0 else x


def to_lab(color: OKLCh) -> tuple[float, float, float]:
    hr = math.radians(color.h)
    return (color.L, color.c * math.cos(hr), color.c * math.sin(hr))


def dist(a: OKLCh, b: OKLCh) -> float:
    """Perceptual delta-E, scaled x100 (JND ~2, distinct ~10)."""
    pL, pa, pb = to_lab(a)
    qL, qa, qb = to_lab(b)
    dL = (pL - qL) * 100
    da = (pa - qa) * 100
    db = (pb - qb) * 100
    return math.sqrt(dL * dL + da * da + db * db)


def lab_dist(p: tuple[float, float, float], q: tuple[float, float, float]) -> float:
    dL = (p[0] - q[0]) * 100
    da = (p[1] - q[1]) * 100
    db = (p[2] - q[2]) * 100
    return math.sqrt(dL * dL + da * da + db * db)


def to_linear_rgb(color: OKLCh) -> tuple[float, float, float]:
    hr = math.radians(color.h)
    a = color.c * math.cos(hr)
    b = color.c * math.sin(hr)
    l_ = color.L + 0.3963377774 * a + 0.2158037573 * b
    m_ = color.L - 0.1055613458 * a - 0.0638541728 * b
    s_ = color.L - 0.0894841775 * a - 1.2914855480 * b
    ll, mm, ss = l_ ** 3, m_ ** 3, s_ ** 3
    return (
        4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
        -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
        -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    )


def in_gamut(color: OKLCh, eps: float = 0.005) -> bool:
    r, g, b = to_linear_rgb(color)
    return all(-eps <= v <= 1 + eps for v in (r, g, b))


def in_usable_band(color: OKLCh) -> bool:
    return L_MIN <= color.L <= L_MAX and C_MIN <= color.c <= C_MAX


def _encode(v: float) -> float:
    x = max(0.0, min(1.0, v))
    return 12.92 * x if x <= 0.0031308 else 1.055 * (x ** (1 / 2.4)) - 0.055


def to_srgb8(color: OKLCh) -> tuple[int, int, int]:
    r, g, b = to_linear_rgb(color)
    return tuple(int(round(_encode(v) * 255)) for v in (r, g, b))


def gamut_headroom(color: OKLCh) -> float:
    """How far inside the sRGB cube a color sits (negative = outside)."""
    r, g, b = to_linear_rgb(color)
    return min(min(r, g, b), 1 - max(r, g, b))
