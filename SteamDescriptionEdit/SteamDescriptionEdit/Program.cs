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
        private const uint rimworldId = 294100;
        private static uint workshopId;
        private static Item workshopItem;

        private static async Task Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("No workshop-id defined.");
                return;
            }

            try
            {
                workshopId = Convert.ToUInt32(args[0]);
            }
            catch (Exception)
            {
                Console.WriteLine($"{args[0]} is not a valid workshopId");
                return;
            }

            try
            {
                SteamClient.Init(rimworldId);
                //Console.WriteLine($"Initiated steam-client.");
            }
            catch (Exception exception)
            {
                Console.WriteLine($"Could not connect to steam.\n{exception}");
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
                Console.WriteLine($"Missing parameters for operation {operation}");
                Console.SetOut(TextWriter.Null);
                SteamClient.Shutdown();
                return;
            }

            var validOperations = new List<string> { "REPLACE", "SET", "SYNC", "SAVE", "GET", "UPDATE" };
            if (!validOperations.Contains(operation))
            {
                Console.WriteLine(
                    $"{operation} is not a valid operation. \nValid values are: {string.Join(",", validOperations)}");
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
                        Console.WriteLine($"{operation} demands two arguments, a searchstring and a replacestring.");
                        Console.SetOut(TextWriter.Null);
                        SteamClient.Shutdown();
                        return;
                    }

                    var searchString = args[2];
                    var replaceString = args[3];
                    await LoadModInfoAsync();
                    if (!workshopItem.Description.Contains(searchString))
                    {
                        Console.WriteLine(
                            $"{workshopItem.Title} description does not contain {searchString}, skipping update");
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
                        Console.WriteLine($"{operation} demands one argument, the file containing the description");
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
                        Console.WriteLine($"{operation} demands one argument, REMOTE or LOCAL");
                        Console.SetOut(TextWriter.Null);
                        return;
                    }

                    await LoadModInfoAsync();


                    Console.WriteLine($"{operation} not implemented yet");
                    break;
                case "SAVE":
                    if (args.Length != 3)
                    {
                        Console.WriteLine($"{operation} demands one argument, the path to the local file to save to");
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
                        Console.WriteLine(
                            $"{operation} demands two arguments, AUTHOR as the first, path to file as the second");
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
                        Console.WriteLine(
                            $"{operation} demands two arguments, PREVIEW as the first, path to file as the second");
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
            workshopItem = (Item)await Item.GetAsync(workshopId);
        }

        private static async Task SetModDescriptionAsync(string description)
        {
            var result = await new Editor(workshopId).WithDescription(description).SubmitAsync();

            Console.WriteLine(result.Success
                ? $"Description of {workshopItem.Title} updated"
                : $"Failed to update description of {workshopItem.Title}");
        }

        private static async Task SetModPreviewAsync(string previewFile)
        {
            var result = await new Editor(workshopId).WithPreviewFile(previewFile).SubmitAsync();

            Console.WriteLine(result.Success
                ? $"Preview of {workshopItem.Title} updated"
                : $"Failed to update preview of {workshopItem.Title}");
        }
    }
}