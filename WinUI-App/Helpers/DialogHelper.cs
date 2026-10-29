using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;

namespace WinUI_App.Helpers
{
    internal class DialogHelper
    {
        // Simple message popup with an OK button
        public static async Task ShowDialog(XamlRoot xamlRoot, string title, string message)
        {
            var dialog = new ContentDialog
            {
                Title = title,
                Content = message,
                CloseButtonText = "OK",
                XamlRoot = xamlRoot
            };
            await dialog.ShowAsync();
        }

        // Two-button popup. Returns true if the primary button was clicked.
        public static async Task<bool> ShowConfirm(XamlRoot xamlRoot, string title, string message,
                                                   string primary = "Yes", string close = "No")
        {
            var dialog = new ContentDialog
            {
                Title = title,
                Content = message,
                PrimaryButtonText = primary,
                CloseButtonText = close,
                XamlRoot = xamlRoot
            };
            var result = await dialog.ShowAsync();
            return result == ContentDialogResult.Primary;
        }
    }
}
