#include <metal_stdlib>
using namespace metal;

// ═══════════════════════════════════════════════════════════════════════
// STRUCTS
// ═══════════════════════════════════════════════════════════════════════

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Params {
    float2 resolution;     // View resolution (not including padding)
    float cornerRadius;    // Corner radius (0 = sharp rectangle)
    float paddingFactor;   // Padding percentage (0.25 = 25%)
    float distortionStrength; // Distortion strength (0 = none, 0.2 = moderate)
    float blurRadius;      // Blur radius in pixels
    float2 shadowDirection; // Direction shadow is cast from (e.g., upper-right = (0.5, -0.7))
    float minifyMultiplier;   // Multiplier for center minification (default 5.0)
    float magnifyMultiplier;  // Multiplier for edge magnification (default 1.0)
    float distortionThreshold; // Threshold where minification transitions to magnification (0.0-1.0, default 0.5)
};

// ═══════════════════════════════════════════════════════════════════════
// DISTORTION FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════

// SDF-based distortion: follows the rounded rectangle shape
// Returns distortion amount based on distance from edge (not center)
// Center → 0 (no distortion)
// 50% distance → minimal distortion
// Edge → VERY HIGH distortion (steep exponential rise)
float sdfBasedDistortion(float sdf, float2 halfSize, float threshold) {
    // Normalize SDF to 0-1 range
    // Maximum SDF (at center) is approximately the smaller dimension / 2
    float maxSDF = min(halfSize.x, halfSize.y);
    float normalizedSDF = clamp(-sdf / maxSDF, 0.0, 1.0);
    
    // INVERT: 0 at center, 1 at edges
    float r = 1.0 - normalizedSDF;
    
    // STRONG EDGE DISTORTION CURVE:
    // - Nearly zero distortion from center to threshold%
    // - Steep exponential rise from threshold% to edge
    float maxDistortion = 1.0;  // Maximum distortion at edge
    
    if (r < threshold) {
        // Very calm interior - almost no distortion
        float t = r / threshold;  // 0 to 1
        return 0.01 * t * t;      // Nearly flat
    } else {
        // STEEP exponential rise at edges
        float t = (r - threshold) / (1.0 - threshold);  // 0 to 1 in edge zone
        
        // Power curve for steep rise: starts slow, accelerates rapidly
        float steep = pow(t, 2.5);
        
        // Additional exponential boost near the very edge
        float edgeBoost = exp(t * 2.0) - 1.0;
        edgeBoost = edgeBoost / (exp(2.0) - 1.0);  // Normalize to 0-1
        
        // Combine for very strong edge effect
        return mix(0.01, maxDistortion, steep * 0.6 + edgeBoost * 0.4);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// GAUSSIAN BLUR
// ═══════════════════════════════════════════════════════════════════════

// Simple 5x5 Gaussian blur
float3 applyGaussianBlur(texture2d<float> tex, sampler samp, float2 uv, float blurRadius, float2 resolution) {
    float3 color = float3(0.0);
    float totalWeight = 0.0;
    
    // 5x5 kernel
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            float2 offset = float2(float(x), float(y)) * blurRadius / resolution;
            float weight = exp(-0.5 * float(x*x + y*y) / 2.0);
            
            color += tex.sample(samp, uv + offset).rgb * weight;
            totalWeight += weight;
        }
    }
    
    return color / totalWeight;
}

// ═══════════════════════════════════════════════════════════════════════
// FRESNEL EFFECT
// ═══════════════════════════════════════════════════════════════════════

// Calculate Fresnel highlight for glass edges
// sdf: signed distance (negative inside)
// halfSize: half dimensions of the shape
// pixelPos: current pixel position
// center: center of the shape
// fresnelDirection: direction where fresnel is strongest (e.g., upper-right = (0.7, -0.7))
// Returns: color with Fresnel highlight applied
float3 applyFresnelEffect(float3 baseColor, float sdf, float2 halfSize, float2 pixelPos, float2 center, float2 fresnelDirection) {
    // Normalize SDF: 0 at edge, 1 at center
    float maxDist = min(halfSize.x, halfSize.y);
    float edgeDistance = clamp(-sdf / maxDist, 0.0, 1.0);
    
    // Fresnel: strong at edges (edgeDistance ≈ 0), weak at center (edgeDistance ≈ 1)
    float fresnel = 1.0 - edgeDistance;
    
    // Apply power curve to concentrate effect at edges
    fresnel = pow(fresnel, 10.0);
    
    // Add directional bias based on provided direction
    float2 toEdge = normalize(pixelPos - center);
    float2 fresnelDir = normalize(fresnelDirection);
    float directional = max(0.0, dot(toEdge, fresnelDir));
    
    // Combine: 30% uniform + 70% directional
    fresnel = fresnel * (0.3 + 0.7 * directional);
    
    // Fresnel highlight color (white with slight blue tint for glass look)
    float3 fresnelColor = float3(0.9, 0.95, 1.0);
    
    // Blend fresnel highlight onto the base color
    float fresnelStrength = 0.15;  // Subtle edge highlight
    return mix(baseColor, fresnelColor, fresnel * fresnelStrength);
}

// ═══════════════════════════════════════════════════════════════════════
// CHROMATIC ABERRATION
// ═══════════════════════════════════════════════════════════════════════

// Apply chromatic aberration (RGB color fringing at edges)
// Samples R, G, B channels at slightly different UV offsets
// Red shifts outward, Blue shifts inward, Green stays centered
float3 applyChromaticAberration(
    texture2d<float> tex,
    sampler samp,
    float2 uv,
    float2 center,        // Center of the shape in UV space
    float sdf,            // SDF value (for edge detection)
    float2 halfSize,      // Half dimensions
    float strength        // Aberration strength (0.0 - 0.02 typical)
) {
    // Calculate direction from center
    float2 direction = uv - center;
    float dist = length(direction);
    
    if (dist < 0.001) {
        // At center, no aberration
        return tex.sample(samp, uv).rgb;
    }
    
    direction = normalize(direction);
    
    // Edge factor: more aberration at edges (using SDF)
    float maxDist = min(halfSize.x, halfSize.y);
    float edgeFactor = clamp(1.0 - (-sdf / maxDist), 0.0, 1.0);
    edgeFactor = pow(edgeFactor, 2.0);  // Concentrate at edges
    
    // Calculate RGB offsets
    float aberrationAmount = strength * edgeFactor;
    float2 redOffset = direction * aberrationAmount;
    float2 blueOffset = -direction * aberrationAmount;
    
    // Sample each channel at different positions
    float r = tex.sample(samp, uv + redOffset).r;
    float g = tex.sample(samp, uv).g;  // Green stays centered
    float b = tex.sample(samp, uv + blueOffset).b;
    
    return float3(r, g, b);
}

// ═══════════════════════════════════════════════════════════════════════
// SPECULAR RIM / CAUSTIC LINE
// ═══════════════════════════════════════════════════════════════════════

// Apply specular rim highlight (bright caustic line at glass edge)
// Creates a sharp, bright line right at the edge simulating light refraction
// sdf: signed distance (negative inside)
// lightDir: simulated light direction (normalized)
// rimWidth: width of the caustic line in pixels
// intensity: brightness of the rim (0.0 - 1.0)
float3 applySpecularRim(
    float3 baseColor,
    float sdf,
    float2 pixelPos,
    float2 center,
    float rimWidth,
    float intensity
) {
    // Create a sharp band near the edge (where sdf ≈ 0)
    // Using smoothstep to create a soft-edged bright line
    float distFromEdge = abs(sdf);
    
    // Rim factor: 1.0 at edge, falls off quickly
    float rimFactor = 1.0 - smoothstep(0.0, rimWidth, distFromEdge);
    
    // Add directional variation (simulate light from top-left)
    float2 toCenter = normalize(center - pixelPos);
    float2 lightDir = normalize(float2(-0.5, -0.7));  // Light from top-left
    float directional = max(0.0, dot(toCenter, lightDir));
    
    // Combine: rim is brightest where light hits the edge
    float rim = rimFactor * (0.3 + 0.7 * directional);
    
    // Apply power curve for sharper falloff
    rim = pow(rim, 1.5);
    
    // Specular highlight color (bright white with slight warmth)
    float3 rimColor = float3(1.0, 0.98, 0.95);
    
    // Blend rim onto base color
    return mix(baseColor, rimColor, rim * intensity);
}

// ═══════════════════════════════════════════════════════════════════════
// INNER SHADOW
// ═══════════════════════════════════════════════════════════════════════

// Apply inner shadow effect (subtle darkening near edges)
// Creates depth and thickness illusion like real glass
// sdf: signed distance (negative inside)
// shadowWidth: how far the shadow extends from edge (pixels)
// shadowIntensity: darkness of shadow (0.0 - 1.0)
// shadowDirection: normalized direction shadow is cast from (e.g., top-right = (0.5, -0.5))
float3 applyInnerShadow(
    float3 baseColor,
    float sdf,
    float2 pixelPos,
    float2 center,
    float shadowWidth,
    float shadowIntensity,
    float2 shadowDirection  // Direction shadow is cast from (e.g., upper-right = (0.5, -0.7))
) {
    // Only apply inside the shape
    if (sdf >= 0.0) return baseColor;
    
    // Distance from edge (sdf is negative inside, so -sdf = distance from edge)
    float distFromEdge = -sdf;
    
    // Shadow factor: 1.0 at edge, 0.0 at shadowWidth distance
    float shadowFactor = 1.0 - smoothstep(0.0, shadowWidth, distFromEdge);
    
    // Add directional bias based on provided direction
    float2 toEdge = normalize(pixelPos - center);
    float2 shadowDir = normalize(shadowDirection);
    float directional = max(0.0, dot(toEdge, shadowDir));
    
    // Combine: shadow is darker where light doesn't reach
    float shadow = shadowFactor * (0.4 + 0.6 * directional);
    
    // Apply smooth curve
    shadow = pow(shadow, 1.2);
    
    // Shadow color (dark with slight blue tint for depth)
    float3 shadowColor = float3(0.0, 0.02, 0.05);
    
    // Darken the base color
    return mix(baseColor, shadowColor, shadow * shadowIntensity);
}

// ═══════════════════════════════════════════════════════════════════════
// SOFT EDGE
// ═══════════════════════════════════════════════════════════════════════

// Calculate soft edge alpha for anti-aliased glass boundary
// Creates smooth transition at edges instead of hard cutoff
// sdf: signed distance (negative inside, positive outside)
// edgeWidth: width of the soft transition zone in pixels
// pixelPos: current pixel position
// center: center of the shape
// lightDirection: direction light comes from (opposite of shadow)
// Returns: alpha value (0.0 = fully transparent, 1.0 = fully opaque)
float calculateSoftEdgeAlpha(float sdf, float edgeWidth, float2 pixelPos, float2 center, float2 lightDirection) {
    // Add directional bias - softer edge on light side, harder on shadow side
    float2 toEdge = normalize(pixelPos - center);
    float2 lightDir = normalize(lightDirection);
    float directional = dot(toEdge, lightDir);
    
    // Modulate edge width: wider on light side (positive dot), narrower on shadow side
    float modulatedWidth = edgeWidth * (0.5 + 0.5 * directional);
    
    // smoothstep creates gradual transition:
    // - sdf < -modulatedWidth → alpha = 1.0 (fully inside)
    // - sdf > 0 → alpha = 0.0 (fully outside)
    // - -modulatedWidth < sdf < 0 → smooth gradient
    return 1.0 - smoothstep(-modulatedWidth, 0.0, sdf);
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE TINT
// ═══════════════════════════════════════════════════════════════════════

// Apply subtle color tint at glass edges
// Simulates how thick glass refracts light differently at edges
// sdf: signed distance (negative inside)
// halfSize: half dimensions for normalization
// tintColor: the color to apply at edges
// tintWidth: how far the tint extends from edge (pixels)
// intensity: strength of the tint (0.0 - 1.0)
float3 applyEdgeTint(
    float3 baseColor,
    float sdf,
    float2 halfSize,
    float3 tintColor,
    float tintWidth,
    float intensity
) {
    // Only apply inside the shape
    if (sdf >= 0.0) return baseColor;
    
    // Distance from edge (sdf is negative inside)
    float distFromEdge = -sdf;
    
    // Tint factor: 1.0 at edge, 0.0 at tintWidth distance
    float tintFactor = 1.0 - smoothstep(0.0, tintWidth, distFromEdge);
    
    // Apply smooth curve for more natural falloff
    tintFactor = pow(tintFactor, 1.5);
    
    // Blend tint color onto base
    return mix(baseColor, baseColor * tintColor, tintFactor * intensity);
}

// ═══════════════════════════════════════════════════════════════════════
// INTERNAL REFLECTION
// ═══════════════════════════════════════════════════════════════════════

// Apply internal reflection effect (light bouncing inside glass)
// Simulates Total Internal Reflection at shallow angles
// tex: background texture
// samp: texture sampler
// uv: current sampling UV
// center: center of texture in UV space
// sdf: signed distance (negative inside)
// halfSize: half dimensions for edge calculation
// strength: reflection intensity (0.0 - 1.0)
float3 applyInternalReflection(
    texture2d<float> tex,
    sampler samp,
    float2 uv,
    float2 center,
    float sdf,
    float2 halfSize,
    float strength
) {
    // Normal sample (refracted view - what we see through glass)
    float3 refracted = tex.sample(samp, uv).rgb;
    
    // Calculate reflected UV - mirror across center
    float2 reflectedUV = 2.0 * center - uv;
    
    // Clamp to valid range to avoid sampling outside texture
    reflectedUV = clamp(reflectedUV, float2(0.01), float2(0.99));
    
    // Sample at reflected position (what bounces back)
    float3 reflected = tex.sample(samp, reflectedUV).rgb;
    
    // Edge factor: more reflection at edges (Total Internal Reflection)
    // 0 at center, 1 at edge
    float maxDist = min(halfSize.x, halfSize.y);
    float edgeFactor = clamp(-sdf / maxDist, 0.0, 1.0);
    
    // Reflection concentrated at edges (like real glass)
    float reflectionAmount = pow(1.0 - edgeFactor, 4.0);
    
    // Add slight blur to reflection for realism
    reflected = reflected * 0.9;  // Slightly dim the reflection
    
    // Blend: mostly refracted (see-through), some reflected at edges
    return mix(refracted, reflected, reflectionAmount * strength);
}

// ═══════════════════════════════════════════════════════════════════════
// SIGNED DISTANCE FIELD (SDF)
// ═══════════════════════════════════════════════════════════════════════

// Calculate distance to rounded rectangle edge
// Returns: negative = inside, positive = outside, zero = on edge
float roundedRectSDF(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + float2(radius);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - radius;
}

// ═══════════════════════════════════════════════════════════════════════
// VERTEX SHADER
// ═══════════════════════════════════════════════════════════════════════

vertex VertexOut simpleVertex(uint vertexID [[vertex_id]], 
                               constant float2 *vertices [[buffer(0)]]) {
    VertexOut out;
    float2 pos = vertices[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    
    // Convert from NDC (-1 to 1) to UV (0 to 1)
    out.uv = (pos + 1.0) * 0.5;
    out.uv.y = 1.0 - out.uv.y;  // Flip Y for texture sampling
    
    return out;
}

// ═══════════════════════════════════════════════════════════════════════
// FRAGMENT SHADER - SDF VISUALIZATION WITH RAINBOW BANDS
// ═══════════════════════════════════════════════════════════════════════

fragment float4 simpleFragment(
    VertexOut in [[stage_in]],
    texture2d<float> backgroundTex [[texture(0)]],
    constant Params &params [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    // UV directly maps to view (0-1 = full view)
    float2 viewUV = in.uv;
    
    // Convert UV (0-1) to pixel coordinates
    float2 pixelCoord = viewUV * params.resolution;
    
    // Get center and dimensions
    float2 pixelCenter = params.resolution * 0.5;
    float2 halfSize = params.resolution * 0.5;
    
    // Position relative to center
    float2 p = pixelCoord - pixelCenter;
    
    // ═══════════════════════════════════════════════════════════════════
    // CALCULATE SDF FIRST (defines the shape boundary)
    // ═══════════════════════════════════════════════════════════════════
    
    float sdf = roundedRectSDF(p, halfSize, params.cornerRadius);
    
    // ═══════════════════════════════════════════════════════════════════
    // APPLY DISTORTION ONLY INSIDE THE SHAPE (for lens effect)
    // ═══════════════════════════════════════════════════════════════════
    
    float2 samplingPixelCoord = pixelCoord;  // Default: sample from original position
    
    if (sdf < 0.0) {
        // INSIDE the shape - CENTER MINIFIES, EDGES MAGNIFY
        
        // Calculate direction from center (normalized)
        float2 toCenter = p / halfSize;
        float dist = length(toCenter);
        float2 direction = dist > 0.001 ? normalize(toCenter) : float2(0.0);
        
        // Get edge factor (0 at center, 1 at edges) using steep curve
        float edgeFactor = sdfBasedDistortion(sdf, halfSize, params.distortionThreshold);
        
        float maxRadius = max(halfSize.x, halfSize.y);
        float strength = params.distortionStrength;
        
        // MINIFY offset (sample from OUTSIDE - makes things smaller)
        float minifyAmount = (1.0 - edgeFactor) * strength * params.minifyMultiplier;
        float2 minifyOffset = direction * dist * minifyAmount * maxRadius;
        
        // MAGNIFY offset (sample from INSIDE - makes things bigger)  
        float magnifyAmount = edgeFactor * strength * params.magnifyMultiplier;
        float2 magnifyOffset = direction * dist * magnifyAmount * maxRadius;
        
        // Apply both: ADD for minify, SUBTRACT for magnify
        samplingPixelCoord = pixelCoord + minifyOffset - magnifyOffset;
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // TEXTURE SAMPLING WITH PADDING
    // ═══════════════════════════════════════════════════════════════════
    // View: 200×100, Padding: 25% → Texture: 300×150
    // Padding in pixels: X = 200*0.25 = 50, Y = 100*0.25 = 25
    // 
    // To sample texture at view pixel (x, y):
    //   texturePixel.x = x + paddingX = x + viewWidth * paddingFactor
    //   texturePixel.y = y + paddingY = y + viewHeight * paddingFactor
    //
    // In UV space:
    //   textureUV.x = (x + viewWidth * padding) / paddedWidth
    //                = (x + viewWidth * padding) / (viewWidth * paddedScale)
    //   textureUV.y = (y + viewHeight * padding) / paddedHeight
    //                = (y + viewHeight * padding) / (viewHeight * paddedScale)
    // ═══════════════════════════════════════════════════════════════════
    
    float paddedScale = 1.0 + 2.0 * params.paddingFactor;  // 1.5 for 25% padding
    
    // Calculate padding in pixels for each dimension
    float2 paddingPixels = params.resolution * params.paddingFactor;  // (50, 25) for 200×100
    
    // Calculate padded texture size in pixels
    float2 paddedSize = params.resolution * paddedScale;  // (300, 150) for 200×100
    
    // Convert sampling pixel coord to texture UV
    // samplingPixelCoord is in VIEW space (can be outside 0-resolution due to distortion)
    // We add padding offset to get texture pixel, then divide by padded size for UV
    float2 texturePixelCoord = samplingPixelCoord + paddingPixels;
    float2 textureSamplingUV = texturePixelCoord / paddedSize;
    
    // ═══════════════════════════════════════════════════════════════════
    // GLASS EFFECT - Background with distortion, blur, tint, and Fresnel
    // ═══════════════════════════════════════════════════════════════════
    
    float3 color;
    float alpha;
    
    // Soft edge width for anti-aliased boundary
    float softEdgeWidth = 0.5;
    
    // Render inside AND the soft transition zone (sdf < softEdgeWidth)
    if (sdf < softEdgeWidth) {
        // INSIDE or EDGE TRANSITION - Sample background with chromatic aberration
        float2 textureCenter = float2(0.5, 0.5);  // Center of texture
        float chromaticStrength = 0.03;  // Stronger color fringing at edges
        color = applyChromaticAberration(backgroundTex, texSampler, textureSamplingUV, 
                                         textureCenter, sdf, halfSize, chromaticStrength);
        
        // Apply Internal Reflection (light bouncing inside glass)
        // float reflectionStrength = 0.15;  // Subtle reflection (0-1)
        // color = applyInternalReflection(backgroundTex, texSampler, textureSamplingUV,
        //                                 textureCenter, sdf, halfSize, reflectionStrength);
        
        // Apply blur on top
        float3 blurredColor = applyGaussianBlur(backgroundTex, texSampler, textureSamplingUV, 
                                                 params.blurRadius, params.resolution);
        color = mix(blurredColor, color, 0.7);  // Blend: 70% CA, 30% blur
        
        // Apply glass tint (slight darkening)
        color *= 0.95;
        
        // Apply Inner Shadow (depth/thickness illusion)
        float2 shapeCenter = params.resolution * 0.5;
        float shadowWidth = 8.0;       // Shadow extends 4 pixels from edge
        float shadowIntensity = 0.1;   // Very subtle shadow (0-1)
        color = applyInnerShadow(color, sdf, pixelCoord, shapeCenter, shadowWidth, shadowIntensity, params.shadowDirection);
        
        // Apply Edge Tint (subtle color at edges like thick glass)
        float3 edgeTintColor = float3(0.85, 0.92, 1.0);  // Subtle blue-white tint
        float edgeTintWidth = 12.0;    // Tint extends 12 pixels from edge
        float edgeTintIntensity = 0.15; // Subtle effect
        color = applyEdgeTint(color, sdf, halfSize, edgeTintColor, edgeTintWidth, edgeTintIntensity);
        
        // Apply Fresnel effect (bright highlight at edges)
        // Use opposite of shadow direction (light comes from opposite side)
        float2 fresnelDir = -params.shadowDirection;
        color = applyFresnelEffect(color, sdf, halfSize, pixelCoord, shapeCenter, fresnelDir);
        
        // Apply Specular Rim / Caustic Line (sharp bright edge)
        float rimWidth = 3.0;      // Width of caustic line in pixels
        float rimIntensity = 0.5;  // Brightness (0-1)
        color = applySpecularRim(color, sdf, pixelCoord, shapeCenter, rimWidth, rimIntensity);
        
        // Apply Soft Edge (anti-aliased boundary)
        // Use opposite of shadow direction (light comes from opposite side)
        float2 lightDir = -params.shadowDirection;
        alpha = calculateSoftEdgeAlpha(sdf, softEdgeWidth, pixelCoord, shapeCenter, lightDir);
    } 
    else {
        // OUTSIDE - Fully transparent
        color = float3(0.0);
        alpha = 0.0;
    }
    
    return float4(color, alpha);
}

