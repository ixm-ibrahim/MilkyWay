// ============================================================================
// BUFFER C
// M0: scaffolding pass. Produces HDR radiance for Milky Way later.
// M7: Milky Way (core) — implemented incrementally (7.2 starts with the mask).
// ============================================================================

/*------------------------------------------
               Control Panel
--------------------------------------------*/

#define TEST_BUFFER_C_WIRING 0

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
#if TEST_BUFFER_C_WIRING
    fragColor = toFrag(DIM_GREEN);
    return;
#endif

    float time = getTimeSeconds(iTime);
    Camera camera = initCamera(fragCoord, iResolution, iMouse);
    CelestialSphere celestialSphere = initCelestialSphere(camera, time);

    // 1) Milky Way frame + galactic UV for this view ray
    MilkyWay mw = initMilkyWay(celestialSphere);

    // M7.2 output policy:
    // - Normal render stays black until disk/bulge are implemented (M7.3+).

    fragColor = toFrag(mw.mask);
}
