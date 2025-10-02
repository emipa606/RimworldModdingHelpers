using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Steamworks;
using Steamworks.Ugc;

namespace SteamUpdateTool
{
    internal class Program
    {
        private const uint RimworldId = 294100;
        private static uint workshopId;
        private static Item workshopItem;

        private static async Task Main(string[] args)
        {
            Console.ForegroundColor = ConsoleColor.Gray;
            if (args.Length == 0)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine("No workshop-id defined.");
                Console.ForegroundColor = ConsoleColor.White;
                return;
            }

            try
            {
                workshopId = Convert.ToUInt32(args[0]);
            }
            catch (Exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"{args[0]} is not a valid workshopId");
                Console.ForegroundColor = ConsoleColor.White;
                return;
            }

            try
            {
                SteamClient.Init(RimworldId);
            }
            catch (Exception exception)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Could not connect to steam.\n{exception}");
                Console.ForegroundColor = ConsoleColor.White;
                return;
            }

            if (args.Length == 1)
            {
                await LoadModInfoAsync();

                Console.WriteLine(workshopItem.Title);
                Console.WriteLine(workshopItem.Description);
                Console.SetOut(TextWriter.Null);
                SteamClient.Shutdown();
                return;
            }

            var operation = args[1];
            if (args.Length == 2)
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Missing parameters for operation {operation}");
                Console.ForegroundColor = ConsoleColor.White;
                Console.SetOut(TextWriter.Null);
                SteamClient.Shutdown();
                return;
            }

            var validOperations = new List<string> { "REPLACE", "SET", "SYNC", "SAVE", "GET", "UPDATE" };
            if (!validOperations.Contains(operation))
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(
                    $"{operation} is not a valid operation. \nValid values are: {string.Join(",", validOperations)}");
                Console.ForegroundColor = ConsoleColor.White;
                Console.SetOut(TextWriter.Null);
                SteamClient.Shutdown();
                return;
            }

            List<string> validArguments;
            switch (operation)
            {
                case "REPLACE":
                    if (args.Length != 4)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine($"{operation} demands two arguments, a searchstring and a replacestring.");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        SteamClient.Shutdown();
                        return;
                    }

                    var searchString = args[2];
                    var replaceString = args[3];
                    await LoadModInfoAsync();
                    if (!workshopItem.Description.Contains(searchString))
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine(
                            $"{workshopItem.Title} description does not contain {searchString}, skipping update");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        SteamClient.Shutdown();
                        return;
                    }

                    var updatedDescription = workshopItem.Description.Replace(searchString, replaceString);
                    await SetModDescriptionAsync(updatedDescription);
                    break;
                case "SET":
                    if (args.Length != 3)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine($"{operation} demands one argument, the file containing the description");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        SteamClient.Shutdown();
                        return;
                    }

                    await LoadModInfoAsync();
                    var newDescription = File.ReadAllText(args[2]);
                    await SetModDescriptionAsync(newDescription);
                    break;
                case "SYNC":
                    validArguments = new List<string> { "REMOTE", "LOCAL" };
                    if (args.Length != 3 || !validArguments.Contains(args[2]))
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine($"{operation} demands one argument, REMOTE or LOCAL");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        return;
                    }

                    await LoadModInfoAsync();


                    Console.ForegroundColor = ConsoleColor.DarkRed;
                    Console.WriteLine($"{operation} not implemented yet");
                    break;
                case "SAVE":
                    if (args.Length != 3)
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine($"{operation} demands one argument, the path to the local file to save to");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        return;
                    }

                    await LoadModInfoAsync();
                    using (var sw = File.CreateText(args[2]))
                    {
                        await sw.WriteAsync(workshopItem.Description);
                    }

                    break;
                case "GET":
                    validArguments = new List<string> { "AUTHOR" };
                    if (args.Length != 4 || !validArguments.Contains(args[2]))
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine(
                            $"{operation} demands two arguments, AUTHOR as the first, path to file as the second");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        return;
                    }

                    await LoadModInfoAsync();
                    switch (args[2])
                    {
                        case "AUTHOR":
                            using (var sw = File.CreateText(args[3]))
                            {
                                await sw.WriteAsync(workshopItem.Owner.Name);
                            }

                            break;
                    }

                    break;
                case "UPDATE":
                    validArguments = new List<string> { "PREVIEW" };
                    if (args.Length != 4 || !validArguments.Contains(args[2]))
                    {
                        Console.ForegroundColor = ConsoleColor.DarkRed;
                        Console.WriteLine(
                            $"{operation} demands two arguments, PREVIEW as the first, path to file as the second");
                        Console.ForegroundColor = ConsoleColor.White;
                        Console.SetOut(TextWriter.Null);
                        return;
                    }

                    await LoadModInfoAsync();
                    switch (args[2])
                    {
                        case "PREVIEW":
                            var newPreview = File.ReadAllText(args[2]);
                            await SetModPreviewAsync(newPreview);
                            break;
                    }

                    break;
            }

            Console.SetOut(TextWriter.Null);
            SteamClient.Shutdown();
        }

        private static async Task LoadModInfoAsync()
        {
            workshopItem = (Item)await Item.GetAsync(workshopId, 0);
        }

        private static async Task SetModDescriptionAsync(string description)
        {
            var result = await new Editor(workshopId).WithDescription(description).SubmitAsync();

            if (result.Success)
            {
                Console.ForegroundColor = ConsoleColor.DarkGreen;
                Console.WriteLine($"Description of {workshopItem.Title} updated");
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine(
                    $"Failed to update description of {workshopItem.Title} and description \n{description}\n{result.Result}");
            }

            Console.ForegroundColor = ConsoleColor.White;
        }

        private static async Task SetModPreviewAsync(string previewFile)
        {
            var result = await new Editor(workshopId).WithPreviewFile(previewFile).SubmitAsync();

            if (result.Success)
            {
                Console.ForegroundColor = ConsoleColor.DarkGreen;
                Console.WriteLine($"Preview of {workshopItem.Title} updated");
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.DarkRed;
                Console.WriteLine($"Failed to update preview of {workshopItem.Title}: {result.Result}");
            }

            Console.ForegroundColor = ConsoleColor.White;
        }
    }
}