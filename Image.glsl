// ============================================================================
// IMAGE
// M0: final composite + tonemap placeholder + debug override + NaN/Inf-ish guard.
// ============================================================================

/*------------------------------------------
                    Main
--------------------------------------------*/

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    Camera camera = initCamera(fragCoord, iResolution);
    
    // Get results from buffers
    vec3 hdrA = ENABLE_BUFFER_A ? texture(iChannel0, camera.uv).rgb : BLACK;
    vec3 hdrB = ENABLE_BUFFER_B ? texture(iChannel1, camera.uv).rgb : BLACK;
    vec3 hdrC = ENABLE_BUFFER_C ? texture(iChannel2, camera.uv).rgb : BLACK;
    
    vec3 hdrFromABC = hdrA + hdrB + hdrC;
    vec3 hdrFromD = ENABLE_BUFFER_D ? texture(iChannel3, camera.uv).rgb : hdrFromABC;

    // Get buffer results
    vec3 hdr = ENABLE_BUFFER_D ? hdrFromD : hdrFromABC;

    // Tonemap placeholder (per M0 plan): clamp HDR to 0..1
    vec3 ldr = tonemapPlaceholder(hdr);

    // Safety/Debug: if something goes NaN/huge, paint with error color so you *notice* immediately.
    if (isBadNumber(hdr) || isBadNumber(ldr))
    {
        fragColor = toFrag(ERROR_COLOR);
        return;
    }
    
#if SHOW_DEBUG
    float time = getTimeSeconds(iTime);
    
    CelestialSphere celestialSphere = initCelestialSphere(camera, time);
    
    fragColor = vec4(ldr, 1.0);
    
    if (DEBUG_MODE == DEBUG_VIEW_RAY)
    {
        // Map Vector (-1..1) to Color (0..1)
        // If this works, you will see a smooth gradient of colors.
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(camera.rayDirection * 0.5 + 0.5);
        return;
    }
    if (DEBUG_MODE == DEBUG_CAMERA_PAN)
    {
        camera = applyDebugCameraPan(camera, time, iResolution);
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(camera.rayDirection * 0.5 + 0.5);
        
        // Verification: show how close the camera "forward" is to its "up"
        // white = almost parallel (danger zone), black = perpendicular (safe)
        vec3 forward = camera.orientation.forward;
        float pole = abs(dot(forward, normalize(camera.orientation.up)));

        //if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(vec3(pole));
        
        return;
    }
    if (DEBUG_MODE == DEBUG_PIXEL_SCALE)
    {
        float change = sin(time);
        camera = adjustCameraByFov(camera, change, iResolution);
        // Multiply by huge number so we can see it (scale is tiny!)
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(vec3(camera.pixelScale * 300.0));
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
        
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(color);
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_GRID)
    {
        // 0. Allow camera panning
        //camera = applyDebugCameraPan(camera, time, iResolution);
        
        // 1. Get the ray that the Star System sees (Celestial Ray)
        vec3 dirCelestial = getCelestialRay(camera.rayDirection, time);
        
        // 2. Run the Mapping Logic
        CubeMapFace mapData = getCubeMapFace(dirCelestial);
        
        // 3. Calculate Grid Coordinates (Same as evalStars)
        vec2 gridPos = mapData.uv * STAR_GRID_SCALE;
        vec2 cellID  = floor(gridPos);
        vec2 uvInCell = fract(gridPos);
        
        // 4. Generate a Random Color for this Cell
        // We use the same seed logic: FaceID + CellID
        vec3 cellColor = hash33(vec3(cellID, mapData.id));
        
        // 5. Draw Grid Lines (Borders)
        // 0.05 is the line thickness relative to the cell size
        vec2 borders = step(0.05, uvInCell) * step(uvInCell, vec2(0.95));
        float isInterior = borders.x * borders.y;
        
        // 6. Tint by Face ID (Optional, helps visualize the cube structure)
        // Face 0=Redish, 1=Greenish, etc. just to see the macro cube
        vec3 faceTint = 0.5 + 0.5 * cos(vec3(0.0, 2.0, 4.0) + float(mapData.id));
        
        // Combine: Black borders, Random Cell Color, Subtle Face Tint
        vec3 finalColor = mix(BLACK, cellColor * faceTint, isInterior);
        
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(finalColor);
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_ID)
    {
        // Placeholder until M4: stable per-pixel pattern to prove "mode changes"
        float v = fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453);
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(debugColorRamp(v));
        return;
    }
    if (DEBUG_MODE == DEBUG_STAR_LUMINANCE)
    {
        // Placeholder until stars exist: show luminance of the current HDR composite
        float lum = dot(hdr, vec3(0.2126, 0.7152, 0.0722));
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(debugColorRamp(saturate(lum)));
        return;
    }
    if (DEBUG_MODE == DEBUG_GALACTIC_PLANE_DISTANCE)
    {
        // Placeholder until M7: show a constant so the switch is visibly working
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(debugColorRamp(0.25));
        return;
    }
    if (DEBUG_MODE == DEBUG_MILKYWAY_MASK)
    {
        // Placeholder until M7: show a constant so the switch is visibly working
        if (DEBUG_USE_TEST_COLOR) fragColor = toFrag(debugColorRamp(0.75));
        return;
    }
#endif
    
    // Output final result
    fragColor = toFrag(ldr);
}
