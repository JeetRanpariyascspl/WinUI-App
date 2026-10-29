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
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.ConstrainedExecution;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.ApplicationModel;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Foundation.Collections;
using Windows.System;
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

    public string AppVersion
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
        DataPackage dataPackage = new DataPackage();
        dataPackage.SetText(GitCloneTextBlock.Text);
        Clipboard.SetContent(dataPackage);
    }

    private async void CheckUpdatesButton_Click(object sender, RoutedEventArgs e)
    {
        CheckUpdatesButton.IsEnabled = false;
        CheckUpdatesButton.Content = "Checking...";

        try
        {
            var release = await UpdateService.GetLatestAsync();
            if (release == null || !Version.TryParse(AppVersion, out var currentFull))
            {
                await DialogHelper.ShowDialog(this.XamlRoot, "Error", "Couldn't read version numbers.");
                return;
            }

            // Compare as major.minor.build so "1.0.1" vs "1.0.1.0" doesn't confuse things
            var current = new Version(currentFull.Major, currentFull.Minor, Math.Max(currentFull.Build, 0));
            var latest = new Version(release.Version.Major, release.Version.Minor, Math.Max(release.Version.Build, 0));

            if (latest <= current)
            {
                await DialogHelper.ShowDialog(this.XamlRoot, "Up to Date", $"You're on the latest version (v{current}).");
                return;
            }

            bool go = await DialogHelper.ShowConfirm(this.XamlRoot, "Update Available", $"{release.AppName}\n\nCurrent version: v{current}\nNew version: v{latest}\n\nDownload and install now?", "Update", "Later");
            if (!go) return;

            // No installer attached to the release: open the release page instead
            if (string.IsNullOrEmpty(release.AssetUrl))
            {
                await Launcher.LaunchUriAsync(new Uri(release.PageUrl));
                return;
            }

            var bar = new ProgressBar { Minimum = 0, Maximum = 100, Width = 300 };
            var percentText = new TextBlock { Text = "0%", HorizontalAlignment = HorizontalAlignment.Center };
            var infoText = new TextBlock
            {
                Text = $"{release.AppName}\nVersion: v{latest}",
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            };

            var panel = new StackPanel { Spacing = 10 };
            panel.Children.Add(infoText);
            panel.Children.Add(bar);
            panel.Children.Add(percentText);

            var progressDialog = new ContentDialog
            {
                Title = "Downloading update...",
                Content = panel,
                XamlRoot = this.XamlRoot
            };
            _ = progressDialog.ShowAsync();

            string path;
            try
            {
                var progress = new Progress<double>(p =>
                {
                    bar.Value = p;
                    percentText.Text = $"{p:0}%";
                });
                path = await UpdateService.DownloadAsync(release, progress);
            }
            finally
            {
                progressDialog.Hide();
            }

            await UpdateService.InstallAsync(path);
            Application.Current.Exit();
        }
        catch (HttpRequestException)
        {
            await DialogHelper.ShowDialog(this.XamlRoot, "No Connection", "Couldn't reach GitHub or no release found. Check your internet and repo name.");
        }
        catch (Exception ex)
        {
            await DialogHelper.ShowDialog(this.XamlRoot, "Update Failed", ex.Message);
        }
        finally
        {
            CheckUpdatesButton.Content = "Check for Updates";
            CheckUpdatesButton.IsEnabled = true;
        }
    }
}
