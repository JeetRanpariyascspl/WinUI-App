using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Text;
using WinUI_App.Helpers.SettingsHelpers;

namespace WinUI_App.Helpers
{
    class NavigationOrientationHelper
    {
        public static bool IsLeftMode()
        {
            return SettingsHelper.Current.IsLeftMode;
        }

        public static void IsLeftModeForElement(bool isLeftMode)
        {
            UpdateNavigationViewForElement(isLeftMode);
            SettingsHelper.Current.IsLeftMode = isLeftMode;
        }

        public static void UpdateNavigationViewForElement(bool isLeftMode)
        {
            NavigationView _navView = App.MainWindow.NavigationView;
            if (isLeftMode)
            {
                _navView.PaneDisplayMode = NavigationViewPaneDisplayMode.Auto;
            }
            else
            {
                _navView.PaneDisplayMode = NavigationViewPaneDisplayMode.Top;
            }
        }
    }
}
