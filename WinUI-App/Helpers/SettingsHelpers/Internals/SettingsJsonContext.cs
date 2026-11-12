using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json.Serialization;

namespace WinUI_App.Helpers.SettingsHelpers.Internals
{
    [JsonSourceGenerationOptions(WriteIndented = true, GenerationMode = JsonSourceGenerationMode.Metadata)]
    [JsonSerializable(typeof(Dictionary<string, System.Text.Json.JsonElement>))]
    [JsonSerializable(typeof(SettingsHelper))]
    internal partial class SettingsJsonContext : JsonSerializerContext
    {
    }
}
