using System;
using System.Collections.Generic;
using System.Text.Json;
using Windows.Storage;
using WinUI_App.Helpers.SettingsHelpers.Internals;

namespace WinUI_App.Helpers.SettingsHelpers.Providers
{
    internal sealed class ApplicationDataSettingsProvider : ISettingsProvider
    {
        private readonly ApplicationDataContainer localSettings;

        public ApplicationDataSettingsProvider(ApplicationDataContainer localSettings)
        {
            this.localSettings = localSettings ?? throw new ArgumentNullException(nameof(localSettings));
        }

        public bool Contains(string key) => localSettings.Values.ContainsKey(key);

        public object? Get(string key) => localSettings.Values.TryGetValue(key, out var value) ? value : null;

        public void Set(string key, object value) => localSettings.Values[key] = value;

        public T? Get<T>(string key)
        {
            if (!localSettings.Values.TryGetValue(key, out var value))
                return default;

            if (value is T t)
                return t;

            if (value is string str && !IsSimpleType(typeof(T)))
            {
                try
                {
                    var typeInfo = SettingsJsonContext.Default.GetTypeInfo(typeof(T))!;
                    return (T?)JsonSerializer.Deserialize(str, typeInfo);
                }
                catch (Exception)
                {
                    HandleCorruptedKey(key);
                    return default;
                }
            }

            return (T)Convert.ChangeType(value, typeof(T));
        }

        private void HandleCorruptedKey(string key)
        {
            try
            {
                localSettings.Values.Remove(key);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to remove corrupted key '{key}': {ex}");
            }
        }

        public void Set<T>(string key, T value)
        {
            object storedValue = IsSimpleType(typeof(T))
                ? value!
                : JsonSerializer.Serialize(value, SettingsJsonContext.Default.GetTypeInfo(typeof(T))!);

            localSettings.Values[key] = storedValue;
        }

        private static readonly HashSet<Type> ExtraSimpleTypes = new()
    {
        typeof(string),
        typeof(DateTimeOffset),
        typeof(TimeSpan),
        typeof(Guid),
        typeof(Windows.Foundation.Point),
        typeof(Windows.Foundation.Size),
        typeof(Windows.Foundation.Rect)
    };

        private static bool IsSimpleType(Type type)
        {
            return type.IsPrimitive || ExtraSimpleTypes.Contains(type);
        }
    }
}
