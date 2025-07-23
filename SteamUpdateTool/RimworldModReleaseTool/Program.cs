using System;
using System.IO;
using System.Reflection;

namespace RimworldModReleaseTool
{
    internal class Program
    {
        public static void Main(string[] args)
        {
            Console.ForegroundColor = ConsoleColor.Gray;
            InitializeProgram();
            if (args.Length < 1 || args.Length > 3)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("You must at least specify the path to the mod-folder.");
                Console.ForegroundColor = ConsoleColor.White;
                return;
            }

            var modFolderPath = args[0];
            if (!Directory.Exists(modFolderPath))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"{modFolderPath} not found");
                Console.ForegroundColor = ConsoleColor.White;
                return;
            }

            var imageFolderPath = string.Empty;
            if (args.Length > 1)
            {
                imageFolderPath = args[1];
                if (!Directory.Exists(imageFolderPath))
                {
                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine($"{imageFolderPath} not found");
                    Console.ForegroundColor = ConsoleColor.White;
                    return;
                }
            }

            var confirm = args.Length > 2;
            var skipConfirm = false;
            if (confirm)
            {
                skipConfirm = args[2].ToLower() == "false";
            }

            var updateInfo = new ModUpdateInfo(modFolderPath);

            SteamUpdateRequest(updateInfo, modFolderPath, imageFolderPath, confirm, skipConfirm);
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
            bool confirm, bool skipConfirm)
        {
            try
            {
                var mod = new Mod(modRootPath, imageFolderPath)
                {
                    SkipConfirm = skipConfirm
                };
                SteamUtility.Init();
                Console.WriteLine(mod.ToString());
                Console.WriteLine($"Latest changenote: {updateInfo.LatestChangeNote}");
                if (confirm && !skipConfirm)
                {
                    Console.WriteLine("Continue?");
                    Console.ReadLine();
                }

                if (!SteamUtility.Upload(mod, updateInfo.LatestChangeNote))
                {
                    return;
                }

                Console.ForegroundColor = ConsoleColor.DarkGreen;
                Console.WriteLine("Upload done");
            }
            catch (Exception e)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(e.Message);
            }
            finally
            {
                Console.ForegroundColor = ConsoleColor.White;
                SteamUtility.Shutdown();
            }
        }
    }
}