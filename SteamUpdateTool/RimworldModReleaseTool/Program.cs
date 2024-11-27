using System;
using System.IO;
using System.Reflection;

namespace RimworldModReleaseTool
{
    internal class Program
    {
        public static void Main(string[] args)
        {
            InitializeProgram();
            if (args.Length < 1 || args.Length > 3)
            {
                Console.WriteLine("You must at least specify the path to the mod-folder.");
                return;
            }

            var modFolderPath = args[0];
            if (!Directory.Exists(modFolderPath))
            {
                Console.WriteLine($"{modFolderPath} not found");
                return;
            }

            var imageFolderPath = string.Empty;
            if (args.Length > 1)
            {
                imageFolderPath = args[1];
                if (!Directory.Exists(imageFolderPath))
                {
                    Console.WriteLine($"{imageFolderPath} not found");
                    return;
                }
            }

            var confirm = args.Length > 2;

            var updateInfo = new ModUpdateInfo(modFolderPath);

            SteamUpdateRequest(updateInfo, modFolderPath, imageFolderPath, confirm);
        }

        private static void InitializeProgram()
        {
            AppDomain.CurrentDomain.AssemblyResolve += (sender, args) =>
            {
                var resourceName = $"AssemblyLoadingAndReflection.{new AssemblyName(args.Name).Name}.dll";
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
                {
                    if (stream == null)
                    {
                        return null;
                    }

                    var assemblyData = new byte[stream.Length];
                    _ = stream.Read(assemblyData, 0, assemblyData.Length);
                    return Assembly.Load(assemblyData);
                }
            };
        }

        private static void SteamUpdateRequest(ModUpdateInfo updateInfo, string modRootPath, string imageFolderPath,
            bool confirm)
        {
            try
            {
                var mod = new Mod(modRootPath, imageFolderPath);
                SteamUtility.Init();
                Console.WriteLine(mod.ToString());
                Console.WriteLine($"Latest changenote: {updateInfo.LatestChangeNote}");
                if (confirm)
                {
                    Console.WriteLine("Continue?");
                    Console.ReadLine();
                }

                if (SteamUtility.Upload(mod, updateInfo.LatestChangeNote))
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