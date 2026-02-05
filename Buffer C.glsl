// ============================================================================
// BUFFER C
// M0: scaffolding pass. Produces HDR radiance for Milky Way later.
// For now: black, plus an optional "wiring test" override.
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
    fragColor = toFrag(DIM_GREEN); return;
#endif

    fragColor = toFrag(BLACK);
}
