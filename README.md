# WinUI-App

A Windows desktop application built with **WinUI 3** and **.NET 10**. The app provides a modern Mica-backed window, title-bar search, and NavigationView-based Home and Settings pages.

## Features

- Native WinUI 3 desktop experience with a Mica system backdrop
- Custom title bar with a search box
- NavigationView shell with Home and Settings pages
- Settings for app theme and navigation placement
- Single-project MSIX packaging configured for 64-bit Windows

## Tech stack

- .NET 10 for Windows
- Windows App SDK / WinUI 3
- CommunityToolkit WinUI Settings Controls
- MSIX single-project packaging

## Requirements

- Windows 10 version 1809 (build 17763) or later
- .NET 10 SDK
- Visual Studio 2022 with the **.NET desktop development** and **Windows application development** workloads, or the .NET CLI

## Getting started

1. Clone the repository:

   ```powershell
   git clone https://github.com/JeetRanpariyascspl/WinUI-App.git
   cd WinUI-App
   ```

2. Restore dependencies and build the application:

   ```powershell
   dotnet restore
   dotnet build .\WinUI-App.slnx
   ```

3. Run it from Visual Studio by selecting the `WinUI-App` project and pressing **F5**, or use the CLI:

   ```powershell
   dotnet run --project .\WinUI-App\WinUI-App.csproj
   ```

## Project layout

```text
WinUI-App.slnx                 Solution file
WinUI-App/
  App.xaml                     Application resources and startup configuration
  MainWindow.xaml              Window shell, title bar, and navigation
  Pages/
    HomePage.xaml              Home page
    SettingsPage.xaml          Appearance, navigation, and project settings
  Assets/                      App icons and tile assets
  Properties/PublishProfiles/  Platform-specific publish settings
Installer/                     Installer-related project files
AppPackages/                   Generated app packages
```

## Packaging

The project is configured for x64 MSIX packaging. In Visual Studio, right-click the project and select **Package and Publish**. Generated packages are written to `AppPackages/`.

## Notes

- The application targets `net10.0-windows10.0.19041.0` and supports Windows 10 build 17763 or newer.
- The project uses the shared .NET and Windows App Runtime rather than bundling them into the app package.

## License

No license has been specified for this repository.
