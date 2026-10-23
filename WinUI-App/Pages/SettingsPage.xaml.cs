using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Foundation;
using Windows.Foundation.Collections;
using WinUI_App.Helpers;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace WinUI_App.Pages;

/// <summary>
/// An empty page that can be used on its own or navigated to within a Frame.
/// </summary>
public sealed partial class SettingsPage : Page
{
    private int LastNavigationSelectionMode = 0;

    public SettingsPage()
    {
        InitializeComponent();
        OnSettingsPageLoaded();
    }

    private void OnSettingsPageLoaded()
    {
        if (Application.Current is not App app)
        {
            return;
        }

        ThemeMode.SelectedIndex = app.CurrentTheme switch
        {
            ElementTheme.Light => 0,
            ElementTheme.Dark => 1,
            _ => 2
        };

        if (App.MainWindow.NavigationView.PaneDisplayMode == NavigationViewPaneDisplayMode.Auto)
        {
            NavigationLocation.SelectedIndex = 0;
        }
        else
        {
            NavigationLocation.SelectedIndex = 1;
        }
        LastNavigationSelectionMode = NavigationLocation.SelectedIndex;
    }

    private void ThemeMode_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Application.Current is not App app)
        {
            return;
        }

        var theme = ThemeMode.SelectedIndex switch
        {
            0 => ElementTheme.Light,
            1 => ElementTheme.Dark,
            2 => ElementTheme.Default,
            _ => (ElementTheme?)null
        };

        if (theme.HasValue)
        {
            app.SetTheme(theme.Value);
        }
    }

    private void NavigationLocation_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NavigationLocation.SelectedIndex != LastNavigationSelectionMode)
        {
            NavigationOrientationHelper.IsLeftModeForElement(NavigationLocation.SelectedIndex == 0);
            LastNavigationSelectionMode = NavigationLocation.SelectedIndex;
        }
    }

    public string Version
    {
        get
        {
            return ProcessInfoHelper.GetVersion() is Version version
                ? string.Format("{0}.{1}.{2}.{3}", version.Major, version.Minor, version.Build, version.Revision)
                : string.Empty;
        }
    }

    private void CloneRepoCard_Click(object sender, RoutedEventArgs e)
    {

    }
}
