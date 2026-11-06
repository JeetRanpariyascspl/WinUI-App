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

        private static readonly HttpClient httpClient = CreateClient();

        private static HttpClient CreateClient()
        {
            HttpClient httpClient = new HttpClient();
            httpClient.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("WinUI-App", "1.0"));
            httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            return httpClient;
        }

        public static async Task<ReleaseInfo?> GetLatestAsync()
        {
            string Url = $"https://api.github.com/repos/{Owner}/{Repo}/releases/latest";
            string Json = await httpClient.GetStringAsync(Url);

            JsonDocument jsonDocument = JsonDocument.Parse(Json);
            JsonElement jsonElement = jsonDocument.RootElement;

            string tag = jsonElement.GetProperty("tag_name").GetString() ?? "";
            if (!Version.TryParse(tag.TrimStart('v', 'V'), out var version))
            {
                return null;
            }

            ReleaseInfo releaseInfo = new ReleaseInfo
            {
                Version = version,
                PageUrl = jsonElement.GetProperty("html_url").GetString() ?? "",
                AppName = Repo
            };

            foreach (JsonElement asset in jsonElement.GetProperty("assets").EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString() ?? "";
                if (Extensions.Any(e => name.EndsWith(e, StringComparison.OrdinalIgnoreCase)))
                {
                    releaseInfo.AssetName = name;
                    releaseInfo.AssetUrl = asset.GetProperty("browser_download_url").GetString() ?? "";
                    break;
                }
            }
            return releaseInfo;
        }

        public static async Task<string> DownloadAsync(ReleaseInfo Release, IProgress<double> Progress)
        {
            string AppPath = Path.Combine(Path.GetTempPath(), Release.AssetName);

            HttpResponseMessage httpResponseMessage = await httpClient.GetAsync(Release.AssetUrl, HttpCompletionOption.ResponseHeadersRead);
            httpResponseMessage.EnsureSuccessStatusCode();
            long total = httpResponseMessage.Content.Headers.ContentLength ?? -1L;

            Stream Source = await httpResponseMessage.Content.ReadAsStreamAsync();
            FileStream fileStream = new FileStream(AppPath, FileMode.Create, FileAccess.Write, FileShare.None);

            byte[] buffer = new byte[81920];
            long read = 0;
            int n;
            while ((n = await Source.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, n);
                read += n;
                if (total > 0) Progress.Report(read * 100.0 / total);
            }
            return AppPath;
        }

        public static async Task InstallAsync(string AppPath)
        {
            string ext = Path.GetExtension(AppPath).ToLowerInvariant();
            if (ext == ".msix" || ext == ".msixbundle")
            {
                StorageFile storageFile = await StorageFile.GetFileFromPathAsync(AppPath);
                await Launcher.LaunchFileAsync(storageFile);   // opens App Installer with an Update button
            }
            else
            {
                Process.Start(new ProcessStartInfo(AppPath) { UseShellExecute = true });
            }
        }
    }

    public class ReleaseInfo
    {
        public Version Version { get; set; } = new Version(0, 0, 0, 0);
        public string PageUrl { get; set; } = "";
        public string AssetName { get; set; } = "";
        public string AssetUrl { get; set; } = "";
        public string AppName { get; set; } = "";     // new
    }
}
