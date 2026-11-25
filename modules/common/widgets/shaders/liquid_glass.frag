#version 440
// iOS 27 Liquid Glass surface fragment shader: analytical rounded-box SDF with
// directional Fresnel specular bevels, prismatic edge refraction, volumetric depth,
// and an interactive liquid caustic highlight.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;
    vec4 radii;         // x: topRight, y: bottomRight, z: topLeft, w: bottomLeft
    vec4 freeEdges;     // x: left, y: top, z: right, w: bottom (1 = free rim, 0 = docked)
    vec4 bodyColor;
    vec4 rimColor;
    vec4 chromaColor;
    vec4 counterColor;
    vec4 depthColor;
    vec2 lightPos;
    float rimWidth;
    float lensStrength;
};

float sdRoundedBox(vec2 p, vec2 b, vec4 rad) {
    float maxR = max(min(b.x, b.y), 0.0);
    float r = (p.x >= 0.0)
        ? ((p.y >= 0.0) ? rad.y : rad.x)
        : ((p.y >= 0.0) ? rad.w : rad.z);
    r = clamp(r, 0.0, maxR);
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 size = max(res, vec2(1.0));
    vec2 halfSize = size * 0.5;
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * size;

    float d = sdRoundedBox(p, halfSize, radii);
    float mask = clamp(0.5 - d, 0.0, 1.0);
    if (mask <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 grad = vec2(
        sdRoundedBox(p + vec2(0.75, 0.0), halfSize, radii) - sdRoundedBox(p - vec2(0.75, 0.0), halfSize, radii),
        sdRoundedBox(p + vec2(0.0, 0.75), halfSize, radii) - sdRoundedBox(p - vec2(0.0, 0.75), halfSize, radii)
    );
    float gradLen = length(grad);
    vec2 n = gradLen > 1e-5 ? grad / gradLen : vec2(0.0, -1.0);

    float edgeDist = max(-d, 0.0);
    float edgeMask = 1.0;
    edgeMask *= mix(smoothstep(0.0, 4.0, halfSize.x + p.x), 1.0, freeEdges.x);
    edgeMask *= mix(smoothstep(0.0, 4.0, halfSize.y + p.y), 1.0, freeEdges.y);
    edgeMask *= mix(smoothstep(0.0, 4.0, halfSize.x - p.x), 1.0, freeEdges.z);
    edgeMask *= mix(smoothstep(0.0, 4.0, halfSize.y - p.y), 1.0, freeEdges.w);

    // 1. Volumetric translucent glass body
    vec3 rgb = mix(bodyColor.rgb, depthColor.rgb, smoothstep(0.5, 1.0, uv.y) * 0.18 * depthColor.a);
    float topSheen = exp(-uv.y * 3.4) * 0.14 * lensStrength;
    rgb += rimColor.rgb * topSheen;

    // 2. Interactive liquid specular caustic glide
    float minDim = max(min(size.x, size.y), 1.0);
    vec2 delta = (uv - lightPos) * (size / minDim);
    float caustic = exp(-dot(delta, delta) * 6.5) * 0.11 * lensStrength * rimColor.a;
    rgb += rimColor.rgb * caustic;

    // 3. Inner chromatic edge refraction band (1px to 5.5px inside boundary)
    float chromaBand = exp(-max(edgeDist - 1.0, 0.0) / 3.2) * (0.45 + 0.55 * abs(n.x - n.y));
    float innerFade = smoothstep(0.0, 1.2, edgeDist);
    rgb += chromaColor.rgb * (chromaColor.a * 0.65 * lensStrength * chromaBand * innerFade * edgeMask);

    // 4. Dual-lobe Fresnel specular rim
    vec2 L1 = normalize(vec2(-0.62, -0.78));
    float rimFalloff = exp(-edgeDist / max(rimWidth, 0.25)) * edgeMask;
    float lobe1 = pow(max(dot(n, L1), 0.0), 1.5);
    float lobe2 = 0.48 * pow(max(dot(n, -L1), 0.0), 2.2);
    float ambientRim = 0.22;

    vec3 rimLight = rimColor.rgb * (lobe1 + ambientRim) * rimColor.a
                  + counterColor.rgb * lobe2 * counterColor.a;
    float rimAlpha = clamp((lobe1 + ambientRim) * rimColor.a + lobe2 * counterColor.a, 0.0, 1.0) * rimFalloff;
    rgb += rimLight * rimFalloff * lensStrength;

    // Keep interior alpha >= bodyColor.a so compositor ignore_alpha blur stays continuous
    float alpha = clamp(bodyColor.a + rimAlpha * 0.35, bodyColor.a, 1.0) * mask * qt_Opacity;
    fragColor = vec4(clamp(rgb, 0.0, 1.0) * alpha, alpha);
}
