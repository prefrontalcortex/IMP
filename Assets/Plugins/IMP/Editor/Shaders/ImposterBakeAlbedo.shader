Shader "Hidden/XRA/IMP/ImposterBakeAlbedo"
{
	Properties
	{
		[MainTexture] _BaseMap("Albedo", 2D) = "white" {}
	}
		SubShader
	{
		Cull off ZWrite on ZTest LEqual

		Pass
		{
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			TEXTURE2D(_BaseMap);	SAMPLER(sampler_BaseMap);

			float4 _BaseMap_ST;
			float4 _BaseMap_TexelSize;

			float4 _BaseColor;

			half _ImposterRenderAlpha; //hacky used to toggle alpha only output only due to relying on replacement shaders

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float4 screenPos : TEXCOORD1;
			};

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = TransformObjectToHClip(v.vertex);
				o.screenPos = ComputeScreenPos(o.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
				return o;
			}

			float4 frag(v2f i) : SV_Target
			{
				//half2 spos = i.screenPos.xy / i.screenPos.w;
				//spos *= 0.5+0.5;
				//half dist = distance(spos.xy,half2(0.5,0.5));
				//
				//dist = 1-saturate( dist / 0.2);

				float4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;

				// TODO expose clipping somehow
				clip (col.a - 0.3);

				if (_ImposterRenderAlpha > 0.5)
				{
					return col.aaaa;
				}

				return col;
			}
			ENDHLSL
		}
	}
}
