// ============================================================================
// IMAGE
// M0: final composite + tonemap placeholder + debug override + NaN/Inf-ish guard.
// ============================================================================

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float time = getTimeSeconds(iTime);
    Camera camera = initCamera(fragCoord, iResolution, iMouse);
    CelestialSphere celestialSphere = initCelestialSphere(camera, time);
    
    // Disable celestial sphere rotation for debugging
#if DEBUG_DISABLE_CYCLE
    celestialSphere.rotatedRay = camera.rayDirection;
#endif

    MilkyWay milkyWay = initMilkyWay(celestialSphere);
    
    // Apply Debug Pan if enabled
#if DEBUG_ADD_CAMERA_PAN
    applyDebugCameraPan(camera, celestialSphere, time, iResolution, iMouse);
#endif
    
    // Get results from buffers
    vec3 hdrA = ENABLE_BUFFER_A ? texture(iChannel0, camera.uv).rgb : BLACK;
    vec3 hdrB = ENABLE_BUFFER_B ? texture(iChannel1, camera.uv).rgb : BLACK;
    vec3 hdrC = ENABLE_BUFFER_C ? texture(iChannel2, camera.uv).rgb : BLACK;

    vec3 hdrFromABC = hdrA + hdrB + hdrC;
    vec3 hdr = ENABLE_BUFFER_D ? texture(iChannel3, camera.uv).rgb : hdrFromABC;

    // Tonemap placeholder (per M0 plan): clamp HDR to 0..1
    vec3 ldr = tonemapPlaceholder(hdr);

    // Safety/Debug: if something goes NaN/huge, paint with error color so you *notice* immediately.
    if (isBadNumber(hdr) || isBadNumber(ldr))
    {
        fragColor = toFrag(ERROR_COLOR);
        return;
    }
    
    fragColor = vec4(ldr, 1.0);
    
#if SHOW_DEBUG
    if (DEBUG_MODE == DEBUG_VIEW_RAY)
    {
        // Map Vector (-1..1) to Color (0..1)
        // If this works, you will see a smooth gradient of colors.
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(camera.rayDirection * 0.5 + 0.5);
        return;
    }
    if (DEBUG_MODE == DEBUG_CAMERA_PAN)
    {
        applyDebugCameraPan(camera, celestialSphere, time, iResolution, iMouse);
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(camera.rayDirection * 0.5 + 0.5);
        
        // Verification: show how close the camera "forward" is to its "up"
        // white = almost parallel (danger zone), black = perpendicular (safe)
        vec3 forward = camera.orientation.forward;
        float pole = abs(dot(forward, normalize(camera.orientation.up)));

        //if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(vec3(pole));
        
        return;
    }
    if (DEBUG_MODE == DEBUG_PIXEL_SCALE)
    {
        float change = sin(time);
        camera = adjustCameraByFov(camera, change, iResolution, iMouse);
        // Multiply by huge number so we can see it (scale is tiny!)
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(vec3(camera.pixelScale * 300.0));
        return;
    }
    if (DEBUG_MODE == DEBUG_CELESTIAL_ROTATION)
    {
        // Allow camera panning
        //camera = applyDebugCameraPan(camera, time, iResolution);
        
        // Create "Latitude Rings" for all 3 axes (X, Y, Z)
        // We use asin() to get the angle, then cos() to make repeating rings.
        float scale = 15.0; // How many rings?
        
        float ringsX = step(0.98, cos(asin(celestialSphere.rotatedRay.x) * scale)); // Red axis rings
        float ringsY = step(0.98, cos(asin(celestialSphere.rotatedRay.y) * scale)); // Green axis rings
        float ringsZ = step(0.98, cos(asin(celestialSphere.rotatedRay.z) * scale)); // Blue axis rings
        
        // Combine them
        vec3 gridColor = BLACK;
        gridColor += RED * ringsX; // Dim Red
        gridColor += GREEN * ringsY; // Dim Green
        gridColor += BLUE * ringsZ; // Dim Blue
        
        // 4. Create a "Red Dot" Marker at a fixed celestial coordinate
        vec3 markerPos = normalize(vec3(-0.2, 0.2, -0.2));
        float d = dot(celestialSphere.rotatedRay, markerPos);
        float marker = smoothstep(0.9995, 0.9999, d);
        
        // Composite
        // Base background
        vec3 color = BLACK;
        
        // Add Grid
        color += gridColor;
        
        // Add Marker (Solid White/Yellow to stand out against the colored grid)
        color = mix(color, YELLOW, marker); 
        
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(color);
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_GRID)
    {
        // 1. Run the Mapping Logic
        CubeMapFace mapData = getCubeMapFace(celestialSphere.rotatedRay);
        
        // 2. Calculate Grid Coordinates (Same as evalStars)
        vec2 gridPos = mapData.uv * STAR_GRID_SCALE;
        vec2 cellID  = floor(gridPos);
        vec2 uvInCell = fract(gridPos);
        
        // 3. Generate a Random Color for this Cell
        // We use the same seed logic: FaceID + CellID
        vec3 cellColor = hash33(vec3(cellID, mapData.id));
        
        // 4. Draw Grid Lines (Borders)
        // 0.05 is the line thickness relative to the cell size
        vec2 borders = step(0.05, uvInCell) * step(uvInCell, vec2(0.95));
        float isInterior = borders.x * borders.y;
        
        // 5. Tint by Face ID (Optional, helps visualize the cube structure)
        // Face 0=Redish, 1=Greenish, etc. just to see the macro cube
        vec3 faceTint = 0.5 + 0.5 * cos(vec3(0.0, 2.0, 4.0) + float(mapData.id));
        
        // Combine: Black borders, Random Cell Color, Subtle Face Tint
        vec3 finalColor = mix(BLACK, cellColor * faceTint, isInterior);
        
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(finalColor);
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_ID)
    {
        // Placeholder until M4: stable per-pixel pattern to prove "mode changes"
        float v = fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453);
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(debugColorRamp(v));
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_LUMINANCE)
    {
        float lum = dot(hdr, vec3(0.2126, 0.7152, 0.0722));
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(debugColorRamp(saturate(lum)));
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_GALACTIC_UV)
    {
        MilkyWay milkyWay = initMilkyWay(celestialSphere);
        
        // Add contour lines for better visibility
        vec3 color = vec3(floor(milkyWay.uv * 10.0) / 10.0, 0.0);

        // Debug visualization:
        // R = longitude (wraps), G = latitude, B = 0
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(color);
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_MASK)
    {
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(milkyWay.mask);
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_COORDS)
    {
        // visualize where longitude = 0 and latitude = 0 are
        //float lat = 1.0 - saturate(abs(milkyWay.latitude) / (0.1 * PI));
        //float lon = 1.0 - saturate(abs(milkyWay.longitude) / (0.1 * PI));
        
        float lonRemap = remap(milkyWay.longitude, -PI, PI, -1.0, 1.0);
        float lonStep = 180.0 / DEBUG_MILKYWAY_COORDS_GRID.x;
        lonRemap = floor(lonRemap * lonStep) / lonStep;
        
        float latRemap = remap(milkyWay.latitude, -HALF_PI, HALF_PI, -1.0, 1.0);
        float latStepDegrees = 90.0 / DEBUG_MILKYWAY_COORDS_GRID.y;
        latRemap = floor(latRemap * latStepDegrees) / latStepDegrees;
        
        // longitude is red, latitude is green
        if (DEBUG_USE_TEST_COLOR) fragColor += toFrag(abs(vec3(lonRemap, latRemap, 0.0)));
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_DISK)
    {
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(milkyWay.core.diskMask);
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_BULGE)
    {
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(milkyWay.core.bulge.mask);
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_CORE)
    {
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(milkyWay.core.mask);
        return;
    }
#endif
    
    // Output final result
    fragColor = toFrag(ldr);
}
