Shader "XRA/IMP/Standard URP" {
	Properties {
		_Color ("Color", Color) = (1,1,1,1)
        
		_Glossiness ("Smoothness", Range(0,1)) = 0.5
		_Metallic ("Metallic", Range(0,1)) = 0.0
		
		_Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.3
		
		_ImposterBaseTex ("Imposter Base", 2D) = "black" {}
		_ImposterWorldNormalDepthTex ("WorldNormal+Depth", 2D) = "black" {}
		_ImposterFrames ("Frames",  float) = 8
		_ImposterSize ("Radius", float) = 1
		_ImposterOffset ("Offset", Vector) = (0,0,0,0)
		_ImposterFullSphere ("Full Sphere", float) = 0
		_ImposterBorderClamp ("Border Clamp", float) = 2.0
		
        //_Mode ("__mode", Float) = 0.0 
        //_SrcBlend ("__src", Float) = 1.0
        //_DstBlend ("__dst", Float) = 0.0
        //_ZWrite ("__zw", Float) = 1.0
        //[HideInInspector] 
 
	}
	SubShader {  
		Tags { "RenderType"="Opaque" }
		//LOD 200

		Pass {
			Name "Universal Forward"
			Tags{"LightMode" = "UniversalForward"}
			AlphaToMask On
			//Blend SrcAlpha OneMinusSrcAlpha  

			ZTest LEqual
			ZWrite On
			Cull Back 
			Blend Off
        
			HLSLPROGRAM
			// Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            // unused shader_feature variants are stripped from build automatically
            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICSPECGLOSSMAP
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _OCCLUSIONMAP

            #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature _SPECULAR_SETUP
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Render Pipeline keywords
            // When doing custom shaders you most often want to copy and past these #pragmas
            // These multi_compile variants are stripped from the build depending on:
            // 1) Settings in the LWRP Asset assigned in the GraphicsSettings at build time
            // e.g If you disable AdditionalLights in the asset then all _ADDITIONA_LIGHTS variants
            // will be stripped from build
            // 2) Invalid combinations are stripped. e.g variants with _MAIN_LIGHT_SHADOWS_CASCADE
            // but not _MAIN_LIGHT_SHADOWS are invalid and therefore stripped.
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
			#pragma multi_compile _ LOD_FADE_CROSSFADE

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            //--------------------------------------
            // GPU Instancing
            /#pragma multi_compile_instancing
			//#pragma instancing_options assumeuniformscaling

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "ImposterCommon.hlsl"

			CBUFFER_START(Foo)
			half _Glossiness;
			half4 _Color;
			CBUFFER_END

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                float2 uvLM         : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 uvAndGrid                : TEXCOORD0;
                float2 uvLM                     : TEXCOORD1;
                float4 positionWSAndFogFactor   : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
                half3  normalWS                 : TEXCOORD3;
                half3 tangentWS                 : TEXCOORD4;
                half3 bitangentWS               : TEXCOORD5;

#ifdef _MAIN_LIGHT_SHADOWS
                float4 shadowCoord              : TEXCOORD6; // compute shadow coord per-vertex for the main light
#endif
				float4 plane0					: TEXCOORD7;
				float4 plane1					: TEXCOORD8;
				float4 plane2					: TEXCOORD9;
                float4 positionCS               : SV_POSITION;
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

				ImposterData imp;
				imp.vertex = input.positionOS;
				imp.uv = input.uv;
				ImposterVertex(imp);

				float4 positionOS = imp.vertex;
				float4 positionCS = TransformObjectToHClip(positionOS.xyz);
				float3 positionWS = TransformObjectToWorld(positionOS.xyz);
				float fogFactor = ComputeFogFactor(positionCS.z);
				float3 normalWS = TransformObjectToWorldDir(input.normalOS.xyz);
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

			half4 LitPassFragment(Varyings input) : SV_Target
			{
//#if defined(LOD_FADE_CROSSFADE)
//				LODDitheringTransition(input.positionCS.xy, unity_LODFade.x);
//#endif

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
				baseTex.a = saturate( pow(baseTex.a,_Cutoff) );
				clip(baseTex.a -_Cutoff);

				

				//scale world normal back to -1 to 1
				half3 normalOS = normalTex.xyz*2-1;
				half3 normalWS = TransformObjectToWorldNormal(normalOS);

				half depth = normalTex.w; //maybe for pixel depth?
            
				half3 t = input.tangentWS;
				half3 b = input.bitangentWS;
				half3 n = input.normalWS;
        
				//from UnityStandardCore.cginc 
				#if UNITY_TANGENT_ORTHONORMALIZE
					n = normalize(n);
        
					//ortho-normalize Tangent
					t = normalize (t - n * dot(t, n));
                
					//recalculate Binormal
					half3 newB = cross(n, t);
					b = newB * sign (dot (newB, b));
				#endif
				half3x3 tangentToWorld = half3x3(t, b, n);


#ifdef LIGHTMAP_ON
				// Normal is required in case Directional lightmaps are baked
				half3 bakedGI = SampleLightmap(input.uvLM, normalWS);
#else
				// Samples SH fully per-pixel. SampleSHVertex and SampleSHPixel functions
				// are also defined in case you want to sample some terms per-vertex.
				half3 bakedGI = SampleSH(normalWS);
#endif

				float3 positionWS = input.positionWSAndFogFactor.xyz;
				half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);

//
//#ifdef _MAIN_LIGHT_SHADOWS
//				float4 shadowCoord;
//#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
//				shadowCoord = input.shadowCoord;
//#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
//				shadowCoord = TransformWorldToShadowCoord(positionWS);
//#else
//				shadowCoord = float4(0, 0, 0, 0);
//#endif
//				Light mainLight = GetMainLight(shadowCoord);
//
//#else
//				Light mainLight = GetMainLight();
//#endif

				// TODO: Receiving shadows. Need to reconstruct world position using depth
				Light mainLight = GetMainLight();

				// Surface data contains albedo, metallic, specular, smoothness, occlusion, emission and alpha
				// InitializeStandarLitSurfaceData initializes based on the rules for standard shader.
				// You can write your own function to initialize the surface data of your shader.
				SurfaceData surfaceData;

				surfaceData.albedo = baseTex.rgb * _Color.rgb;
				surfaceData.alpha = baseTex.a;
				surfaceData.metallic = _Metallic;
				surfaceData.smoothness = _Glossiness;
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
			ENDHLSL
		}

		Pass {
			Name "ShadowCaster"
			Tags{"LightMode" = "ShadowCaster"}
			AlphaToMask On
			//Blend SrcAlpha OneMinusSrcAlpha  

			ZTest LEqual
			ZWrite On
			Cull Back 
			Blend Off
        
			HLSLPROGRAM
			// Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            // unused shader_feature variants are stripped from build automatically
            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICSPECGLOSSMAP
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _OCCLUSIONMAP

            #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature _SPECULAR_SETUP
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Render Pipeline keywords
            // When doing custom shaders you most often want to copy and past these #pragmas
            // These multi_compile variants are stripped from the build depending on:
            // 1) Settings in the LWRP Asset assigned in the GraphicsSettings at build time
            // e.g If you disable AdditionalLights in the asset then all _ADDITIONA_LIGHTS variants
            // will be stripped from build
            // 2) Invalid combinations are stripped. e.g variants with _MAIN_LIGHT_SHADOWS_CASCADE
            // but not _MAIN_LIGHT_SHADOWS are invalid and therefore stripped.
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
			#pragma multi_compile _ LOD_FADE_CROSSFADE

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #pragma vertex ShadowCasterPassVertex
            #pragma fragment ShadowCasterPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "ImposterCommon.hlsl"

			CBUFFER_START(UnityPerMaterial)
			half _Glossiness;
			half4 _Color;
			CBUFFER_END

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 uvAndGrid                : TEXCOORD0;
				float4 plane0					: TEXCOORD7;
				float4 plane1					: TEXCOORD8;
				float4 plane2					: TEXCOORD9;
                float4 positionCS               : SV_POSITION;
            };

			inline half3x3 CreateTangentToWorldPerVertex(half3 normal, half3 tangent, half tangentSign)
			{
				// For odd-negative scale transforms we need to flip the sign
				half sign = tangentSign * unity_WorldTransformParams.w;
				half3 binormal = cross(normal, tangent) * sign;
				return half3x3(tangent, binormal, normal);
			}

			float3 _LightDirection;
			float4 GetShadowPositionHClip(float3 positionWS, half3 normalWS) {
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
				Varyings output;

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

			half4 ShadowCasterPassFragment(Varyings input) : SV_Target
			{
				ImposterData imp;
				imp.uv = input.uvAndGrid.xy;
				imp.grid = input.uvAndGrid.zw;
				imp.frame0 = input.plane0;
				imp.frame1 = input.plane1;
				imp.frame2 = input.plane2;

				//perform texture sampling
				half4 baseTex;
				half4 normalTex;
		    
				// TODO: Don't need normal for shadows
				ImposterSample(imp, baseTex, normalTex);
				baseTex.a = saturate( pow(baseTex.a,_Cutoff) );
				clip(baseTex.a-_Cutoff);

				return 1;
			}

			ENDHLSL
		}
	}
	//FallBack "Diffuse"
	
	//CustomEditor "StandardShaderGUI"
}