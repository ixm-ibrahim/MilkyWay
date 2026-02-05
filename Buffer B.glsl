// ============================================================================
// BUFFER B
// M0: scaffolding pass. Produces HDR radiance for stars.
// M4: Starfield Generator (Deterministic) + Magnitude Distribution
// ============================================================================

/*------------------------------------------
                 Constants
--------------------------------------------*/



/*------------------------------------------
               Control Panel
--------------------------------------------*/

#define TEST_BUFFER_B_WIRING 0

/*------------------------------------------
                 Structures
--------------------------------------------*/



/*------------------------------------------
                 Functions
--------------------------------------------*/

// Core function: Is there a star in this grid cell?
// If so, return its data. If not, return 0 brightness.
vec3 getStarInCell(int faceIdx, vec2 cellID, vec3 viewDir, float pixelScale)
{
    // 1. Deterministic Seed for this cell
    vec3 cellHashSeed = vec3(cellID, faceIdx);
    
    // 2. Hash to check probability
    vec3 rng = hash33(cellHashSeed);
    
    if (rng.x > STAR_PROBABILITY) return BLACK; // Empty cell
    
    // 3. Generate Star Properties
    // Position: Jitter the star within the cell (0.1 to 0.9 to avoid edges)
    vec2 cellUV = (cellID + 0.1 + 0.8 * rng.yz) / STAR_GRID_SCALE;
    
    // Make CubeMapFace struct
    CubeMapFace cubeMapFace = initCubeMapFace(faceIdx, cellUV);
    
    vec3 starDir = getDirFromCubemap(cubeMapFace);
    // ------------------------------------------------
    
    // Magnitude: Exponential distribution (lots of faint, few bright)
    float magRng = fract(rng.x * 123.45); 
    float magnitude = mix(STAR_MAGNITUDE_MIN, STAR_MAGNITUDE_MAX, magRng * magRng);
    float brightness = magnitudeToRadiance(magnitude);

    // A. Coarse Check (Dot Product)
    // We still use dot product for the "Are we even close?" check because it's cheap.
    float cosTheta = dot(viewDir, starDir);
    if (cosTheta < ALMOST_ONE_4) return BLACK; // Optimization exit
    
    // B. Precise Angle (Cross Product)
    // For small angles, sin(theta) ~ theta.
    // The length of the cross product gives us sin(theta).
    // This avoids the acos(1.0) singularity and precision noise.
    vec3 cp = cross(viewDir, starDir);
    float angle = length(cp);
    
    // Simple "Draw a Dot" logic (M4 Placeholder)
    float radius = pixelScale * 1.5; // 1.5 pixels wide
    float intensity = brightness * max(0.0, one_minus(angle / radius));
    
    return vec3(intensity);
}

// Iterate through the grid to find stars near the current pixel ray
vec3 evalStars(vec3 dirCelestial, float pixelScale) {
    
    // 1. Get our grid coordinates
    CubeMapFace cubeMapFace = getCubeMapFace(dirCelestial);
    
    // Scale UV to grid coordinates
    vec2 gridPos = cubeMapFace.uv * STAR_GRID_SCALE;
    vec2 centerID = floor(gridPos);
    
    vec3 totalRadiance = BLACK;
    
    // 2. Neighbor Search (3x3)
    // We must check neighbors because a star in the next cell 
    // might overlap into our pixel view.
    for (int x = -STAR_ADJACENT_NEIGHBORS; x <= STAR_ADJACENT_NEIGHBORS; x++)
    {
        for (int y = -STAR_ADJACENT_NEIGHBORS; y <= STAR_ADJACENT_NEIGHBORS; y++)
        {
            vec2 neighborID = centerID + vec2(x, y);
            
            // Valid integer cell range: [0, STAR_GRID_SCALE-1]
            if (neighborID.x < 0.0 || neighborID.y < 0.0 ||
                neighborID.x >= STAR_GRID_SCALE || neighborID.y >= STAR_GRID_SCALE)
            {
                continue;
            }
            
            // Handle wrapping? 
            // For a simple Cubemap, wrapping edges to other faces is complex.
            // For "Fast > Accurate", we just clamp or ignore edge stars.
            // They will just pop-in/out at the very edge of the 90-degree face.
            // This is acceptable for M4.
            
            // Check star in this neighbor cell
            totalRadiance += getStarInCell(cubeMapFace.id, neighborID, dirCelestial, pixelScale);
        }
    }
    
    return totalRadiance;
}

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
#if TEST_BUFFER_B_WIRING
    fragColor = toFrag(DIM_YELLOW);
    return;
#endif

    Camera camera = initCamera(fragCoord, iResolution);
    
    // Apply Debug Pan if enabled (so we can test star stability)
#if (DEBUG_MODE == DEBUG_CAMERA_PAN)
    camera = applyDebugCameraPan(camera, getTimeSeconds(iTime), iResolution);
#endif

    // 1. Get World Ray
    vec3 dirWorld = camera.rayDirection;
    
    // 2. Apply Celestial Rotation (M2) to get Celestial Ray
    // The stars are fixed to the Celestial Sphere, which rotates.
    vec3 dirCelestial = getCelestialRay(dirWorld, getTimeSeconds(iTime));

    // 3. Evaluate Stars
    vec3 starRadiance = evalStars(dirCelestial, camera.pixelScale);
    
    // 4. Output HDR
    fragColor = toFrag(starRadiance);
}