#ifndef IMPOSTER_LIT_INPUT_INCLUDED
#define IMPOSTER_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _BaseMap_ST;
half4 _BaseColor;
half4 _SpecColor;
half4 _EmissionColor;
half _Cutoff;
half _Smoothness;
half _Metallic;
half _BumpScale;
half _OcclusionStrength;

half _ImposterFrames;
half _ImposterSize;
half3 _ImposterOffset;
half _ImposterFullSphere;
half _ImposterBorderClamp;
float4 _ImposterBaseTex_TexelSize;
CBUFFER_END

TEXTURE2D(_ImposterBaseTex);                SAMPLER(sampler_ImposterBaseTex);
TEXTURE2D(_ImposterWorldNormalDepthTex);    SAMPLER(sampler_ImposterWorldNormalDepthTex);
SAMPLER(sampler_LinearClamp);

#endif //IMPOSTER_LIT_INPUT_INCLUDED



//CBUFFER_START(UnityPerMaterial)

//half _ImposterFrames;
//half _ImposterSize;
//half3 _ImposterOffset;
//half _ImposterFullSphere;
//half _ImposterBorderClamp;
//float4 _ImposterBaseTex_TexelSize;
//CBUFFER_END

//TEXTURE2D(_ImposterBaseTex);SAMPLER(sampler_ImposterBaseTex);
//TEXTURE2D(_ImposterWorldNormalDepthTex);    SAMPLER(sampler_ImposterWorldNormalDepthTex);

//SAMPLER(sampler_LinearClamp);