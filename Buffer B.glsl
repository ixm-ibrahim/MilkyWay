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
vec3 getStarInCell_old(int faceIdx, vec2 cellID, vec3 viewDir, float pixelScale)
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

bool getStarInCell(int faceIdx, vec2 cellID, out Star star)
{
    // 1. Deterministic Seed
    vec3 cellHashSeed = vec3(cellID, faceIdx);
    vec3 rng = hash33(cellHashSeed);
    
    // 2. Probability Check
    if (rng.x > STAR_PROBABILITY) return false;
    
    // 3. Generate Properties
    // Unique ID for consistency
    star.id = rng.x + rng.y + float(faceIdx); 

    // Position: Jitter within cell
    vec2 cellUV = (cellID + 0.1 + 0.8 * rng.yz) / STAR_GRID_SCALE;
    CubeMapFace face = initCubeMapFace(faceIdx, cellUV);
    star.direction = getDirFromCubemap(face);
    
    // Magnitude: Exponential distribution
    float magRng = fract(rng.x * 123.45);
    star.magnitude = mix(STAR_MAGNITUDE_MIN, STAR_MAGNITUDE_MAX, magRng * magRng);
    
    // Temperature: Random distribution (2000K to 12000K)
    // We skew slightly towards cooler (red/yellow) stars as they are more common, 
    // but blue stars are brighter.
    float tempRng = fract(rng.y * 456.78);
    star.tempKelvin = mix(2000.0, STAR_COLOR_KELVIN_MAX, tempRng);
    
    // Pre-calculate Radiance (Energy)
    star.radiance = vec3(magnitudeToRadiance(star.magnitude));
    
    return true;
}

vec3 renderStar(Star star, vec3 viewDir, float pixelScale)
{
    // 1. Angle Calculation
    // For small angles, the length of the cross product is sin(theta) ~ theta.
    // This is numerically stable and faster than acos(dot).
    vec3 cp = cross(viewDir, star.direction);
    float angleRadians = length(cp);
    
    // Optimization: Coarse culling
    // If the star is further than, say, 10 pixels away, don't compute exp().
    // We use the pixel scale to determine this threshold.
    float cullAngle = pixelScale * STAR_PSF_CUTOFF_PIXELS;
    if (angleRadians > cullAngle) return BLACK;
    
    // 2. Screen Space Conversion (The M5 Key)
    // How many pixels away is the star center from the current pixel center?
    float rPixels = angleRadians / pixelScale;
    
    // 3. Point Spread Function (Gaussian)
    // I = I_0 * exp( -r^2 / (2 * sigma^2) )
    // sigma is the "width" of the star in pixels.
    float sigma = STAR_PSF_SIGMA_PIXELS; 
    
    // We allow very bright stars to bleed slightly more (simulating glare/bloom "pre-pass")
    // by modifying sigma slightly based on brightness, or just keeping it pure.
    // Let's keep it pure for M5:
    float falloff = exp(-(rPixels * rPixels) / (2.0 * sigma * sigma));
    
    // We multiply by a smooth envelope that goes from 1.0 to 0.0 
    // as we approach the cull radius.
    // This prevents the "pop" when a star enters/exits the search radius.
    float edgeFade = smoothstep(1.0, 0.0, rPixels / STAR_PSF_CUTOFF_PIXELS);
    
    // 4. Color Calculation
    vec3 starColor = blackbodyToColor(star.tempKelvin);
    
    // 5. Final Radiance
    // We multiply the star's total energy by the PSF falloff.
    // Note: Technically, the integral of the PSF should normalize to 1.
    // But since we are tuning artistically, we just multiply.
    return star.radiance * starColor * falloff * edgeFade;
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
            //totalRadiance += getStarInCell(cubeMapFace.id, neighborID, dirCelestial, pixelScale);
            
            // Get Star Data
            Star star;
            bool exists = getStarInCell(cubeMapFace.id, neighborID, star);
            
            if (exists)
            {
                // Render Star with PSF
                totalRadiance += renderStar(star, dirCelestial, pixelScale);
            }
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
    
    // --- CORRECTION START ---
    // Fix Rectilinear Stretching at wide FOVs.
    // We calculate how far "off-center" this pixel is using the dot product.
    // forward dot dir = 1.0 at center, < 1.0 at edges.
    float cosTheta = dot(dirWorld, camera.orientation.forward);
    
    // We tighten the scale by cos^2 to counteract the tan^2 projection stretching.
    // This tricks the PSF into thinking pixels at the edge are "worth" more angle,
    // keeping the star size constant in screen space.
    camera.pixelScale *= (cosTheta * cosTheta);
    // --- CORRECTION END ---
    
    // 3. Evaluate Stars
    vec3 starRadiance = evalStars(dirCelestial, camera.pixelScale);
    
    // 4. Output HDR
    fragColor = toFrag(starRadiance);
}