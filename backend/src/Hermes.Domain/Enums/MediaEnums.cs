namespace Hermes.Domain.Enums;

public enum UserRole
{
    Member = 0,
    Admin = 1
}

public enum LibraryMediaType
{
    Movies = 0,
    Series = 1,
    Music = 2
}

public enum StreamKind
{
    Video = 0,
    Audio = 1,
    Subtitle = 2
}

public enum VideoQualityPreset
{
    DirectPlay = 0,
    P1080 = 1,
    P720 = 2,
    P480 = 3
}

public enum AudioQualityPreset
{
    Lossless = 0,
    VeryHigh320 = 1,
    High160 = 2,
    Medium96 = 3,
    Low64 = 4
}

public enum PlaybackState
{
    Stopped = 0,
    Playing = 1,
    Paused = 2
}

public enum RepeatMode
{
    Off = 0,
    All = 1,
    One = 2
}

public enum ThemeSurfacePreset
{
    ObsidianGlow = 0,
    OledBlack = 1,
    Slate = 2
}

public enum HardwareAccelerationMode
{
    None = 0,
    Auto = 1,
    Nvenc = 2,
    Vaapi = 3,
    Qsv = 4,
    VideoToolbox = 5
}
