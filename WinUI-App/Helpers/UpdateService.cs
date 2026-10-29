using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.Storage;
using Windows.System;

namespace WinUI_App.Helpers
{
    internal class UpdateService
    {
        private const string Owner = "JeetRanpariyascspl";
        private const string Repo = "WinUI-App";
        private static readonly string[] Extensions = { ".msix", ".msixbundle", ".msi", ".exe" };

        private static readonly HttpClient _http = CreateClient();

        private static HttpClient CreateClient()
        {
            var c = new HttpClient();
            c.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("WinUI-App", "1.0"));
            c.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            return c;
        }

        public static async Task<ReleaseInfo?> GetLatestAsync()
        {
            var url = $"https://api.github.com/repos/{Owner}/{Repo}/releases/latest";
            var json = await _http.GetStringAsync(url);

            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var tag = root.GetProperty("tag_name").GetString() ?? "";
            if (!Version.TryParse(tag.TrimStart('v', 'V'), out var version))
                return null;

            var info = new ReleaseInfo
            {
                Version = version,
                PageUrl = root.GetProperty("html_url").GetString() ?? "",
                AppName = Repo   // "WinUI-App"; change to a friendly name if you like
            };

            foreach (var asset in root.GetProperty("assets").EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString() ?? "";
                if (Extensions.Any(e => name.EndsWith(e, StringComparison.OrdinalIgnoreCase)))
                {
                    info.AssetName = name;
                    info.AssetUrl = asset.GetProperty("browser_download_url").GetString() ?? "";
                    break;
                }
            }
            return info;
        }

        public static async Task<string> DownloadAsync(ReleaseInfo release, IProgress<double> progress)
        {
            var path = Path.Combine(Path.GetTempPath(), release.AssetName);

            using var response = await _http.GetAsync(release.AssetUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength ?? -1L;

            using var source = await response.Content.ReadAsStreamAsync();
            using var target = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);

            var buffer = new byte[81920];
            long read = 0;
            int n;
            while ((n = await source.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await target.WriteAsync(buffer, 0, n);
                read += n;
                if (total > 0) progress.Report(read * 100.0 / total);
            }
            return path;
        }

        public static async Task InstallAsync(string path)
        {
            var ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".msix" || ext == ".msixbundle")
            {
                var file = await StorageFile.GetFileFromPathAsync(path);
                await Launcher.LaunchFileAsync(file);   // opens App Installer with an Update button
            }
            else
            {
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
        }
    }

    public class ReleaseInfo
    {
        public Version Version { get; set; } = new Version(0, 0, 0);
        public string PageUrl { get; set; } = "";
        public string AssetName { get; set; } = "";
        public string AssetUrl { get; set; } = "";
        public string AppName { get; set; } = "";     // new
    }
}
