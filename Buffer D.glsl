// ============================================================================
// BUFFER D
// M9: Post (Bloom/Glare) + Exposure + Tonemap + Gamma + Dither.
// Produces LDR (display-ready) output.
// ============================================================================

/*------------------------------------------
               Control Panel
--------------------------------------------*/

// Verification toggles
#define TEST_BUFFER_D_WIRING 0
#define TEST_BLOOM_ONLY      0
#define TEST_HDR_HEATMAP     0

// Post toggles
#define ENABLE_BLOOM         1
#define ENABLE_DITHER        1

// Exposure / Tonemap controls (start simple: fixed exposure)
#define EXPOSURE             1.25   // Raise/lower overall brightness
#define GAMMA                2.2

// Bloom controls (cheap multi-tap blur)
#define BLOOM_THRESHOLD      1.25   // Luminance threshold in HDR (pre-exposure)
#define BLOOM_SOFT_KNEE      0.75   // Smooth transition width
#define BLOOM_INTENSITY      0.35   // How much bloom is added back
#define BLOOM_RADIUS_PIXELS  1.75   // Blur radius in pixels (small = subtle halos)

/*------------------------------------------
              Local Utilities
--------------------------------------------*/

float luminance(vec3 c)
{
    // Rec.709 / sRGB luminance
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float softThreshold(float x, float threshold, float knee)
{
    // Smoothly ramps from 0 to 1 around the threshold to avoid hard edges.
    // knee = 0 -> hard threshold.
    if (knee <= 0.0) return step(threshold, x);

    float t0 = threshold - knee;
    float t1 = threshold + knee;
    return saturate((x - t0) / (t1 - t0));
}

vec3 acesTonemap(vec3 x)
{
    // Cheap, widely-used ACES fitted curve (good default for star HDR).
    // Works per-channel; assumes x is scene-referred linear HDR.
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

vec3 applyGamma(vec3 ldr)
{
    return pow(max(ldr, 0.0), vec3(1.0 / GAMMA));
}

vec3 sampleHDRComposite(vec2 uv)
{
    // Composite in HDR space
    vec3 hdrA = ENABLE_BUFFER_A ? texture(iChannel0, uv).rgb : BLACK; // Buffer A
    vec3 hdrB = ENABLE_BUFFER_B ? texture(iChannel1, uv).rgb : BLACK; // Buffer B
    vec3 hdrC = ENABLE_BUFFER_C ? texture(iChannel2, uv).rgb : BLACK; // Buffer C
    
    return hdrA + hdrB + hdrC;
}

vec3 bloomAt(vec2 uv, vec2 texel)
{
    // 9-tap “tiny glare” kernel. Intentionally small and cheap.
    // We only bloom bright HDR contributions (integrated glow around bright stars).
    vec3 s0 = sampleHDRComposite(uv);
    vec3 s1 = sampleHDRComposite(uv + vec2( texel.x, 0.0));
    vec3 s2 = sampleHDRComposite(uv + vec2(-texel.x, 0.0));
    vec3 s3 = sampleHDRComposite(uv + vec2(0.0,  texel.y));
    vec3 s4 = sampleHDRComposite(uv + vec2(0.0, -texel.y));
    vec3 s5 = sampleHDRComposite(uv + vec2( texel.x,  texel.y));
    vec3 s6 = sampleHDRComposite(uv + vec2(-texel.x,  texel.y));
    vec3 s7 = sampleHDRComposite(uv + vec2( texel.x, -texel.y));
    vec3 s8 = sampleHDRComposite(uv + vec2(-texel.x, -texel.y));

    // Convert each sample into “bloom contribution” via soft threshold on luminance.
    float w0 = softThreshold(luminance(s0), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w1 = softThreshold(luminance(s1), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w2 = softThreshold(luminance(s2), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w3 = softThreshold(luminance(s3), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w4 = softThreshold(luminance(s4), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w5 = softThreshold(luminance(s5), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w6 = softThreshold(luminance(s6), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w7 = softThreshold(luminance(s7), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);
    float w8 = softThreshold(luminance(s8), BLOOM_THRESHOLD, BLOOM_SOFT_KNEE);

    // Kernel weights: center-heavy to keep halos subtle and local.
    vec3 bloom =
          s0 * (w0 * 0.28)
        + s1 * (w1 * 0.12) + s2 * (w2 * 0.12)
        + s3 * (w3 * 0.12) + s4 * (w4 * 0.12)
        + s5 * (w5 * 0.06) + s6 * (w6 * 0.06)
        + s7 * (w7 * 0.06) + s8 * (w8 * 0.06);

    return bloom;
}

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
#if TEST_BUFFER_D_WIRING
    fragColor = toFrag(DIM_BLUE);
    return;
#endif

    vec2 uv = getUV(fragCoord, iResolution);

    // --------------------------------------------------------------------
    // Step 1) HDR composite (scene-referred, linear)
    // --------------------------------------------------------------------
    vec3 hdr = sampleHDRComposite(uv);

#if TEST_HDR_HEATMAP
    // Visualize HDR headroom (values > 1 should exist for bright stars)
    float y = luminance(hdr);
    // Simple pseudo-heatmap: 0..4 mapped to grayscale
    fragColor = toFrag(vec3(saturate(y / 4.0)));
    return;
#endif

    // --------------------------------------------------------------------
    // Step 2) Bloom (cheap glare) in HDR space
    // Scientifically: optics/eyes spread bright light into small halos.
    // Cheap: threshold + tiny blur kernel, then add back.
    // --------------------------------------------------------------------
    vec3 bloom = BLACK;

#if ENABLE_BLOOM
    vec2 texel = 1.0 / iResolution.xy;
    texel *= BLOOM_RADIUS_PIXELS;

    bloom = bloomAt(uv, texel);
#endif

#if TEST_BLOOM_ONLY
    fragColor = toFrag(bloom * BLOOM_INTENSITY);
    return;
#endif

    vec3 hdrPost = hdr + bloom * BLOOM_INTENSITY;

    // --------------------------------------------------------------------
    // Step 3) Exposure (simple scalar)
    // Scientifically: camera/eye exposure adapts; first pass = fixed control.
    // --------------------------------------------------------------------
    vec3 hdrExposed = hdrPost * EXPOSURE;

    // --------------------------------------------------------------------
    // Step 4) Tonemap (ACES) -> LDR linear
    // --------------------------------------------------------------------
    vec3 ldrLinear = acesTonemap(hdrExposed);

    // --------------------------------------------------------------------
    // Step 5) Dither (tiny noise before gamma/quantization)
    // Scientifically: helps hide banding in smooth gradients.
    // Cheap: hash noise in [−0.5, +0.5] at ~1/255 amplitude.
    // --------------------------------------------------------------------
#if ENABLE_DITHER
    // Stable per-pixel noise
    float n = hash12(fragCoord + vec2(17.0, 59.0)) - 0.5;
    ldrLinear += (n / 255.0);
    ldrLinear = saturate(ldrLinear);
#endif

    // --------------------------------------------------------------------
    // Step 6) Gamma (display transform)
    // --------------------------------------------------------------------
    vec3 ldr = applyGamma(ldrLinear);

    // Output result (LDR)
    fragColor = toFrag(ldr);
}
