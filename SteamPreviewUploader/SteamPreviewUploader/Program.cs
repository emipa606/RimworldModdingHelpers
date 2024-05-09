using System;
using System.Reflection;

namespace RimworldModReleaseTool
{
    internal class Program
    {
        public static void Main(string[] args)
        {
            InitializeProgram();
            if (args.Length != 3)
            {
                Console.WriteLine(
                    "You must the path to the mod-folder, the preview image to upload and the index of the image.");
                return;
            }

            var modFolderPath = args[0];
            var previewImage = args[1];

            if (!uint.TryParse(args[2], out var index))
            {
                Console.WriteLine("Could not parse the index as int.");
                return;
            }

            SteamPreviewRequest(modFolderPath, previewImage, index);
        }

        private static void InitializeProgram()
        {
            AppDomain.CurrentDomain.AssemblyResolve += (sender, args) =>
            {
                var resourceName = "AssemblyLoadingAndReflection." +
                                   new AssemblyName(args.Name).Name + ".dll";
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
                {
                    if (stream == null)
                    {
                        return null;
                    }

                    var assemblyData = new byte[stream.Length];
                    var unused = stream.Read(assemblyData, 0, assemblyData.Length);
                    return Assembly.Load(assemblyData);
                }
            };
        }

        private static void SteamPreviewRequest(string modRootPath, string imagePath, uint index)
        {
            try
            {
                var mod = new Mod(modRootPath, imagePath, index);
                SteamUtility.Init();
                Console.WriteLine(mod.ToString());

                if (SteamUtility.Upload(mod))
                {
                    Console.WriteLine("Upload done");
                }
            }
            catch (Exception e)
            {
                Console.WriteLine(e.Message);
            }
            finally
            {
                SteamUtility.Shutdown();
            }
        }
    }
}