using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace WinUI_App.Helpers
{
    internal class ProcessInfoHelper
    {
        private static readonly FileVersionInfo? _fileVersionInfo;
        private static readonly Process _process;

        static ProcessInfoHelper()
        {
            _process = Process.GetCurrentProcess();
            _fileVersionInfo = _process.MainModule?.FileVersionInfo;
        }

        public static Version? GetVersion()
        {
            return _fileVersionInfo is null
                ? null
                : new Version(_fileVersionInfo.FileMajorPart, _fileVersionInfo.FileMinorPart, _fileVersionInfo.FileBuildPart, _fileVersionInfo.FilePrivatePart);
        }
    }
}
