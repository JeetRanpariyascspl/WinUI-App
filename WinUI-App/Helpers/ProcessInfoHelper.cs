using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace WinUI_App.Helpers
{
    internal class ProcessInfoHelper
    {
        private static readonly FileVersionInfo? _fileVersionInfo;

        public static Version? GetVersion()
        {
            return _fileVersionInfo is null
                ? null
                : new Version(_fileVersionInfo.FileMajorPart, _fileVersionInfo.FileMinorPart, _fileVersionInfo.FileBuildPart, _fileVersionInfo.FilePrivatePart);
        }
    }
}
