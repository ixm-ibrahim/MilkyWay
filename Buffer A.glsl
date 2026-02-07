// ============================================================================
// BUFFER A
// M0: scaffolding pass. Produces HDR radiance for sky background.
// M3: Base Night Sky Background + Airglow
// ============================================================================

/*------------------------------------------
                 Constants
--------------------------------------------*/


/*------------------------------------------
               Control Panel
--------------------------------------------*/

#define TEST_BUFFER_A_WIRING 0
#define TEST_SKY_COLOR       0  // 10+

/*------------------------------------------
                 Structures
--------------------------------------------*/

struct AirGlow
{
    float center;
    float bandWidth;
    
    float mask;
    vec3 color;
};

struct Atmosphere
{
    float altitude;
    
    vec3 skyColor;
    
    AirGlow airGlow;
};

/*------------------------------------------
                 Functions
--------------------------------------------*/

AirGlow initAirGlow(float altitude)
{
    AirGlow airglow;
    
    // A subtle bump in brightness slightly above the horizon.
    // We want a peak at say, 10-15 degrees altitude.
    airglow.center    = SKY_AIRGLOW_CENTER;
    airglow.bandWidth = SKY_AIRGLOW_BAND_WIDTH;
    
    // Gaussian-ish shape: exp( - (x - center)^2 * width )
    float airglowDist = altitude - airglow.center;
    airglow.mask      = exp(-(airglowDist * airglowDist) * airglow.bandWidth);
    
    airglow.color     = SKY_AIRGLOW_COLOR * airglow.mask * SKY_AIRGLOW_INTENSITY;
    
    return airglow;
}

Atmosphere initAtmosphere(Camera camera)
{
    Atmosphere atmosphere;
    
    // Calculate Altitude (0.0 at horizon, 1.0 at zenith)
    // We clamp to 0.0 to avoid weird colors below the ground for now.
    atmosphere.altitude = max(0.0, dot(camera.rayDirection, AXIS_UP));
    
    // 2. Base Gradient (Zenith to Horizon)
    
    // We use a power function to make the horizon haze drop off quickly,
    // keeping the upper sky very dark.
    // Interpolate: 0% altitude = Horizon Color, 100% altitude = Zenith Color
    // We use sqrt(altitude) or similar to shape the gradient.
    
    // Note: This is "Atmosphere", so it stays fixed to the world (ground),
    // it does NOT rotate with the stars (Celestial Sphere).
    atmosphere.skyColor = mix(SKY_HORIZON_COLOR, SKY_ZENITH_COLOR, pow(atmosphere.altitude, 0.4)) * SKY_COLOR_INTENSITY;
    
    // Get airglow
    atmosphere.airGlow = initAirGlow(atmosphere.altitude);
    
    return atmosphere;
}

vec3 getFinalSkyColor(Atmosphere atmosphere)
{
    return atmosphere.skyColor + atmosphere.airGlow.color;
}

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
#if TEST_BUFFER_A_WIRING
    fragColor = toFrag(DIM_RED);
    return;
#endif

    // 1. Initialize Camera to get the correct ray for this pixel
    Camera camera = initCamera(fragCoord, iResolution, iMouse);
    
    // 2. Optional: Apply Debug Pan (M1/M2 check)
    // If DEBUG_CAMERA_PAN is on in Common, we want Buffer A to respect it
    // so the background moves with the camera.
#if (DEBUG_MODE == DEBUG_CAMERA_PAN)
    float time = getTimeSeconds(iTime);
    CelestialSphere celestialSphere = initCelestialSphere(camera, time);
    applyDebugCameraPan(camera, celestialSphere, getTimeSeconds(iTime), iResolution);
#endif

    // 3. Get the ray direction in World Space
    Atmosphere atmosphere = initAtmosphere(camera);

    // 4. Compute Sky Background (M3)
    vec3 skyRadiance = getFinalSkyColor(atmosphere);
    
#if TEST_SKY_COLOR
    skyRadiance *= float(TEST_SKY_COLOR);
#endif

    // 5. Output HDR
    fragColor = toFrag(skyRadiance);
}