#ifndef IMPOSTER_LIT_FORWARD_PASS
#define IMPOSTER_LIT_FORWARD_PASS

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

#include "ImposterCommon.hlsl"

struct Attributes
{
	float4 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float4 tangentOS : TANGENT;
	float2 uv : TEXCOORD0;
	float2 uvLM : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
	float4 uvAndGrid : TEXCOORD0;
	float2 uvLM : TEXCOORD1;
	float4 positionWSAndFogFactor : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
	half3 normalWS : TEXCOORD3;
	half3 tangentWS : TEXCOORD4;
	half3 bitangentWS : TEXCOORD5;

#ifdef _MAIN_LIGHT_SHADOWS
    float4 shadowCoord              : TEXCOORD6; // compute shadow coord per-vertex for the main light
#endif
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

Varyings LitPassVertex(Attributes input)
{
	Varyings output;
    
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

	ImposterData imp;
	imp.vertex = input.positionOS;
	imp.uv = input.uv;
	ImposterVertex(imp);

	float4 positionOS = imp.vertex;
	float4 positionCS = TransformObjectToHClip(positionOS.xyz);
	float3 positionWS = TransformObjectToWorld(positionOS.xyz);
	float fogFactor = ComputeFogFactor(positionCS.z);
    float3 normalWS = TransformObjectToWorldDir(imp.billboardNormalOS);
	float3 tangentWS = TransformObjectToWorldDir(input.tangentOS.xyz);
	float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWS, tangentWS, input.tangentOS.w);

	output.tangentWS = tangentToWorld[0];
	output.bitangentWS = tangentToWorld[1];
	output.normalWS = tangentToWorld[2];
	output.uvAndGrid.xy = imp.uv;
	output.uvAndGrid.zw = imp.grid;
	output.plane0 = imp.frame0;
	output.plane1 = imp.frame1;
	output.plane2 = imp.frame2;
	output.positionWSAndFogFactor = float4(positionWS, fogFactor);
	output.positionCS = positionCS;

	return output;
}

float3 ReconstructWorldSpacePosition(float3 positionWS, float3 normalWS, float depthOffset) {
    return positionWS + normalWS * (depthOffset - 0.5) * _ImposterSize * -2;
}

half4 LitPassFragment(Varyings input/*, out half outputDepth : DEPTH*/) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
#if defined(LOD_FADE_CROSSFADE)
	LODDitheringTransition(input.positionCS.xy, unity_LODFade.x);
#endif
    
    
	ImposterData imp;
	imp.uv = input.uvAndGrid.xy;
	imp.grid = input.uvAndGrid.zw;
	imp.frame0 = input.plane0;
	imp.frame1 = input.plane1;
	imp.frame2 = input.plane2;

	//perform texture sampling
	half4 baseTex;
	half4 normalTex;
		    
	ImposterSample(imp, baseTex, normalTex);
    
	baseTex.a = saturate(pow(baseTex.a, _Cutoff));
	clip(baseTex.a - _Cutoff);

	//scale world normal back to -1 to 1
	half3 normalOS = normalTex.xyz * 2 - 1;
	half3 normalWS = TransformObjectToWorldNormal(normalOS);

//	half3 t = input.tangentWS;
//	half3 b = input.bitangentWS;
//	half3 n = input.normalWS;
    
        
//	// TODO: What purpose did this serve?
	
////	//from UnityStandardCore.cginc 
//#if UNITY_TANGENT_ORTHONORMALIZE
//	n = normalize(n);
        
//	//ortho-normalize Tangent
//	t = normalize (t - n * dot(t, n));
                
//	//recalculate Binormal
//	half3 newB = cross(n, t);
//	b = newB * sign (dot (newB, b));
//#endif
//    half3x3 tangentToWorld = half3x3(t, b, n);


#ifdef LIGHTMAP_ON
	// Normal is required in case Directional lightmaps are baked
	half3 bakedGI = SampleLightmap(input.uvLM, normalWS);
#else
	// Samples SH fully per-pixel. SampleSHVertex and SampleSHPixel functions
	// are also defined in case you want to sample some terms per-vertex.
	half3 bakedGI = SampleSH(normalWS);
#endif

    float3 positionWS = input.positionWSAndFogFactor.xyz;
    positionWS = ReconstructWorldSpacePosition(positionWS, input.normalWS, 1 - normalTex.w);
    half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);
    
#ifdef _MAIN_LIGHT_SHADOWS
	float4 shadowCoord;
	shadowCoord = TransformWorldToShadowCoord(positionWS);
	Light mainLight = GetMainLight(shadowCoord);
#else
    Light mainLight = GetMainLight();
#endif

	// Surface data contains albedo, metallic, specular, smoothness, occlusion, emission and alpha
	// InitializeStandarLitSurfaceData initializes based on the rules for standard shader.
	// You can write your own function to initialize the surface data of your shader.
	SurfaceData surfaceData;

	surfaceData.albedo = baseTex.rgb * _BaseColor.rgb;
	surfaceData.alpha = baseTex.a;
	surfaceData.metallic = _Metallic;
	surfaceData.smoothness = _Smoothness;
	surfaceData.occlusion = 1;
	surfaceData.specular = 0;
	surfaceData.emission = 0;

	// BRDFData holds energy conserving diffuse and specular material reflections and its roughness.
	// It's easy to plugin your own shading fuction. You just need replace LightingPhysicallyBased function
	// below with your own.
	BRDFData brdfData;
	InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);
				
	// Mix diffuse GI with environment reflections.
	half3 color = GlobalIllumination(brdfData, bakedGI, surfaceData.occlusion, normalWS, viewDirectionWS);

	// LightingPhysicallyBased computes direct light contribution.
	color += LightingPhysicallyBased(brdfData, mainLight, normalWS, viewDirectionWS);

	// Additional lights loop
#ifdef _ADDITIONAL_LIGHTS
	// Returns the amount of lights affecting the object being renderer.
	// These lights are culled per-object in the forward renderer
	int additionalLightsCount = GetAdditionalLightsCount();
	for (int i = 0; i < additionalLightsCount; ++i)
	{
		// Similar to GetMainLight, but it takes a for-loop index. This figures out the
		// per-object light index and samples the light buffer accordingly to initialized the
		// Light struct. If _ADDITIONAL_LIGHT_SHADOWS is defined it will also compute shadows.
		Light light = GetAdditionalLight(i, positionWS);

		// Same functions used to shade the main light.
		color += LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
	}
#endif
	// Emission
	color += surfaceData.emission;

	float fogFactor = input.positionWSAndFogFactor.w;

	// Mix the pixel color with fogColor. You can optionaly use MixFogColor to override the fogColor
	// with a custom one.
	color = MixFog(color, fogFactor);

	//return half4(color, 1);
	return half4(color, surfaceData.alpha);
}

#endif //IMPOSTER_LIT_FORWARD_PASS