// ============================================================================
// BUFFER D
// M0: passthrough/post stage.
// For now: simply composites Buffer A + Buffer B + Buffer C into one HDR buffer.
// ============================================================================

/*------------------------------------------
               Control Panel
--------------------------------------------*/

#define TEST_BUFFER_D_WIRING 0

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
#if TEST_BUFFER_D_WIRING
    fragColor = toFrag(DIM_BLUE); return;
#endif

    vec2 uv = getUV(fragCoord, iResolution);

    // Get results from previous buffers
    vec3 hdrA = texture(iChannel0, uv).rgb; // Buffer A
    vec3 hdrB = texture(iChannel1, uv).rgb; // Buffer B
    vec3 hdrC = texture(iChannel2, uv).rgb; // Buffer C
    vec3 hdr  = hdrA + hdrB + hdrC;
    
    // Ourput result
    fragColor = toFrag(hdr);
}
