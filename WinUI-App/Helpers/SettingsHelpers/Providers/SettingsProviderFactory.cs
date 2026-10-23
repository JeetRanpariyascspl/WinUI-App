using Windows.Storage;

namespace WinUI_App.Helpers.SettingsHelpers.Providers
{
    internal static class SettingsProviderFactory
    {
        public static ISettingsProvider CreateProvider()
        {
            return new ApplicationDataSettingsProvider(ApplicationData.Current.LocalSettings);
        }
    }
}
