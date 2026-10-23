using System;
using System.Collections.Generic;
using System.Text;
using WinUI_App.Helpers.SettingsHelpers.Providers;

namespace WinUI_App.Helpers.SettingsHelpers
{
    public partial class SettingsHelper : ObservableSettings
    {
        private static readonly SettingsHelper instance = new(SettingsProviderFactory.CreateProvider());
        public static SettingsHelper Current => instance;
        private SettingsHelper(ISettingsProvider provider) : base(provider) { }

        public bool IsLeftMode
        {
            get => GetOrCreateDefault<bool>(true);
            set => Set(value);
        }
    }
}
