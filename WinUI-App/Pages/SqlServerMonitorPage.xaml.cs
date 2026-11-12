using Microsoft.Data.SqlClient;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using System;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.Storage;

namespace WinUI_App.Pages;

public sealed partial class SqlServerMonitorPage : Page
{
    private readonly DispatcherQueueTimer _timer;
    private bool _refreshing;
    private SavedSqlConnection? _selectedConnection;
    public ObservableCollection<MonitorFinding> Findings { get; } = [];
    public ObservableCollection<MonitorFinding> Operations { get; } = [];
    public ObservableCollection<SavedSqlConnection> SavedConnections { get; } = [];

    public SqlServerMonitorPage()
    {
        InitializeComponent();
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(10);
        _timer.Tick += async (_, _) => await RefreshAsync();
        AutoRefresh.Toggled += AutoRefresh_Toggled;
        if (ApplicationData.Current.LocalSettings.Values.TryGetValue(DatabasePage.SettingsKey, out var saved)) try { foreach (var item in JsonSerializer.Deserialize<List<SavedSqlConnection>>(saved?.ToString() ?? string.Empty) ?? []) SavedConnections.Add(item); } catch (JsonException) { }
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is SavedSqlConnection connection)
        {
            _selectedConnection = connection;
            ServerBox.Text = connection.Server;
            DatabaseBox.Text = connection.Database;
        }
    }

    private async void ConnectButton_Click(object sender,
                                           RoutedEventArgs e) => await RefreshAsync();
    private async void SavedDatabaseBox_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (SavedDatabaseBox.SelectedItem is not SavedSqlConnection item) return; _selectedConnection = item; ServerBox.Text = item.Server; DatabaseBox.Text = item.Database; await RefreshAsync(); }
    private async void RefreshButton_Click(object sender,
                                           RoutedEventArgs e) => await RefreshAsync();
    private void AutoRefresh_Toggled(object sender, RoutedEventArgs e)
    {
        if (AutoRefresh.IsOn)
            _timer.Start();
        else
            _timer.Stop();
    }

    private async Task RefreshAsync()
    {
        if (_refreshing || string.IsNullOrWhiteSpace(ServerBox.Text) ||
            string.IsNullOrWhiteSpace(DatabaseBox.Text))
            return;
        _refreshing = true;
        RefreshButton.IsEnabled = false;
        StatusBar.IsOpen = false;
        try
        {
            var selectedConnection = _selectedConnection;
            var builder = new SqlConnectionStringBuilder
            {
                DataSource = ServerBox.Text.Trim(),
                InitialCatalog = DatabaseBox.Text.Trim(),
                IntegratedSecurity = selectedConnection?.Auth != "Sql",
                Encrypt = true,
                TrustServerCertificate = selectedConnection?.Trust ?? true,
                ConnectTimeout = 10
            };
            if (selectedConnection?.Auth == "Sql")
            {
                builder.UserID = selectedConnection.User;
                builder.Password = DatabasePage.Get(selectedConnection.Id);
            }
            await using var connection = new SqlConnection(builder.ConnectionString);
            await connection.OpenAsync();
            ServerIdentityText.Text =
                $"Monitoring {connection.DataSource} · {connection.Database} · Windows authentication";
            var cpu = await ScalarAsync(
                connection,
                "SELECT TOP (1) record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') FROM (SELECT CONVERT(xml, record) AS record FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' AND record LIKE N'%<SystemHealth>%') x ORDER BY record.value('(./Record/@id)[1]', 'bigint') DESC;");
            var memory = await ScalarAsync(
                connection,
                "SELECT CAST((total_physical_memory_kb-available_physical_memory_kb)*100.0/NULLIF(total_physical_memory_kb,0) AS decimal(5,1)) FROM sys.dm_os_sys_memory;");
            var size = await ScalarAsync(
                connection,
                "SELECT CAST(SUM(size)*8.0/1024 AS decimal(18,1)) FROM sys.database_files;");
            SetPercent(CpuText, CpuBar, cpu);
            SetPercent(MemoryText, MemoryBar, memory);
            SizeText.Text = size is null ? "Unavailable" : $"{size} MB";
            var blocking = await ScalarAsync(
                connection,
                "SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id <> 0;");
            var missingIndexes = await ScalarAsync(
                connection, "SELECT COUNT(*) FROM sys.dm_db_missing_index_group_stats;");
            var slowQueries =
                await ScalarAsync(connection, "SELECT COUNT(*) FROM sys.dm_exec_query_stats;");
            var jobs = await ScalarAsync(connection, "SELECT COUNT(*) FROM msdb.dbo.sysjobs;");
            var lastBackup = await ScalarAsync(
                connection,
                "SELECT CONVERT(varchar(16), MAX(backup_finish_date), 120) FROM msdb.dbo.backupset WHERE database_name = DB_NAME();");
            Findings.Clear();
            Findings.Add(new("Blocking sessions", ValueOrUnavailable(blocking, " active")));
            Findings.Add(new("Missing-index suggestions",
                             ValueOrUnavailable(missingIndexes, " DMV records")));
            Findings.Add(
                new("Cached query statistics", ValueOrUnavailable(slowQueries, " query entries")));
            Operations.Clear();
            Operations.Add(new("SQL Agent jobs", ValueOrUnavailable(jobs, " configured")));
            Operations.Add(new("Latest backup", lastBackup?.ToString() ?? "Unavailable"));
            Operations.Add(new("Refresh interval", AutoRefresh.IsOn ? "10 seconds" : "Manual"));
            var health = 100 - (ToDouble(cpu) > 80 ? 20 : 0) - (ToDouble(memory) > 85 ? 15 : 0) -
                         (ToDouble(blocking) > 0 ? 20 : 0);
            HealthText.Text = $"{Math.Max(0, health)}/100";
            HealthDetail.Text = health >= 85 ? "Healthy"
                                : health >= 65 ? "Needs attention"
                                               : "Investigate now";
            RefreshTimeText.Text = $"Updated {DateTime.Now:t}";
        }
        catch (Exception ex)
        {
            StatusBar.Title = "Monitor connection failed";
            StatusBar.Message = ex.Message;
            StatusBar.Severity = InfoBarSeverity.Error;
            StatusBar.IsOpen = true;
        }
        finally
        {
            _refreshing = false;
            RefreshButton.IsEnabled = true;
        }
    }

    private static async Task<object?> ScalarAsync(SqlConnection c, string sql)
    {
        try
        {
            await using var cmd = new SqlCommand(sql, c) { CommandTimeout = 10 };
            var v = await cmd.ExecuteScalarAsync();
            return v == DBNull.Value ? null : v;
        }
        catch (SqlException)
        {
            return null;
        }
    }
    private static void SetPercent(TextBlock text, ProgressBar bar, object? value)
    {
        var n = ToDouble(value);
        text.Text = value is null ? "Unavailable" : $"{n:0.0}%";
        bar.Value = Math.Clamp(n, 0, 100);
    }
    private static double ToDouble(object? v) => v is null ? 0
                                                 : double.TryParse(v.ToString(), NumberStyles.Any,
                                                                   CultureInfo.InvariantCulture,
                                                                   out var n)
                                                     ? n
                                                     : 0;
    private static string ValueOrUnavailable(object? value, string suffix) =>
        value is null ? "Unavailable (permission or feature unavailable)" : $"{value}{suffix}";
}

public sealed class MonitorFinding
(string title, string detail)
{
    public string Title { get; } = title;
    public string Detail { get; } = detail;
}
