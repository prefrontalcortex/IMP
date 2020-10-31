﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System;

namespace IMP
{
    public class IMPGenerator
    {

        public static void DebugSnapshots(Transform root, BillboardSettings settings)
        {
            BillboardImposter imposterAsset;
            Snapshots[] snapshots;

            if (SetupRig(root, settings, out imposterAsset, out snapshots))
                DebugSnapshots(snapshots, imposterAsset.Radius);
        }

        private static void DebugSnapshots(Snapshots[] snapshots, float rayScale)
        {
            for (var i = 0; i < snapshots.Length; i++)
                Debug.DrawRay(snapshots[i].Position, snapshots[i].Ray * rayScale, Color.green, 0.5f);
        }

        private static bool SetupRig(Transform root, BillboardSettings settings, out BillboardImposter imposterAsset, out Snapshots[] snapshots)
        {
            var mrs = root.GetComponentsInChildren<MeshRenderer>();
            imposterAsset = null;
            snapshots = null;
            if (mrs == null || mrs.Length == 0) return false;

            imposterAsset = ScriptableObject.CreateInstance<BillboardImposter>();

            //grow bounds, first centered on root transform 
            var bounds = new Bounds(root.position, Vector3.zero);
            for (var i = 0; i < mrs.Length; i++)
            {
                //check if mesh renderer enabled
                if (!mrs[i].enabled) continue;
                //instead of encapsulating mesh renderer bounds, encapsulate vertices
                //this is because mesh bounds are sometimes much larger than needed
                var mf = mrs[i].GetComponent<MeshFilter>();
                if (mf == null || mf.sharedMesh == null || mf.sharedMesh.vertices == null) continue;
                var verts = mf.sharedMesh.vertices;
                for (var v = 0; v < verts.Length; v++)
                {
                    var meshWorldVert = mf.transform.localToWorldMatrix.MultiplyPoint3x4(verts[v]);
                    var meshLocalToRoot = root.worldToLocalMatrix.MultiplyPoint3x4(meshWorldVert);
                    var worldVert = root.localToWorldMatrix.MultiplyPoint3x4(meshLocalToRoot);
                    bounds.Encapsulate(worldVert);
                }
            }

            //the bounds will fit within the sphere
            var radius = Vector3.Distance(bounds.min, bounds.max) * 0.5f;
            imposterAsset.Radius = radius;
            imposterAsset.Frames = settings.frames;
            imposterAsset.IsHalf = settings.isHalf;
            imposterAsset.AtlasResolution = settings.atlasResolution;
            imposterAsset.Offset = bounds.center - root.position;

            Debug.DrawLine(bounds.min, bounds.max, Color.cyan, 1f);
#if UNITY_2018_2_OR_NEWER
            imposterAsset.AssetReference = (GameObject)PrefabUtility.GetCorrespondingObjectFromSource(root.gameObject);
#else
        imposterAsset.AssetReference = (GameObject) PrefabUtility.GetPrefabParent(root.gameObject);
#endif

            snapshots = UpdateSnapshots(settings.frames, radius, root.position + imposterAsset.Offset, settings.isHalf);

            DebugSnapshots(snapshots, radius * 0.1f);
            return true;
        }

        /// <summary>
        ///     constructs the snapshot data for camera position and rays
        /// </summary>
        private static Snapshots[] UpdateSnapshots(int frames, float radius, Vector3 origin, bool isHalf = true)
        {
            var snapshots = new Snapshots[frames * frames];

            float framesMinusOne = frames - 1;

            var i = 0;
            for (var y = 0; y < frames; y++)
                for (var x = 0; x < frames; x++)
                {
                    var vec = new Vector2(
                        x / framesMinusOne * 2f - 1f,
                        y / framesMinusOne * 2f - 1f
                    );
                    var ray = isHalf ? OctahedralCoordToVectorHemisphere(vec) : OctahedralCoordToVector(vec);

                    ray = ray.normalized;

                    snapshots[i].Position = origin + ray * radius;
                    snapshots[i].Ray = -ray;
                    i++;
                }

            return snapshots;
        }

        private static Vector2 Get2DIndex(int i, int res)
        {
            float x = i % res;
            float y = (i - x) / res;
            return new Vector2(x, y);
        }

        public static bool CaptureViews(GameObject prefab, Transform lightingRoot, BillboardSettings settings)
        {
            BillboardImposter imposterAsset;
            Snapshots[] snapshots;

            //Create root
            GameObject spawnedPrefab = GameObject.Instantiate(prefab);
            Transform root = spawnedPrefab.transform;

            bool success = false;

            if (SetupRig(root, settings, out imposterAsset, out snapshots))
                success = CaptureViews(root, lightingRoot, imposterAsset, snapshots, settings);

            //Cleanup
            GameObject.DestroyImmediate(prefab);

            return false;
        }

        public static BillboardImposter CaptureViews(Transform root, Transform lightingRoot, BillboardSettings settings)
        {
            BillboardImposter imposterAsset;
            Snapshots[] snapshots;

            if (SetupRig(root, settings,out imposterAsset, out snapshots))
                if(CaptureViews(root, lightingRoot,imposterAsset, snapshots, settings))
                    return imposterAsset;

            //Failure
            return null;
        }

        private static bool CaptureViews(Transform root, Transform lightingRoot, BillboardImposter imposter, Snapshots[] snapshots,BillboardSettings settings)
        {
            Vector3 originalScale = root.localScale;

            //reset root local scale
            root.localScale = Vector3.one;

            var prevRt = RenderTexture.active;

            ///////////////// create the atlas for base and pack

            //base target
            var baseAtlas = RenderTexture.GetTemporary(settings.atlasResolution, settings.atlasResolution, 0, RenderTextureFormat.ARGB32,
                RenderTextureReadWrite.Linear);
            baseAtlas.enableRandomWrite = true;
            baseAtlas.Create();

            //world normal target
            var packAtlas = RenderTexture.GetTemporary(settings.atlasResolution, settings.atlasResolution, 0, RenderTextureFormat.ARGB32,
                RenderTextureReadWrite.Linear);
            packAtlas.enableRandomWrite = true;
            packAtlas.Create();
            //temp
            var tempAtlas = RenderTexture.GetTemporary(baseAtlas.descriptor);
            tempAtlas.Create();

            ////////////// create the single frame RT for base and pack

            var frameReso = settings.atlasResolution / imposter.Frames;

            //base frame (multiple frames make up target)
            var frame = RenderTexture.GetTemporary(frameReso, frameReso, 32, RenderTextureFormat.ARGB32,
                RenderTextureReadWrite.Linear);
            frame.enableRandomWrite = true;
            frame.Create();

            //world normal frame        
            var packFrame = RenderTexture.GetTemporary(frameReso, frameReso, 32, RenderTextureFormat.ARGB32,
                RenderTextureReadWrite.Linear);
            packFrame.Create();

            //temp
            var tempFrame = RenderTexture.GetTemporary(frame.descriptor);
            tempFrame.Create();

            //high-res frame, intended for super sampling
            //TODO proper super sampling
            //upscale 4 times
            var frameResUpscale = frameReso * 4;
            var superSizedFrame = RenderTexture.GetTemporary(frameResUpscale, frameResUpscale, 32, RenderTextureFormat.ARGB32,
                RenderTextureReadWrite.Linear);
            superSizedFrame.enableRandomWrite = true;
            superSizedFrame.Create();
            //temp
            var superSizedFrameTemp = RenderTexture.GetTemporary(superSizedFrame.descriptor);

            var superSizedAlphaMask = RenderTexture.GetTemporary(superSizedFrame.descriptor);
            superSizedAlphaMask.Create();

            //////////// create the Texture2D used for writing final image
            imposter.BaseTexture = new Texture2D(baseAtlas.width, baseAtlas.height, TextureFormat.ARGB32, true, true);
            imposter.PackTexture = new Texture2D(baseAtlas.width, baseAtlas.height, TextureFormat.ARGB32, true, true);

            //compute buffer for distance alpha
            ComputeBuffer minDistancesBuffer = new ComputeBuffer(frame.width * frame.height, sizeof(float));
            ComputeBuffer maxDistanceBuffer = new ComputeBuffer(1, sizeof(float));

            const int layer = 30;

            var clearColor = Color.clear;

            //create camera
            var camera = new GameObject().AddComponent<Camera>();
            camera.gameObject.hideFlags = HideFlags.DontSave;
            camera.cullingMask = 1 << layer;
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = clearColor;
            camera.orthographic = true;
            camera.nearClipPlane = 0f;
            camera.farClipPlane = imposter.Radius * 2f;
            camera.orthographicSize = imposter.Radius;
            camera.allowMSAA = false;
            camera.enabled = false;

            var frameCount = imposter.Frames * imposter.Frames;

            //set and store original layer to restore afterwards
            var originalLayers = new Dictionary<GameObject, int>();
            StoreLayers(root, layer, ref originalLayers);

            var originalLights = new Dictionary<Light, bool>();
            var customLit = lightingRoot != null;
            //custom lit renders with lighting into base RGB
            if (customLit)
            {
                //toggle all lights off except for lighting rig
                var lights = UnityEngine.Object.FindObjectsOfType<Light>();
                for (var i = 0; i < lights.Length; i++)
                {
                    //not part of lighting rig
                    if (!lights[i].transform.IsChildOf(lightingRoot))
                    {
                        if (originalLights.ContainsKey(lights[i])) continue;
                        //store original state
                        originalLights.Add(lights[i], lights[i].enabled);
                        //toggle it off
                        lights[i].enabled = false;
                    }
                    else
                    {
                        //is part of lighting rig
                        lights[i].enabled = true;
                        //store state as off
                        if (!originalLights.ContainsKey(lights[i]))
                            originalLights.Add(lights[i], false);
                    }
                }
            }

            //first render solid color replacement, checking for filled pixels
            //this decides if the camera can be cropped in closer to maximize atlas usage
            var tempMinMaxRT = RenderTexture.GetTemporary(frame.width, frame.height, 0, RenderTextureFormat.ARGB32);
            tempMinMaxRT.Create();

            Graphics.SetRenderTarget(tempMinMaxRT);
            GL.Clear(true, true, Color.clear);

            camera.clearFlags = CameraClearFlags.Nothing;
            camera.backgroundColor = clearColor;
            camera.targetTexture = tempMinMaxRT;

            var min = Vector2.one * frame.width;
            var max = Vector2.zero;

            for (var i = 0; i < frameCount; i++)
            {
                if (i > snapshots.Length - 1)
                {
                    Debug.LogError("[IMP] snapshot data length less than frame count! this shouldn't happen!");
                    continue;
                }

                //position camera with the current snapshot info
                var snap = snapshots[i];
                camera.transform.position = snap.Position;
                camera.transform.rotation = Quaternion.LookRotation(snap.Ray, Vector3.up);

                //render alpha only
                Shader.SetGlobalFloat("_ImposterRenderAlpha", 1f);
                camera.RenderWithShader(settings.albedoBake, "");
                camera.ResetReplacementShader();

                //render without clearing (accumulating filled pixels)
                camera.Render();

                //supply the root position taken into camera space
                //this is for the min max, in the case root is further from opaque pixels
                var viewPos = camera.WorldToViewportPoint(root.position);
                var texPos = new Vector2(viewPos.x, viewPos.y) * frame.width;
                texPos.x = Mathf.Clamp(texPos.x, 0f, frame.width);
                texPos.y = Mathf.Clamp(texPos.y, 0f, frame.width);
                min.x = Mathf.Min(min.x, texPos.x);
                min.y = Mathf.Min(min.y, texPos.y);
                max.x = Mathf.Max(max.x, texPos.x);
                max.y = Mathf.Max(max.y, texPos.y);
            }

            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = clearColor;
            camera.targetTexture = null;

            //now read render texture
            var tempMinMaxTex = new Texture2D(tempMinMaxRT.width, tempMinMaxRT.height, TextureFormat.ARGB32, false);
            RenderTexture.active = tempMinMaxRT;
            tempMinMaxTex.ReadPixels(new Rect(0f, 0f, tempMinMaxRT.width, tempMinMaxRT.height), 0, 0);
            tempMinMaxTex.Apply();

            var tempTexC = tempMinMaxTex.GetPixels32();

            //loop pixels get min max
            for (var c = 0; c < tempTexC.Length; c++)
            {
                if (tempTexC[c].r != 0x00)
                {
                    var texPos = Get2DIndex(c, tempMinMaxRT.width);
                    min.x = Mathf.Min(min.x, texPos.x);
                    min.y = Mathf.Min(min.y, texPos.y);
                    max.x = Mathf.Max(max.x, texPos.x);
                    max.y = Mathf.Max(max.y, texPos.y);
                }
            }

            UnityEngine.Object.DestroyImmediate(tempMinMaxTex, true);
            RenderTexture.ReleaseTemporary(tempMinMaxRT);

            //rescale radius
            var len = new Vector2(max.x - min.x, max.y - min.y);

            ////add 2 pixels to x and y
            //len.x += 2f;
            //len.y += 2f;
            var maxR = Mathf.Max(len.x, len.y);

            var ratio = maxR / frame.width; //assume square

            //adjust ratio (if clipping is too tight)
            //ratio = Mathf.Lerp(1f, ratio, _pixelCrop);

            imposter.Radius = imposter.Radius * ratio;
            //adjust the camera size and far clip
            camera.farClipPlane = imposter.Radius * 2f;
            camera.orthographicSize = imposter.Radius;

            //use a scale factor to make sure the offset is in the correct location
            //this is related to scaling the asset to 1,1,1 while baking, to ensure imposter matches all types of asset scaling
            Vector3 scaleFactor = new Vector3(root.localScale.x / originalScale.x, root.localScale.y / originalScale.y, root.localScale.z / originalScale.z);
            imposter.Offset = Vector3.Scale(imposter.Offset, scaleFactor);

            //recalculate snapshots
            snapshots = UpdateSnapshots(imposter.Frames, imposter.Radius, root.position + imposter.Offset, imposter.IsHalf);

            ///////////////////// rendering the actual frames 

            for (var frameIndex = 0; frameIndex < frameCount; frameIndex++)
            {
                if (frameIndex > snapshots.Length - 1)
                {
                    Debug.LogError("[IMP] snapshot data length less than frame count! this shouldn't happen!");
                    continue;
                }

                var snap = snapshots[frameIndex];
                camera.transform.position = snap.Position;
                camera.transform.rotation = Quaternion.LookRotation(snap.Ray, Vector3.up);
                clearColor = Color.clear;

                //target and clear base frame
                Graphics.SetRenderTarget(superSizedFrame);
                GL.Clear(true, true, clearColor);

                Graphics.SetRenderTarget(superSizedFrameTemp);
                GL.Clear(true, true, clearColor);

                //render into temp
                camera.targetTexture = superSizedFrameTemp;
                camera.backgroundColor = clearColor;

                if (!customLit)
                {
                    Shader.SetGlobalFloat("_ImposterRenderAlpha", 0f);
                    camera.RenderWithShader(settings.albedoBake, "");
                    camera.ResetReplacementShader();
                }
                else
                {
                    //render without replacement
                    camera.Render();
                }

                camera.targetTexture = superSizedAlphaMask;
                camera.backgroundColor = clearColor;
                camera.Render();

                //solidify alpha (uses step) //TODO probably dont need this anymore 
                Graphics.Blit(superSizedAlphaMask, superSizedFrame, settings.processingMat, 3);
                Graphics.Blit(superSizedFrame, superSizedAlphaMask);

                //combine RGB and ALPHA
                settings.processingMat.SetTexture("_MainTex", superSizedFrameTemp);
                settings.processingMat.SetTexture("_MainTex2", superSizedAlphaMask);
                settings.processingMat.SetFloat("_Step", 1f);

                //result in frameUp
                Graphics.Blit(superSizedFrameTemp, superSizedFrame, settings.processingMat, 1);

                //target frame and clear, TODO proper sampling
                Graphics.SetRenderTarget(frame);
                GL.Clear(true, true, clearColor);
                Graphics.Blit(superSizedFrame, frame);

                //clear superSized frames for use with normals + depth
                Graphics.SetRenderTarget(superSizedFrameTemp);
                GL.Clear(true, true, clearColor);
                Graphics.SetRenderTarget(superSizedFrame);
                GL.Clear(true, true, clearColor);

                //render normals & depth
                //camera background half gray (helps with height displacement)
                clearColor = new Color(0.0f, 0.0f, 0.0f, 0.5f);
                camera.targetTexture = superSizedFrame;
                camera.backgroundColor = clearColor;
                camera.RenderWithShader(settings.normalBake, "");
                camera.ResetReplacementShader();

                //clear the pack frame and write TODO proper sampling
                Graphics.SetRenderTarget(packFrame);
                GL.Clear(true, true, clearColor);
                Graphics.Blit(superSizedFrame, packFrame);
                
                //////////// perform processing on frames

                //pack frame is done first so alpha of base frame can be used as a mask (before distance alpha process)
                Graphics.SetRenderTarget(tempFrame);
                GL.Clear(true, true, Color.clear);

                //padding / dilate TODO can be improved?
                int threadsX, threadsY, threadsZ;
                CalcWorkSize(packFrame.width * packFrame.height, out threadsX, out threadsY, out threadsZ);

                if(settings.processCompute == null)
                {
                    Debug.Log("Null compute");
                    return false;
                }

                settings.processCompute.SetTexture(0, "Source", packFrame);
                settings.processCompute.SetTexture(0, "SourceMask", frame);
                settings.processCompute.SetTexture(0, "Result", tempFrame);
                settings.processCompute.SetBool("AllChannels", true);
                settings.processCompute.SetBool("NormalsDepth", true);
                settings.processCompute.Dispatch(0, threadsX, threadsY, threadsZ);

                Graphics.Blit(tempFrame, packFrame);

                //Perform processing on base atlas, Albedo + alpha (alpha is modified)
                Graphics.SetRenderTarget(tempFrame);
                GL.Clear(true, true, Color.clear);

                //padding / dilate
                CalcWorkSize(frame.width * frame.height, out threadsX, out threadsY, out threadsZ);
                settings.processCompute.SetTexture(0, "Source", frame);
                settings.processCompute.SetTexture(0, "SourceMask", frame);
                settings.processCompute.SetTexture(0, "Result", tempFrame);
                settings.processCompute.SetBool("AllChannels", false);
                settings.processCompute.SetBool("NormalsDepth", false);
                settings.processCompute.Dispatch(0, threadsX, threadsY, threadsZ);

                Graphics.Blit(tempFrame, frame);

                Graphics.SetRenderTarget(tempFrame);
                GL.Clear(true, true, Color.clear);

                //distance field alpha
                //step 1 store min distance to unfilled alpha
                CalcWorkSize(frame.width * frame.height, out threadsX, out threadsY, out threadsZ);
                settings.processCompute.SetTexture(1, "Source", frame);
                settings.processCompute.SetTexture(1, "SourceMask", frame);
                settings.processCompute.SetBuffer(1, "MinDistances", minDistancesBuffer);
                settings.processCompute.Dispatch(1, threadsX, threadsY, threadsZ);

                //step 2 write maximum of the min distances to MaxDistanceBuffer[0]
                //also reset the min distances to 0 during this kernel
                settings.processCompute.SetInt("MinDistancesLength", minDistancesBuffer.count);
                settings.processCompute.SetBuffer(2, "MaxOfMinDistances", maxDistanceBuffer);
                settings.processCompute.SetBuffer(2, "MinDistances", minDistancesBuffer);
                settings.processCompute.Dispatch(2, 1, 1, 1);

                //step 3 write min distance / max of min to temp frame
                CalcWorkSize(frame.width * frame.height, out threadsX, out threadsY, out threadsZ);
                settings.processCompute.SetTexture(3, "Source", frame);
                settings.processCompute.SetTexture(3, "SourceMask", frame);
                settings.processCompute.SetTexture(3, "Result", tempFrame);
                settings.processCompute.SetBuffer(3, "MinDistances", minDistancesBuffer);
                settings.processCompute.SetBuffer(3, "MaxOfMinDistances", maxDistanceBuffer);
                settings.processCompute.Dispatch(3, threadsX, threadsY, threadsZ);

                Graphics.Blit(tempFrame, frame);

                //convert 1D index to flattened octahedra coordinate
                int x;
                int y;
                //this is 0-(frames-1) ex, 0-(12-1) 0-11 (for 12 x 12 frames)
                XYFromIndex(frameIndex, imposter.Frames, out x, out y);

                //X Y position to write frame into atlas
                //this would be frame index * frame width, ex 2048/12 = 170.6 = 170
                //so 12 * 170 = 2040, loses 8 pixels on the right side of atlas and top of atlas

                x *= frame.width;
                y *= frame.height;

                //copy base frame into base render target
                Graphics.CopyTexture(frame, 0, 0, 0, 0, frame.width, frame.height, baseAtlas, 0, 0, x, y);

                //copy normals frame into normals render target
                Graphics.CopyTexture(packFrame, 0, 0, 0, 0, packFrame.width, packFrame.height, packAtlas, 0, 0, x, y);
            }

            //read render target pixels
            Graphics.SetRenderTarget(packAtlas);
            imposter.PackTexture.ReadPixels(new Rect(0f, 0f, packAtlas.width, packAtlas.height), 0, 0);

            Graphics.SetRenderTarget(baseAtlas);
            imposter.BaseTexture.ReadPixels(new Rect(0f, 0f, baseAtlas.width, baseAtlas.height), 0, 0);

            //restore previous render target
            RenderTexture.active = prevRt;

            baseAtlas.Release();
            frame.Release();
            packAtlas.Release();
            packFrame.Release();

            RenderTexture.ReleaseTemporary(baseAtlas);
            RenderTexture.ReleaseTemporary(packAtlas);
            RenderTexture.ReleaseTemporary(tempAtlas);

            RenderTexture.ReleaseTemporary(frame);
            RenderTexture.ReleaseTemporary(packFrame);
            RenderTexture.ReleaseTemporary(tempFrame);

            RenderTexture.ReleaseTemporary(superSizedFrame);
            RenderTexture.ReleaseTemporary(superSizedAlphaMask);
            RenderTexture.ReleaseTemporary(superSizedFrameTemp);

            minDistancesBuffer.Dispose();
            maxDistanceBuffer.Dispose();

            UnityEngine.Object.DestroyImmediate(camera.gameObject, true);

            //restore layers
            RestoreLayers(originalLayers);

            //restore lights
            var enumerator2 = originalLights.Keys.GetEnumerator();
            while (enumerator2.MoveNext())
            {
                var light = enumerator2.Current;
                if (light != null) light.enabled = originalLights[light];
            }

            enumerator2.Dispose();
            originalLights.Clear();

            return true;
        }

        //Save an asset automatically, by either saving alongside the owning prefab,
        //or asking where to save
        public static void SaveAsset(BillboardImposter imposter, BillboardSettings settings,bool savePrefab=true)
        {
            string assetPath = "";
            string assetName = "";
            if (imposter.AssetReference != null)
            {
                assetPath = AssetDatabase.GetAssetPath(imposter.AssetReference);
                var lastSlash = assetPath.LastIndexOf("/", StringComparison.Ordinal);
                var folder = assetPath.Substring(0, lastSlash);
                assetName = assetPath.Substring(lastSlash + 1,
                    assetPath.LastIndexOf(".", StringComparison.Ordinal) - lastSlash - 1);

                assetPath = folder + "/" + assetName + "_Imposter" + ".asset";
            }
            else //no prefab, ask where to save
            {
                assetName = imposter.AssetReference.name;
                assetPath = EditorUtility.SaveFilePanelInProject("Save Billboard Imposter", assetName + "_Imposter", "asset",
                    "Select save location");
            }

            SaveAsset(assetPath, assetName, savePrefab, imposter, settings);
        }

        //Save an asset to a path
        public static void SaveAsset(string assetPath, string assetName, bool savePrefab,BillboardImposter imposter,BillboardSettings settings)
        {
            imposter.PrefabSuffix = settings.suffix;
            imposter.name = assetName;

            AssetDatabase.CreateAsset(imposter, assetPath);

            imposter.Save(assetPath, assetName, settings.createUnityBillboard);

            if(savePrefab)
            {
                imposter.CreatePrefab(true, assetName);
            }
        }

        //dumb, use draw procedural
        private static void DrawQuad()
        {
            GL.PushMatrix();
            GL.LoadOrtho();
            GL.Begin(GL.QUADS);
            GL.TexCoord2(0.0f, 0.0f);
            GL.Vertex3(-1.0f, -1.0f, 0.0f);
            GL.TexCoord2(1.0f, 0.0f);
            GL.Vertex3(-1.0f, 1.0f, 0.0f);
            GL.TexCoord2(1.0f, 1.0f);
            GL.Vertex3(1.0f, 1.0f, 0.0f);
            GL.TexCoord2(0.0f, 1.0f);
            GL.Vertex3(1.0f, -1.0f, 0.0f);
            GL.End();
            GL.PopMatrix();
        }

        private static void StoreLayers(Transform root, int layer, ref Dictionary<GameObject, int> store)
        {
            //store existing layer
            store.Add(root.gameObject, root.gameObject.layer);
            //set new layer
            root.gameObject.layer = layer;
            for (var i = 0; i < root.childCount; i++)
            {
                var t = root.GetChild(i);
                StoreLayers(t, layer, ref store);
            }
        }

        private static void RestoreLayers(Dictionary<GameObject, int> store)
        {
            var enumerator = store.Keys.GetEnumerator();
            while (enumerator.MoveNext())
                if (enumerator.Current != null)
                    enumerator.Current.layer = store[enumerator.Current];

            enumerator.Dispose();
            store.Clear();
        }

        private static Vector3 OctahedralCoordToVectorHemisphere(Vector2 coord)
        {
            coord = new Vector2(coord.x + coord.y, coord.x - coord.y) * 0.5f;
            var vec = new Vector3(
                coord.x,
                1.0f - Vector2.Dot(Vector2.one,
                    new Vector2(Mathf.Abs(coord.x), Mathf.Abs(coord.y))
                ),
                coord.y
            );
            return Vector3.Normalize(vec);
        }

        private static Vector3 OctahedralCoordToVector(Vector2 f)
        {
            var n = new Vector3(f.x, 1f - Mathf.Abs(f.x) - Mathf.Abs(f.y), f.y);
            var t = Mathf.Clamp01(-n.y);
            n.x += n.x >= 0f ? -t : t;
            n.z += n.z >= 0f ? -t : t;
            return n;
        }

        private static void XYFromIndex(int index, int dims, out int x, out int y)
        {
            x = index % dims;
            y = (index - x) / dims;
        }

        private static Mesh CreateOctahedron(int frames, float radius = 1f, bool isHalf = true)
        {
            var verts = frames + 1;
            var lenVerts = verts * verts;
            var lenFrames = frames * frames;

            var vertices = new Vector3[lenVerts];
            var normals = new Vector3[lenVerts];
            var uvs = new Vector2[lenVerts];

            //indices is number of frames * 2 * 3  (a frame is a quad, two triangles to quad, 3 verts per triangle)
            var indices = new int[lenFrames * 2 * 3];

            for (var i = 0; i < lenVerts; i++)
            {
                int x;
                int y;

                XYFromIndex(i, verts, out x, out y);
                //0 to 1
                var vec = new Vector2(x / (float)frames, y / (float)frames);
                //-1 to 1
                var vecSigned = new Vector2(vec.x * 2f - 1f, vec.y * 2f - 1f);

                //use as UV
                uvs[i] = vec;

                var vertex = isHalf ? OctahedralCoordToVectorHemisphere(vecSigned) : OctahedralCoordToVector(vecSigned);

                //normalize
                normals[i] = vertex.normalized;

                //based radius
                vertices[i] = normals[i] * radius;
            }

            //indices follow a pattern, 
            //XY same sign or different sign determines which indice pattern
            //there are 4 quadrants:
            //
            // -1,+1|+1,+1
            // -----|-----
            // -1,-1|+1,-1

            // full  half
            //  /\    \/
            //  \/    /\

            for (var i = 0; i < indices.Length / 6; i++)
            {
                int x;
                int y;

                XYFromIndex(i, frames, out x, out y);

                var corner = x + y * verts;
                var v0 = corner;
                var v1 = corner + verts;
                var v2 = corner + 1;
                var v3 = corner + 1 + verts;

                //use UV coords here as they are flat 0-1
                var vec = uvs[corner];
                //-1 to 1 space
                vec = new Vector2(vec.x * 2f - 1f, vec.y * 2f - 1f);
                var sameSign = Mathf.Abs(Mathf.Sign(vec.x) - Mathf.Sign(vec.y)) < Mathf.Epsilon;

                //flip pattern if half octahedron
                if (isHalf) sameSign = !sameSign;

                if (sameSign)
                {
                    // LL / UR
                    // 1---3
                    // | \ |
                    // 0---2
                    indices[i * 6 + 0] = v0;
                    indices[i * 6 + 1] = v1;
                    indices[i * 6 + 2] = v2;
                    indices[i * 6 + 3] = v2;
                    indices[i * 6 + 4] = v1;
                    indices[i * 6 + 5] = v3;
                }
                else
                {
                    // UL / LR
                    // 1---3
                    // | / |
                    // 0---2
                    indices[i * 6 + 0] = v2;
                    indices[i * 6 + 1] = v0;
                    indices[i * 6 + 2] = v3;
                    indices[i * 6 + 3] = v3;
                    indices[i * 6 + 4] = v0;
                    indices[i * 6 + 5] = v1;
                }
            }

            var mesh = new Mesh
            {
                vertices = vertices,
                normals = normals,
                uv = uvs
            };
            mesh.SetTriangles(indices, 0);
            return mesh;
        }

        private struct Snapshots
        {
            public Vector3 Position;
            public Vector3 Ray;
        }

        public class BillboardSettings
        {
            //Settings
            public string suffix;
            public int frames;
            public int atlasResolution;
            public bool isHalf;
            public bool createUnityBillboard;

            public ComputeShader processCompute;
            
            //Generated values
            public Shader albedoBake;
            public Shader normalBake;
            public Material processingMat;

            public void SetupDefaultShaders()
            {
                if (processingMat == null)
                    processingMat = new Material(Shader.Find("Hidden/XRA/IMP/ImposterProcessing"));

                if (normalBake == null)
                    normalBake = Shader.Find("Hidden/XRA/IMP/ImposterBakeWorldNormalDepth");

                if (albedoBake == null)
                    albedoBake = Shader.Find("Hidden/XRA/IMP/ImposterBakeAlbedo");
                
            }
        }

        private const int GROUP_SIZE = 256;
        private const int MAX_DIM_GROUPS = 1024;
        private const int MAX_DIM_THREADS = (GROUP_SIZE * MAX_DIM_GROUPS);

        private static void CalcWorkSize(int length, out int x, out int y, out int z)
        {
            if (length <= MAX_DIM_THREADS)
            {
                x = (length - 1) / GROUP_SIZE + 1;
                y = z = 1;
            }
            else
            {
                x = MAX_DIM_GROUPS;
                y = (length - 1) / MAX_DIM_THREADS + 1;
                z = 1;
            }
        }
    }

}
