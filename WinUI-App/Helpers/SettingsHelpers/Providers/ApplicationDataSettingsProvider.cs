using Windows.Storage;

namespace WinUI_App.Helpers.SettingsHelpers.Providers
{
    internal sealed class ApplicationDataSettingsProvider : ISettingsProvider
    {
        private readonly ApplicationDataContainer localSettings;

        public ApplicationDataSettingsProvider(ApplicationDataContainer localSettings)
        {
            this.localSettings = localSettings;
        }

        public bool Contains(string key) => localSettings.Values.ContainsKey(key);

        public object? Get(string key) =>
            localSettings.Values.TryGetValue(key, out var value) ? value : null;

        public T? Get<T>(string key) => Get(key) is T value ? value : default;

        public void Set(string key, object value) => localSettings.Values[key] = value;

        public void Set<T>(string key, T value) => localSettings.Values[key] = value;
    }
}
