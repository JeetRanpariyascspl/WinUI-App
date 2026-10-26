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
using WinUI_App.Pages;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace WinUI_App
{
    /// <summary>
    /// An empty window that can be used on its own or navigated to within a Frame.
    /// </summary>
    public sealed partial class MainWindow : Window
    {
        public NavigationView NavigationView
        {
            get { return NavigationViewControl; }
        }

        public MainWindow()
        {
            InitializeComponent();
            SetWindowProperties();
            NavigationViewControl.SelectedItem = Home;
            rootFrame.Navigate(typeof(HomePage));
        }

        public void NavigateToSettings()
        {
            NavigationViewControl.SelectedItem = NavigationViewControl.SettingsItem;
            if (rootFrame.CurrentSourcePageType != typeof(SettingsPage))
            {
                rootFrame.Navigate(typeof(SettingsPage));
            }
        }

        private void SetWindowProperties()
        {
            //this.Title = "My WinUI App";
            this.ExtendsContentIntoTitleBar = true;
            this.SetTitleBar(TitleBar);
            //this.AppWindow.SetIcon("/Image/WinUI-App.ico");
            //this.AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        }

        private void NavigationViewControl_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.IsSettingsSelected)
            {
                if (rootFrame.CurrentSourcePageType != typeof(SettingsPage))
                {
                    rootFrame.Navigate(typeof(SettingsPage));
                }
            }
            else
            {
                NavigationViewItemBase navigationViewItemBase = args.SelectedItemContainer;
                if (navigationViewItemBase == Home)
                {
                    if (rootFrame.CurrentSourcePageType != typeof(HomePage))
                    {
                        rootFrame.Navigate(typeof(HomePage));
                    }
                }
            }
        }

        private void TitleBar_PaneToggleRequested(TitleBar sender, object args)
        {
            NavigationViewControl.IsPaneOpen = !NavigationViewControl.IsPaneOpen;
        }
    }
}
