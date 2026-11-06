using Microsoft.UI;
using Microsoft.UI.Xaml;
using System;
using Windows.UI;

namespace WinUI_App.Helpers
{
    internal class TitleBarHelper
    {
        public static void ApplySystemThemeToCaptionButtons(Window window, ElementTheme currentTheme)
        {
            if (window is null)
            {
                throw new ArgumentNullException(nameof(window));
            }

            if (window.AppWindow is not null)
            {
                Color Themecolor = currentTheme == ElementTheme.Dark ? Microsoft.UI.Colors.White : Microsoft.UI.Colors.Black;
                window.AppWindow.TitleBar.ButtonForegroundColor = Themecolor;
                window.AppWindow.TitleBar.ButtonHoverForegroundColor = Themecolor;

                Color backgroundHoverColor = currentTheme == ElementTheme.Dark ? Color.FromArgb(24, 255, 255, 255) : Color.FromArgb(24, 0, 0, 0);
                window.AppWindow.TitleBar.ButtonHoverBackgroundColor = backgroundHoverColor;
            }
        }
    }
}
