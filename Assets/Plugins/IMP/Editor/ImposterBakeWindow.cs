using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace IMP
{
    public class ImposterBakeWindow : EditorWindow
    {
        private static string _suffix = "IMP"; //when creating prefabs

        private static int _atlasResolution = 2048;

        private static readonly string[] ResNames = { "1024", "2048", "4096", "8192" };
        private static readonly int[] ResSizes = { 1024, 2048, 4096, 8192 };

        private static int _frames = 12;
        private static bool _isHalf = true;
        //private static float _pixelCrop = 1f; //0f no extra cropping, 1f full pixel cropping
        private static Transform _lightingRig; //root of lighting rig if used
        private static Transform _root;
        private static readonly List<Transform> Roots = new List<Transform>();
        private static Material _processingMat;

        private static bool _createUnityBillboard = false; //attempt at Unity BillboardAsset and BillboardRenderer support

        private Mesh _cameraRig;
        private BillboardImposter _imposterAsset;
        private Vector3 _origin;
        
        //private static GUIContent _labelResolution = new GUIContent("Resolution", "Resolution of the Imposter Atlas");
        private static GUIContent _labelFrames = new GUIContent("Frames", "Too many frames = low texel density, Too few frames = distortion");
        private static GUIContent _labelHemisphere = new GUIContent("Hemisphere", "Full Sphere or Hemisphere capture, sphere is useful for objects seen at all angles");
        private static GUIContent _labelCustomLighting = new GUIContent("Custom Lighting Root", "transform of custom light rig, lit object rendered in place of albedo");
        private static GUIContent _labelSuffix = new GUIContent("Prefab Suffix", "Appended to Imposter Prefab(s), useful for LOD naming");
        private static GUIContent _labelUnityBillboard = new GUIContent("Create Unity Billboard", "Creates additional Unity Billboard Renderer Asset (WIP)");
        private static GUIContent _labelPreviewSnapshot = new GUIContent("Preview Snapshot Locations", "Draw rays showing camera positions");

        [MenuItem("Window/IMP", priority = 9000)]
        public static void ShowWindow()
        {
            GetWindow<ImposterBakeWindow>("Imposter Baker");
        }

        private static bool IsEven(int n)
        {
            return n % 2 == 0;
        }

        private IMPGenerator.BillboardSettings BuildSettings()
        {
            IMPGenerator.BillboardSettings settings = new IMPGenerator.BillboardSettings();
            settings.SetupDefaultShaders();
            settings.atlasResolution = _atlasResolution;
            settings.createUnityBillboard = _createUnityBillboard;
            settings.frames = _frames;
            settings.isHalf = _isHalf;
            settings.processingMat = _processingMat;
 
            settings.suffix = _suffix;

            return settings;
        }
        

        private void OnGUI()
        {
            try
            {
                Draw();
            }
            catch (Exception e)
            {
                Debug.LogException(e);
            }
        }

        private void Draw()
        {
            if (_processingMat == null)
            {
                Shader shader = Shader.Find("Hidden/XRA/IMP/ImposterProcessing");
                if (shader != null)
                {
                    _processingMat = new Material(shader);
                }
                else
                {
                    Debug.LogError("Imposter Baker Material NULL!");
                }
            }
            var noSelection = Selection.activeTransform == null;

            EditorGUI.BeginChangeCheck(); //check for settings change

            _atlasResolution = EditorGUILayout.IntPopup("Resolution", _atlasResolution, ResNames, ResSizes);

            _frames = EditorGUILayout.IntField(_labelFrames, Mathf.Clamp(_frames, 4, 32));

            if (!IsEven(_frames)) _frames -= 1;

            //min is 2 x 2
            _frames = Mathf.Max(2, _frames);

            //pixel crop not needed, extra 2 pixels added to X Y, border of frames cleared to black
            //_pixelCrop = EditorGUILayout.Slider("PixelCrop", _pixelCrop, 0f, 1f);
            //_pixelCrop = Mathf.Clamp01(_pixelCrop);

            _isHalf = EditorGUILayout.Toggle(_labelHemisphere, _isHalf);

            EditorGUILayout.LabelField(_labelCustomLighting);
            _lightingRig = (Transform)EditorGUILayout.ObjectField(_lightingRig, typeof(Transform), true);

            var settingsChanged = EditorGUI.EndChangeCheck(); //end check

            EditorGUILayout.LabelField(_labelSuffix);
            _suffix = EditorGUILayout.TextField(_suffix);

            _createUnityBillboard = EditorGUILayout.Toggle(_labelUnityBillboard, _createUnityBillboard);

            //if selection changed, or settings were changed, rig is no longer ready for capture
            if (_root != Selection.activeTransform || settingsChanged) Roots.Clear();

            _root = Selection.activeTransform;

            if (noSelection) return;

            if (GUILayout.Button(_labelPreviewSnapshot))
            {
                IMPGenerator.DebugSnapshots(_root, BuildSettings());
            }

            if (Selection.gameObjects != null && Selection.gameObjects.Length > 1 &&
                Selection.gameObjects.Length != Roots.Count)
            {
                for (var i = 0; i < Selection.gameObjects.Length; i++)
                {
                    if (Selection.gameObjects[i].transform.parent == null)
                        Roots.Add(Selection.gameObjects[i].transform);
                }
            }

            if (Roots.Count > 1)
            {
                if (GUILayout.Button("Capture Multiple"))
                {
                    for (var i = 0; i < Roots.Count; i++)
                    {
                        EditorUtility.DisplayProgressBar("Capturing", "Capturing " + Roots[i].name,
                            (i + 1f) / Roots.Count);

                        IMPGenerator.BillboardSettings settings = BuildSettings();

                        BillboardImposter imposter = IMPGenerator.CaptureViews(Roots[i], _lightingRig, settings);
                        if (imposter != null)
                            IMPGenerator.SaveAsset(imposter,settings);
                    }

                    EditorUtility.ClearProgressBar();
                }
            }
            else if (_root != null)
            {
                if (GUILayout.Button("Capture"))
                {
                    EditorUtility.DisplayProgressBar("Capturing", "Capturing " + _root.name, 1f);

                    IMPGenerator.BillboardSettings settings = BuildSettings();

                    BillboardImposter imposter = IMPGenerator.CaptureViews(_root, _lightingRig, settings);
                    if (imposter != null)
                        IMPGenerator.SaveAsset(imposter, settings);

                    EditorUtility.ClearProgressBar();
                }
            }
        }

    }
}
