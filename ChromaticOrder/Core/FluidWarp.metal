//  Fluid-warp distortion shader for the solved-puzzle celebration.
//  SwiftUI's .distortionEffect feeds in each pixel's position and
//  expects us to return the position we'd like the renderer to sample
//  the rasterized view from. Displacing that position by a smooth
//  time-varying vector field gives the colors a fluid "smear" — like
//  ink flowing in water — without running an actual Navier-Stokes
//  simulation.
//
//  Two sine-based octaves are summed: a broad, slow-swirling flow for
//  large-scale motion, and a finer higher-frequency layer for detail.
//  `amplitude` drives the displacement magnitude; 0 is identity (the
//  effect is a no-op), and the caller ramps it up + back down over
//  the solve celebration so the grid gently "blooms and settles."

#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] float2 fluidWarp(float2 position,
                                  float time,
                                  float amplitude) {
    // Coarse flow — low spatial frequency, slow time sweep. The two
    // components are driven by perpendicular axes so the field rotates
    // slightly instead of just sliding.
    float2 p1 = position * 0.012;
    float2 flow1 = float2(
        sin(p1.y * 4.5 + time * 1.10),
        cos(p1.x * 4.0 + time * 0.80 + 1.7)
    );
    // Fine ripple — higher frequency, different phase. Half-weighted
    // so it decorates the primary flow without overpowering it.
    float2 p2 = position * 0.034;
    float2 flow2 = float2(
        sin(p2.y * 3.2 - time * 1.90 + 2.3),
        cos(p2.x * 3.6 + time * 1.60 + 0.4)
    ) * 0.45;
    return position + (flow1 + flow2) * amplitude;
}
