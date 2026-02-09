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

bool getStarInCell(int faceIdx, vec2 cellID, out Star star)
{
    // 1. Deterministic Seed
    vec3 cellHashSeed = vec3(cellID, faceIdx);
    vec3 rng = hash33(cellHashSeed);
    
    // 2. Probability Check
    if (rng.x >= STAR_PROBABILITY) return false;
    
    // 3. Generate Properties
    // Unique ID for consistency
    star.id = rng.x + rng.y + float(faceIdx); 

    // Position: Jitter within cell
    vec2 cellUV = (cellID + 0.1 + 0.8 * rng.yz) / STAR_GRID_SCALE;
    CubeMapFace face = initCubeMapFace(faceIdx, cellUV);
    star.direction = getDirFromCubemap(face);
    
    // Magnitude: Exponential distribution
    float magRng = fract(rng.x * 123.45);
    float distributionCurve = pow(magRng, STAR_BRIGHTNESS_CURVE_ADJUST);
    star.magnitude = mix(STAR_BRIGHTNESS_MIN, STAR_BRIGHTNESS_MAX, distributionCurve);
    
    // Temperature: Random distribution
    // We skew slightly towards cooler (red/yellow) stars as they are more common, 
    // but blue stars are brighter.
    float tempRng = pow(fract(rng.y * 456.78), STAR_COLOR_CURVE_ADJUST);
    star.tempKelvin = mix(STAR_COLOR_KELVIN_MIN, STAR_COLOR_KELVIN_MAX, tempRng);
    
    // Pre-calculate Radiance (Energy)
    star.radiance = vec3(magnitudeToRadiance(star.magnitude));
    
    return true;
}

float getAtmosphereTransmission(float altitude)
{
    // Returns a factor (0.0 to 1.0) of how much light survives the atmosphere.
    
    // 1. Air Mass Approximation
    // At zenith (alt=1.0), air mass = 1.
    // At horizon (alt=0.0), air mass approaches infinity.
    // We clamp altitude to 0.05 to prevent divide-by-zero (and because the simple math breaks at the true horizon).
    float airMass = 1.0 / max(0.05, abs(altitude));

    // 2. Beer-Lambert Law
    // Transmittance = exp(-optical_depth)
    return exp(-STAR_ATMOSPHERE_DENSITY_COEFF * airMass);
}

vec4 getAtmosphereTurbulence(float starID, float altitude, float time)
{
    float seed = starID * 12.345;
    
    // Turbulence increases at horizon (0 at zenith, 1 at horizon)
    float turbulence = 1.0 - altitude; 
    turbulence = 0.5 + 0.5 * turbulence; 

    // 1. Scintillation (Brightness)
    float phase = seed + time * STAR_SCINTILLATION_SPEED;
    float brightMult = 1.0 + (STAR_TWINKLE_STRENGTH * turbulence) * sin(phase);
    brightMult = max(0.0, brightMult);

    // 2. Seeing (Position Jitter Noise)
    // We generate 3D noise components -1.0 to 1.0
    // We scale the *amplitude* of this noise by altitude here
    float scale = turbulence; 
    
    vec3 jitterNoise = vec3(
        sin(phase * 1.1 + 43.0),
        cos(phase * 0.9 + 12.0),
        0.0
    );
    
    // Return brightness + raw jitter vector scaled by atmospheric turbulence
    return vec4(brightMult, jitterNoise * scale);
}

vec3 renderStar(Star star, vec3 viewDir, float pixelScale, float altitude, float time)
{
    // --- M6: Atmosphere Effects ---
    vec4 turb = getAtmosphereTurbulence(star.id, altitude, time);
    float brightMult = turb.x;
    vec3 jitterNoise = turb.yzw; // This is the random 3D wobble
    float transmission = getAtmosphereTransmission(altitude);

    // --- APPLY JITTER (The Fix) ---
    // Instead of hacking the radius, we perturb the star's 3D direction.
    // 1. Convert Jitter Strength (pixels) to Radians
    //    Direction is a unit vector. Adding a small vector ~radians.
    float jitterRad = (STAR_JITTER_STRENGTH * pixelScale);
    
    // 2. Apply noise to direction
    //    We add the tiny random vector to the star's direction and re-normalize.
    vec3 perturbedDir = normalize(star.direction + jitterNoise * jitterRad);

    // 1. Angle Calculation (Using the wobbling position)
    vec3 cp = cross(viewDir, perturbedDir);
    float angleRadians = length(cp);

    // Optimization: Coarse culling
    float cullAngle = pixelScale * STAR_PSF_CUTOFF_PIXELS;
    if (angleRadians > cullAngle) return BLACK;
    
    // 2. Screen Space Conversion
    float rPixels = angleRadians / pixelScale;
    
    // 3. Point Spread Function (Gaussian)
    float sigma = STAR_PSF_SIGMA_PIXELS; 
    float falloff = exp(-(rPixels * rPixels) / (2.0 * sigma * sigma));

    // Smooth envelope
    float edgeFade = smoothstep(1.0, 0.0, rPixels / STAR_PSF_CUTOFF_PIXELS);

    // 4. Color Calculation
    vec3 starColor = blackbodyToColor(star.tempKelvin);
    
    // 5. Final Radiance
    return star.radiance * starColor * falloff * edgeFade * transmission * brightMult;
}

vec3 evalUnresolvedStarsPatch(vec2 patchID, int faceID, float altitude)
{
    vec3 seed = vec3(patchID, float(faceID) * 19.31);
    vec3 total = BLACK;

    for (int i = 0; i < STAR_UNRESOLVED_SAMPLES_PER_PATCH; i++)
    {
        vec3 rng = hash33(seed + vec3(float(i) * 11.7, float(i) * 23.3, float(i) * 37.9));

        float u   = pow(rng.x, STAR_UNRESOLVED_BRIGHTNESS_ADJUST);
        float mag = mix(STAR_UNRESOLVED_BRIGHTNESS_MIN, STAR_UNRESOLVED_BRIGHTNESS_MAX, u);

        float radiance = magnitudeToRadiance(mag);

        float kelvin = mix(STAR_COLOR_KELVIN_MIN, STAR_COLOR_KELVIN_MAX, rng.y);
        vec3  color  = blackbodyToColor(kelvin);

        total += radiance * color;
    }

    total *= (1.0 / float(STAR_UNRESOLVED_SAMPLES_PER_PATCH));

    float transmission = getAtmosphereTransmission(altitude);
    return total * transmission;
}

vec3 evalUnresolvedStars(vec3 dirCelestial, float altitude)
{
    CubeMapFace face = getCubeMapFace(dirCelestial);

    // Continuous patch coordinates
    vec2 p = face.uv * STAR_UNRESOLVED_GRID_SCALE;

    // Integer patch base + fractional within-patch
    vec2 p0 = floor(p);
    vec2 f  = fract(p);

    // Smooth interpolation to hide block boundaries
    f = f * f * (3.0 - 2.0 * f); // smoothstep-like easing

    // Sample 4 neighboring patches and bilerp
    vec3 v00 = evalUnresolvedStarsPatch(p0 + vec2(0.0, 0.0), face.id, altitude);
    vec3 v10 = evalUnresolvedStarsPatch(p0 + vec2(1.0, 0.0), face.id, altitude);
    vec3 v01 = evalUnresolvedStarsPatch(p0 + vec2(0.0, 1.0), face.id, altitude);
    vec3 v11 = evalUnresolvedStarsPatch(p0 + vec2(1.0, 1.0), face.id, altitude);

    vec3 vx0 = mix(v00, v10, f.x);
    vec3 vx1 = mix(v01, v11, f.x);
    vec3 v   = mix(vx0, vx1, f.y);

    // TEMP scaling: clamp-only pipeline needs huge boost until M9 exposure/tonemap
    return v * STAR_UNRESOLVED_INTENSITY_SCALE;
}

// Iterate through the grid to find stars near the current pixel ray
vec3 evalStars(vec3 dirCelestial, float pixelScale, float altitude, float time)
{    
    // 1. Get our grid coordinates
    CubeMapFace cubeMapFace = getCubeMapFace(dirCelestial);

    // Scale UV to grid coordinates
    vec2 gridPos = cubeMapFace.uv * STAR_GRID_SCALE;
    vec2 centerID = floor(gridPos);

    vec3 totalRadiance = BLACK;
    
    // 2. Neighbor Search (3x3)
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
            
            // Get Star Data
            Star star;
            bool exists = getStarInCell(cubeMapFace.id, neighborID, star);
            
            if (exists)
            {
                // Render Star with PSF + M6 Atmosphere
                totalRadiance += renderStar(star, dirCelestial, pixelScale, altitude, time);
            }
        }
    }
    
    // --- Unresolved Stars: Integrated background starlight (no twinkle/jitter) ---
    totalRadiance += evalUnresolvedStars(dirCelestial, altitude);
    
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

    float time = getTimeSeconds(iTime);
    Camera camera = initCamera(fragCoord, iResolution, iMouse);
    CelestialSphere celestialSphere = initCelestialSphere(camera, time);
    
    // 1. Get World Ray
    vec3 dirWorld = camera.rayDirection;
    
    // 2. Altitude Calculation
    // Atmosphere is attached to Earth (World Space), not the rotating sky.
    // We clamp to 0.0 so stars below the horizon don't do weird math, 
    // though they are usually culled by the ground in a full scene.
    float altitude = max(0.0, dot(dirWorld, AXIS_UP));

#if STAR_RECTILINEAR_PROJETION
    // Rectilinear projection: angular size per pixel shrinks off-axis by cos^2(theta).
    // theta here is the angle from the *center* view ray.
    Camera camCenter = camera;
    camCenter.normalizedUV = vec2(0.0);
    vec3 centerRay = getRay(camCenter, iResolution, iMouse);

    float cosTheta = saturate(dot(dirWorld, centerRay));
    camera.pixelScale *= (cosTheta * cosTheta);
#endif
    
    // 3. Evaluate Stars (M4 + M5 + M6)
    // Pass altitude and time for extinction and twinkle
    vec3 starRadiance = evalStars(celestialSphere.rotatedRay, camera.pixelScale, altitude, time);

    // 4. Output HDR
    fragColor = toFrag(starRadiance);
}