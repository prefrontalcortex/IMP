Shader "Hidden/XRA/IMP/ImposterBakeWorldNormalDepth"
{
	Properties
	{
		[MainTexture] _BaseMap("Albedo", 2D) = "white" {}
		_BumpMap ("Normal", 2D) = "bump" {}
	}
	SubShader
	{
		Cull Off
		ZWrite On
		ZTest LEqual

		Pass
		{
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			float4 _BumpMap_TexelSize;
			float4 _BumpMap_ST;
			float4 _MainTex_ST;
			float _BumpScale;
			
			// CODY
			TEXTURE2D(_BumpMap);	SAMPLER(sampler_BumpMap);
			TEXTURE2D(_BaseMap);	SAMPLER(sampler_BaseMap);
			float4 _BaseMap_ST;
			float4 _BaseMap_TexelSize;

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float4 TtoW0 : TEXCOORD1;
				float4 TtoW1 : TEXCOORD2;
				float4 TtoW2 : TEXCOORD3;
				float  depth : TEXCOORD4;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = TransformObjectToHClip(v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
				
				float3 worldPos = TransformObjectToWorld(v.vertex); //mul(unity_ObjectToWorld,v.vertex);
                float3 worldNormal = TransformObjectToWorldNormal(v.normal); //UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = TransformObjectToWorldDir(v.tangent.xyz); // UnityObjectToWorldDir(v.tangent.xyz);
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;
   
                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);
				
				// TOOD: fix
				//o.depth = COMPUTE_DEPTH_01;

				//float eyeDepth = LinearEyeDepth(worldPos, UNITY_MATRIX_V);
				//float d = length(worldPos - _WorldSpaceCameraPos);
				//o.depth = Linear01Depth(d, _ZBufferParams);

				o.depth = -mul(UNITY_MATRIX_MV, v.vertex).z *_ProjectionParams.w;
				return o;
			}
			


			float4 frag (v2f i) : SV_Target
			{
			    float3 worldPos = float3(i.TtoW0.w,i.TtoW1.w,i.TtoW2.w);

			    float depth = 1-i.depth;
			
				//float3 normTangent = UnpackScaleNormal( SAMPLE(_BumpMap, i.uv), _BumpScale );
				float3 normTangent = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv));
				
				float3 normWorld = normalize( float3( dot(i.TtoW0.xyz, normTangent), dot(i.TtoW1.xyz, normTangent), dot(i.TtoW2.xyz, normTangent) ) );
				
				float4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
				// TODO: expose alpha clip
				clip(baseTex.a - 0.3);
				return float4(normWorld.rgb*0.5+0.5, depth);
			}
			ENDHLSL
		}
	}
}
