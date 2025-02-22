using System;
using System.Reflection;
using System.Text.RegularExpressions;

namespace SteamCollectionManager
{
    internal class Program
    {
        public static void Main(string[] args)
        {
            InitializeProgram();
            if (args.Length != 2 && args.Length != 3)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(
                    "First parameter is the id of the mod to sub/unsub, second should be 'True' or 'False' depending on the action. Optional third is no verification of subscription (True)");
                return;
            }

            var modId = args[0];
            if (!Regex.IsMatch(modId, @"^\d+$"))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Mod id {modId} is not numeric");
                return;
            }

            var actionToTake = args[1].ToLower();
            if (actionToTake != "true" && actionToTake != "false")
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(
                    $"Second parameter {actionToTake} is not true/false.");
                return;
            }

            var fast = args.Length == 3;

            var subscribe = actionToTake == "true";

            Console.ForegroundColor = ConsoleColor.White;
            Console.WriteLine(subscribe ? $"Will subscribe to modId {modId}" : $"Will unsubscribe to modId {modId}");

            Console.ForegroundColor = ConsoleColor.Gray;

            SteamUtility.SetSubscription(modId, subscribe, fast);
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
                    stream.Read(assemblyData, 0, assemblyData.Length);
                    return Assembly.Load(assemblyData);
                }
            };
        }
    }
}