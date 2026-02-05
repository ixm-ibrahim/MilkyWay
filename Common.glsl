// ============================================================================
// COMMON
// M0: Scaffolding + Debug Harness
// M1: Camera Structs, Ray Generation, and Angular Scale Helpers
// ============================================================================

//==================================================================
//                        --- CONSTANTS ---
//==================================================================

const float PI      = 3.14159265358979323846;
const float TAU     = 6.28318530717958647692;

const float EPSILON_12 = 1e-12;
const float EPSILON_4  = 1e-4;

const float ALMOST_ONE_4 = 1.0 - EPSILON_4;

const vec3 ORIGIN       = vec3(0.0);
const vec3 AXIS_FORWARD = vec3(0.0, 0.0, -1.0); // Z is usually forward/back
const vec3 AXIS_UP      = vec3(0.0, 1.0, 0.0);  // Y is up
const vec3 AXIS_RIGHT   = vec3(1.0, 0.0, 0.0);  // X is right

const float MAX_ABS_PITCH = (0.5 * PI) - EPSILON_4;  // ~89.94 degrees

const vec3 RED        = vec3(1.0, 0.0, 0.0);
const vec3 YELLOW     = vec3(1.0, 1.0, 0.0);
const vec3 GREEN      = vec3(0.0, 1.0, 0.0);
const vec3 CYAN       = vec3(0.0, 1.0, 1.0);
const vec3 BLUE       = vec3(0.0, 0.0, 1.0);
const vec3 MAGENTA    = vec3(1.0, 0.0, 1.0);
const vec3 BLACK      = vec3(0.0, 0.0, 0.0);

const vec3 DIM_RED    = vec3(0.25, 0.05, 0.05);
const vec3 DIM_YELLOW = vec3(0.25, 0.25, 0.05);
const vec3 DIM_GREEN  = vec3(0.05, 0.25, 0.05);
const vec3 DIM_BLUE   = vec3(0.05, 0.05, 0.25);

//==================================================================
//                    --- MAIN CONTROL PANEL ---
//==================================================================

/*------------------------------------------
                  0. DEBUG
--------------------------------------------*/

#define SHOW_DEBUG                    1

#define ENABLE_BUFFER_A               true  // background
#define ENABLE_BUFFER_B               true  // stars
#define ENABLE_BUFFER_C               true  // milky way
#define ENABLE_BUFFER_D               true  // post-processing

#define DEBUG_OFF                     0
#define DEBUG_VIEW_RAY                1
#define DEBUG_CAMERA_PAN              2
#define DEBUG_PIXEL_SCALE             3
#define DEBUG_CELESTIAL_ROTATION      4
#define DEBUG_STAR_GRID               5
#define DEBUG_STAR_ID                 6
#define DEBUG_STAR_LUMINANCE          7
#define DEBUG_GALACTIC_PLANE_DISTANCE 8
#define DEBUG_MILKYWAY_MASK           9

#define DEBUG_MODE                    DEBUG_STAR_GRID
#define DEBUG_USE_TEST_COLOR          false

#define DEBUG_ENABLE_FREEZE_TIME      false
#define DEBUG_FROZEN_TIME_SECONDS     0.1
#define DEBUG_TIME_SPEED_SCALE        1.0

#define ERROR_COLOR                   MAGENTA


/*------------------------------------------
                 1. CAMERA
--------------------------------------------*/

#define CAMERA_START_POSITION    ORIGIN
#define CAMERA_START_TARGET      AXIS_FORWARD
#define CAMERA_START_UP          AXIS_UP

#define CAMERA_START_FOV_DEGREES 60.0
#define CAMERA_MIN_FOV_DEGREES   10.0
#define CAMERA_MAX_FOV_DEGREES   120.0

/*------------------------------------------
            2. CELESTIAL SPHERE
--------------------------------------------*/

#define SKY_ROTATION_AXIS  AXIS_UP
#define SKY_ROTATION_SPEED 0.1 // radians per second

/*------------------------------------------
                   3. SKY
--------------------------------------------*/

#define AIRGLOW_CENTER     0.15 // ~8.5 degrees above horizon
#define AIRGLOW_BAND_WIDTH 15.0 // Controls how narrow the band is

/*------------------------------------------
                  4. STARS
--------------------------------------------*/

#define STAR_GRID_USE_ADJUSTMENT 1

#define STAR_GRID_SCALE          15.0 // Higher = smaller cells, more potential stars
#define STAR_PROBABILITY         0.15 // Chance a cell contains a star

#define STAR_ADJACENT_NEIGHBORS  1

#define STAR_MAGNITUDE_BASE      1.0 
#define STAR_MAGNITUDE_MIN       -1.0 // Siriusish
#define STAR_MAGNITUDE_MAX       6.0  // Dim limit

#define STAR_PSF_SIGMA_PIXELS    0.65
#define STAR_PSF_CUTOFF_PIXELS   3:contentReference[oaicite:5]{index=5}_MIN        2500.0
#define STAR_COLOR_KELVIN_MAX    12000.0



//==================================================================
//                        --- STRUCTURES ---
//==================================================================

struct Orientation
{
    vec3 forward; // Look-at direction
    vec3 up;      // Up vector
};

struct Camera
{
    vec3        position;    // World position
    Orientation orientation; // World orientation
    float       fovY;        // Vertical Field of View in radians
    
    vec3 rayDirection;  // the direction each pixel looks at
    float pixelScale;   // how many radians each pixel covers
    
    vec2 uv;            // screen coordinates
    vec2 normalizedUV;  // normalized and centered screen coordinates
};

struct CelestialSphere
{
    vec3 rotationAxis;
    float rotationValue;
    
    vec3 rotatedRay;
};

struct CubeMapFace
{
    int id;
    vec2 uv;
};

//==================================================================
//                    --- UTILITY FUNCTIONS ---
//==================================================================

/*--------------------------------------
               Validation
----------------------------------------*/

bool isNan(float x) { return (x != x); }
bool isNan(vec2 v) { return isNan(v.x) || isNan(v.y); }
bool isNan(vec3 v) { return isNan(v.x) || isNan(v.y) || isNan(v.z); }

bool isBadNumber(float v)
{
    // NaN check + very-large-value check (cheap “inf-ish” guard)
    if (isNan(v)) return true;
    if (abs(v) > float(1e20)) return true;
    return false;
}
bool isBadNumber(vec2 v)
{
    // NaN check + very-large-value check (cheap “inf-ish” guard)
    if (isNan(v)) return true;
    if (any(greaterThan(abs(v), vec2(1e20)))) return true;
    return false;
}
bool isBadNumber(vec3 v)
{
    // NaN check + very-large-value check (cheap “inf-ish” guard)
    if (isNan(v)) return true;
    if (any(greaterThan(abs(v), vec3(1e20)))) return true;
    return false;
}

/*--------------------------------------
              Math Helpers
----------------------------------------*/

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2  v) { return clamp(v, vec2(0.0), vec2(1.0)); }
vec3  saturate(vec3  v) { return clamp(v, vec3(0.0), vec3(1.0)); }

float one_minus(float x) { return 1.0 - x; }
vec2 one_minus(vec2 v) { return 1.0 - v; }
vec3 one_minus(vec3 v) { return 1.0 - v; }

float remap(float value, float old_min, float old_max, float new_min, float new_max)
{
    return new_min + (value - old_min) * (new_max - new_min) / (old_max - old_min);
}
vec2 remap(vec2 value, float old_min, float old_max, float new_min, float new_max)
{
    return new_min + (value - old_min) * (new_max - new_min) / (old_max - old_min);
}
vec2 remap(vec2 value, vec2 old_min, vec2 old_max, vec2 new_min, vec2 new_max)
{
    return new_min + (value - old_min) * (new_max - new_min) / (old_max - old_min);
}

vec3 safeNormalize(vec3 v, vec3 fallback)
{
    float len2 = dot(v, v);
    if (len2 < EPSILON_12) return fallback;
    return v * inversesqrt(len2);
}

/*--------------------------------------
        Geometric Transformation
----------------------------------------*/

float clampPitch(float pitch) { return clamp(pitch, -MAX_ABS_PITCH, MAX_ABS_PITCH); }

vec3 rotateAroundAxis(vec3 v, vec3 axis, float angle)
{
    axis = normalize(axis);
    
    float s = sin(angle);
    float c = cos(angle);
    
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

/*--------------------------------------
            Color & Lighting
----------------------------------------*/

vec4 toFrag(vec3 color) { return vec4(color, 1.0); }

float magnitudeToRadiance(float mag)
{
    // Convert astronomical magnitude to linear light energy.
    // Mag 0 is brighter than Mag 5. Scale is logarithmic.
    // 5 steps in magnitude = 100x brightness difference.
    
    // I = I_0 * 10^(-0.4 * mag)
    return pow(10.0, -0.4 * mag);
}

/*--------------------------------------
             Randomization
----------------------------------------*/

float hash12(vec2 p2)
{
    vec3 p3  = fract(vec3(p2.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p2)
{
    vec3 p3 = fract(vec3(p2.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

vec3 hash33(vec3 p3)
{
    p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy + p3.yxx)*p3.zyx);
}

/*--------------------------------------
            Common Utilities
----------------------------------------*/

float getTimeSeconds(float iTime)
{
    return DEBUG_TIME_SPEED_SCALE * (DEBUG_ENABLE_FREEZE_TIME ? DEBUG_FROZEN_TIME_SECONDS : iTime);
}

//==================================================================
//                   --- STRUCTURE FUNCTIONS ---
//==================================================================

/*--------------------------------------
                 Camera
----------------------------------------*/

vec2 squareAspectRatio(vec2 uv, vec3 iResolution)
{
    if (iResolution.x > iResolution.y)
        uv.x *= iResolution.x / iResolution.y;
    else if (iResolution.y > iResolution.x)
        uv.y *= iResolution.y / iResolution.x;
        
    return uv;
}

vec2 getUV(vec2 fragCoord, vec3 iResolution) { return fragCoord/iResolution.xy; }
vec2 getNormalizedUV(vec2 uv, vec3 iResolution)
{
    uv = remap(uv, 0.0, 1.0, -1.0, 1.0);
    return squareAspectRatio(uv, iResolution);
}

mat3 getCameraMatrix(Camera camera)
{
    vec3 forward = normalize(camera.orientation.forward);
    vec3 right   = normalize(cross(forward, camera.orientation.up));
    vec3 up = cross(right, forward);
    
    return mat3(right, up, forward);
}

vec3 getRay(Camera camera)
{
    // 1. Adjust for Field of View (zoom)
    float tanHalfFov = tan(camera.fovY * 0.5);
    vec2 screenPlane = camera.normalizedUV * tanHalfFov;

    // 2. Rotate into world space (right, up, forward basis).
    mat3 basis = getCameraMatrix(camera);

    // 3. Local ray points "forward" (z=1) with offsets in x/y.
    vec3 dirLocal = normalize(vec3(screenPlane, 1.0));
    vec3 dirWorld = basis * dirLocal;

    return normalize(dirWorld);
}

float getPixelAngularScale(Camera cam, float resY) // How many radians does one pixel cover?
{
    // Approximation: Total Vertical Angle / Vertical Pixels
    return cam.fovY / resY;
}

Orientation initOrientation(vec3 forward, vec3 up)
{
    Orientation orientation;
    
    orientation.forward = forward;
    orientation.up = up;
    
    return orientation;
}

float setCameraFov(float fovRadians)
{
    float minFov = radians(CAMERA_MIN_FOV_DEGREES);
    float maxFov = radians(CAMERA_MAX_FOV_DEGREES);
    
    return clamp(fovRadians, minFov, maxFov);
}

Camera initCamera(vec2 fragCoord, vec3 iResolution)
{
    Camera camera;
    
    // 1. Setup Camera (Standard look-at)
    camera.position     = CAMERA_START_POSITION;
    camera.orientation  = initOrientation(CAMERA_START_TARGET, CAMERA_START_UP);
    camera.fovY         = setCameraFov(radians(CAMERA_START_FOV_DEGREES));
    
    // 2. Get screen coordinates
    camera.uv           = getUV(fragCoord, iResolution);
    camera.normalizedUV = getNormalizedUV(camera.uv, iResolution);
    
    // 3. Compute Ray and Scale
    camera.rayDirection = getRay(camera);
    camera.pixelScale   = getPixelAngularScale(camera, iResolution.y);
    
    return camera;
}

Camera adjustCameraByFov(Camera camera, float offset, vec3 iResolution)
{
    camera.fovY = setCameraFov(camera.fovY + offset);
    camera.rayDirection = getRay(camera);
    camera.pixelScale = getPixelAngularScale(camera, iResolution.y);
    
    return camera;
}

/*--------------------------------------
                  Sky
----------------------------------------*/

CelestialSphere initCelestialSphere(Camera camera, float time)
{
    CelestialSphere celestialSphere;
    
    celestialSphere.rotationAxis = vec3(0.0);
    celestialSphere.rotationValue = 0.0;
    
    // The sky rotates around the up axis.
    // We rotate the vector by -time * speed.
    // (Negative because sky moves opposite to earth rotation)
    celestialSphere.rotatedRay = rotateAroundAxis(camera.rayDirection, SKY_ROTATION_AXIS, -time * SKY_ROTATION_SPEED);
    
    return celestialSphere;
}

vec3 getCelestialRay(vec3 dirWorld, float time)
{
    // The sky rotates around the up axis.
    // We rotate the vector by -time * speed.
    // (Negative because sky moves opposite to earth rotation)
    return rotateAroundAxis(dirWorld, SKY_ROTATION_AXIS, -time * SKY_ROTATION_SPEED);
}

/*--------------------------------------
              CubeMapFace
----------------------------------------*/

CubeMapFace initCubeMapFace(int faceId, vec2 faceUV)
{
    CubeMapFace cubeMapFace;
    
    cubeMapFace.id = faceId;
    cubeMapFace.uv = faceUV;
    
    return cubeMapFace;
}

CubeMapFace getCubeMapFace(vec3 dir)
{
    // Maps a direction to a Cube Face (0-5) and a UV (0-1) on that face.
    // This allows us to tile the sky perfectly without pole distortion.
    vec3 absDir = abs(dir);
    int faceIndex;
    vec2 uv;
    float ma; // Major Axis

    if (absDir.x >= absDir.y && absDir.x >= absDir.z)
    {
        ma = absDir.x;
        faceIndex = (dir.x > 0.0) ? 0 : 1;
        uv = (dir.x > 0.0) ? vec2(-dir.z, -dir.y) : vec2(dir.z, -dir.y);
    }
    else if (absDir.y >= absDir.z)
    {
        ma = absDir.y;
        faceIndex = (dir.y > 0.0) ? 2 : 3;
        uv = (dir.y > 0.0) ? vec2(dir.x, dir.z) : vec2(dir.x, -dir.z);
    }
    else
    {
        ma = absDir.z;
        faceIndex = (dir.z > 0.0) ? 4 : 5;
        uv = (dir.z > 0.0) ? vec2(dir.x, -dir.y) : vec2(-dir.x, -dir.y);
    }
    
    CubeMapFace cubeMapFace;
    
    cubeMapFace.id = faceIndex;
#if STAR_GRID_USE_ADJUSTMENT
    // 1. Normalize UV to range [-1, 1]
    vec2 normUV = uv / ma;
    // 2. Apply atan to correct for spherical distortion (result is approx -PI/4 to PI/4)
    // 3. Normalize angle to [0, 1] by dividing by PI/2 (total range)
    cubeMapFace.uv = (atan(normUV) / (PI * 0.5)) + 0.5;
#else
    // Convert range [-ma, ma] to [0, 1]
    cubeMapFace.uv = (uv / ma + 1.0) * 0.5;
#endif
    
    return cubeMapFace;
}

vec3 getDirFromCubemap(CubeMapFace cubeMapFace)
{
    // Inverse: Recover the 3D direction from a Face ID and UV.
    // Needed to verify exactly where the star is in the neighbor cell.
    
    // Map uv [0,1] back to [-1, 1]
    vec2 st = cubeMapFace.uv * 2.0 - 1.0;
    
#if STAR_GRID_USE_ADJUSTMENT
    // 1. Map [0,1] back to Angle [-PI/4, PI/4]
    // 2. Map Angle back to Linear Plane Coordinate using tan()
    st = tan(st * (PI * 0.25));
#endif
    
    vec3 dir;
    
    if (cubeMapFace.id == 0)      dir = vec3(1.0, -st.y, -st.x);
    else if (cubeMapFace.id == 1) dir = vec3(-1.0, -st.y, st.x);
    else if (cubeMapFace.id == 2) dir = vec3(st.x, 1.0, st.y);
    else if (cubeMapFace.id == 3) dir = vec3(st.x, -1.0, -st.y);
    else if (cubeMapFace.id == 4) dir = vec3(st.x, -st.y, 1.0);
    else                          dir = vec3(-st.x, -st.y, -1.0);
    
    return normalize(dir);
}

//==================================================================
//                   --- DEBUGGING FUNCTIONS ---
//==================================================================

// Debug ramp: maps 0..1 to a readable color gradient
vec3 debugColorRamp(float x)
{
    x = saturate(x);

    // A simple, readable ramp (blue -> cyan -> green -> yellow -> red)
    vec3 c0 = BLUE;
    vec3 c1 = CYAN;
    vec3 c2 = GREEN;
    vec3 c3 = YELLOW;
    vec3 c4 = RED;

    float t = x * 4.0;
    if (t < 1.0) return mix(c0, c1, t);
    if (t < 2.0) return mix(c1, c2, t - 1.0);
    if (t < 3.0) return mix(c2, c3, t - 2.0);
    return mix(c3, c4, t - 3.0);
}

// Placeholder tonemap for M0 (per your plan): clamp HDR to 0..1
vec3 tonemapPlaceholder(vec3 hdr)
{
    return saturate(hdr);
}

Camera applyDebugCameraPan(Camera camera, float timeSeconds, vec3 iResolution)
{
    // This is a verification helper for M1:
    // when enabled (DEBUG_CAMERA_PAN) the camera slowly yaws/pitches over time so
    // DEBUG_VIEW_RAY should "rotate smoothly" (per the plan).
    //
    // IMPORTANT: This is a *debug* motion. Real sky rotation will be in M2.
    float yaw   = 3.5 * sin(timeSeconds * 0.25);
    float pitch = 2.0 * sin(timeSeconds * 0.19);
    
    // To prevent weird behavior at the poles
    pitch = clampPitch(pitch);
    
    vec3 forwardDir = normalize(camera.orientation.forward);
    forwardDir = rotateAroundAxis(forwardDir, AXIS_UP, yaw);

    vec3 rightDir = normalize(cross(forwardDir, camera.orientation.up));
    forwardDir = rotateAroundAxis(forwardDir, rightDir, pitch);

    camera.orientation.forward = normalize(forwardDir);

    // Keep camera.forward consistent with our "direction" interpretation.
    camera.orientation.forward = camera.position + camera.orientation.forward;

    // Recompute ray and pxScale for the new orientation.
    camera.rayDirection = getRay(camera);
    camera.pixelScale   = getPixelAngularScale(camera, iResolution.y);

    return camera;
}
