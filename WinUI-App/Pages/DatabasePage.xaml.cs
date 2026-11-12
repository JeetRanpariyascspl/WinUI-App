using Microsoft.Data.SqlClient;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using Windows.Security.Credentials;
using Windows.Storage;
using System.Runtime.InteropServices;
namespace WinUI_App.Pages;

public sealed partial class DatabasePage : Page
{
    public const string SettingsKey = "SavedSqlConnections";
    const string Key = SettingsKey, Prefix = "WinUI-App.SqlServer.";
    string? id;
    public ObservableCollection<SavedSqlConnection> Items { get; } = [];
    public DatabasePage()
    {
        InitializeComponent();
        Auth.SelectedIndex = 0;
        Load();
    }
    void Load()
    {
        if (ApplicationData.Current.LocalSettings.Values.TryGetValue(Key, out var v))
            try
            {
                foreach (var x in JsonSerializer.Deserialize<List<SavedSqlConnection>>(
                             v?.ToString() ?? "") ??
                         [])
                    Items.Add(x);
            }
            catch
            {
            }
    }
    void Persist() => ApplicationData.Current.LocalSettings.Values[Key] =
        JsonSerializer.Serialize(Items);
    void AuthChanged(object s, SelectionChangedEventArgs e)
    {
        User.IsEnabled = Password.IsEnabled = Auth.SelectedIndex == 1;
    }
    async void Test(object s, RoutedEventArgs e)
    {
        try
        {
            await using var c = new SqlConnection(Cs());
            await c.OpenAsync();
            Show("Connection succeeded", InfoBarSeverity.Success);
        }
        catch (Exception x)
        {
            Show(x.Message, InfoBarSeverity.Error);
        }
    }
    void Save(object s, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(Name.Text) || string.IsNullOrWhiteSpace(Server.Text) ||
            string.IsNullOrWhiteSpace(Database.Text))
        {
            Show("Enter name, server, and database.", InfoBarSeverity.Warning);
            return;
        }
        var x = Items.FirstOrDefault(a => a.Id == id);
        if (x is null)
        {
            x = new() { Id = Guid.NewGuid().ToString("N") };
            Items.Add(x);
            id = x.Id;
        }
        x.Name = Name.Text.Trim();
        x.Server = Server.Text.Trim();
        x.Database = Database.Text.Trim();
        x.Auth = Auth.SelectedIndex == 1 ? "Sql" : "Windows";
        x.User = User.Text.Trim();
        x.Trust = Trust.IsChecked == true;
        if (x.Auth == "Sql")
            Put(id, Password.Password);
        else
            Del(id);
        Persist();
        List.SelectedItem = x;
        Show("Connection saved", InfoBarSeverity.Success);
    }
    void New(object s, RoutedEventArgs e)
    {
        List.SelectedItem = null;
        id = null;
        Name.Text = Server.Text = Database.Text = User.Text = Password.Password = "";
        Auth.SelectedIndex = 0;
        Trust.IsChecked = true;
    }
    void Changed(object s, SelectionChangedEventArgs e)
    {
        var x = List.SelectedItem as SavedSqlConnection;
        Analyze.IsEnabled = Remove.IsEnabled = x is not null;
        if (x is null)
            return;
        id = x.Id;
        Name.Text = x.Name;
        Server.Text = x.Server;
        Database.Text = x.Database;
        Auth.SelectedIndex = x.Auth == "Sql" ? 1 : 0;
        User.Text = x.User;
        Password.Password = Get(x.Id);
        Trust.IsChecked = x.Trust;
    }
    void Open(object s, RoutedEventArgs e)
    {
        if (List.SelectedItem is SavedSqlConnection x)
            App.MainWindow.NavigateToSqlServerMonitor(x);
    }
    void Delete(object s, RoutedEventArgs e)
    {
        if (List.SelectedItem is not SavedSqlConnection x)
            return;
        Del(x.Id);
        Items.Remove(x);
        Persist();
        New(s, e);
    }
    string Cs()
    {
        var b = new SqlConnectionStringBuilder
        {
            DataSource = Server.Text,
            InitialCatalog = Database.Text,
            IntegratedSecurity = Auth.SelectedIndex != 1,
            Encrypt = true,
            TrustServerCertificate = Trust.IsChecked == true
        };
        if (Auth.SelectedIndex == 1)
        {
            b.UserID = User.Text;
            b.Password = Password.Password;
        }
        return b.ConnectionString;
    }
    static void Put(string i, string p)
    {
        Del(i);

        if (string.IsNullOrWhiteSpace(p))
            return;

        new PasswordVault().Add(new PasswordCredential(Prefix + i, "Password", p));
    }
    public static string Get(string i)
    {
        var resource = Prefix + i;

        try
        {
            var vault = new PasswordVault();
            var credential = vault.FindAllByResource(resource).FirstOrDefault();
            if (credential is null)
                return "";

            credential.RetrievePassword();
            return credential.Password;
        }
        catch (COMException ex) when (
            (uint)ex.HResult == 0x80070490u || // Element not found
            ex.Message.Contains("Cannot find credential in Vault", StringComparison.OrdinalIgnoreCase))
        {
            return "";
        }
        catch
        {
            return "";
        }
    }

    static void Del(string i)
    {
        var resource = Prefix + i;

        try
        {
            var vault = new PasswordVault();
            foreach (var credential in vault.FindAllByResource(resource))
                vault.Remove(credential);
        }
        catch (COMException ex) when (
            (uint)ex.HResult == 0x80070490u ||
            ex.Message.Contains("Cannot find credential in Vault", StringComparison.OrdinalIgnoreCase))
        {
            // No password exists for this resource; nothing to delete.
        }
        catch
        {
            // Ignore any other vault errors.
        }
    }
    void Show(string m, InfoBarSeverity v)
    {
        Status.Message = m;
        Status.Severity = v;
        Status.IsOpen = true;
    }
}
public sealed class SavedSqlConnection
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Server { get; set; } = "";
    public string Database { get; set; } = "";
    public string Auth { get; set; } = "Windows";
    public string User { get; set; } = "";
    public bool Trust { get; set; } = true;
    public string Summary => $"{Server} · {Database}";
}
