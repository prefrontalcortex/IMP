#ifndef IMPOSTER_SHADOW_CASTER_PASS
#define IMPOSTER_SHADOW_CASTER_PASS

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#include "ImposterCommon.hlsl"

float3 _LightDirection;

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 uvAndGrid : TEXCOORD0;
    float4 plane0 : TEXCOORD7;
    float4 plane1 : TEXCOORD8;
    float4 plane2 : TEXCOORD9;
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

inline half3x3 CreateTangentToWorldPerVertex(half3 normal, half3 tangent, half tangentSign)
{
	// For odd-negative scale transforms we need to flip the sign
    half sign = tangentSign * unity_WorldTransformParams.w;
    half3 binormal = cross(normal, tangent) * sign;
    return half3x3(tangent, binormal, normal);
}

float4 GetShadowPositionHClip(float3 positionWS, half3 normalWS)
{
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

#if UNITY_REVERSED_Z
	positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}


Varyings ShadowCasterPassVertex(Attributes input)
{
    Varyings output = (Varyings) 0;
    
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    ImposterData imp;
    imp.vertex = input.positionOS;
    imp.uv = input.uv;
    ImposterVertexShadow(imp);

    float4 positionOS = imp.vertex;
    float3 positionWS = TransformObjectToWorld(positionOS);
    float3 normalWS = TransformObjectToWorldDir(input.normalOS.xyz);
    float4 positionCS = GetShadowPositionHClip(positionWS, normalWS);

    output.uvAndGrid.xy = imp.uv;
    output.uvAndGrid.zw = imp.grid;
    output.plane0 = imp.frame0;
    output.plane1 = imp.frame1;
    output.plane2 = imp.frame2;
    output.positionCS = positionCS;

    return output;
}

half4 ShadowCasterPassFragment(Varyings input/*, out float depth : DEPTH*/) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
//#if defined(LOD_FADE_CROSSFADE)
//	LODDitheringTransition(input.positionCS.xy, unity_LODFade.x);
//#endif
    
    ImposterData imp;
    imp.uv = input.uvAndGrid.xy;
    imp.grid = input.uvAndGrid.zw;
    imp.frame0 = input.plane0;
    imp.frame1 = input.plane1;
    imp.frame2 = input.plane2;

	// Perform texture sampling
    half4 baseTex;
    half4 normalTex;
		    
	// TODO: Don't need normal for shadows
    ImposterSample(imp, baseTex, normalTex);
    baseTex.a = saturate(pow(baseTex.a, _Cutoff));
    clip(baseTex.a - _Cutoff);

    return 1;
}

#endif //IMPOSTER_SHADOW_CASTER_PASS